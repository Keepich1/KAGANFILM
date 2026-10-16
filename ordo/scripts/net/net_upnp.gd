class_name NetUpnp
extends RefCounted
## «Узнать мой адрес в интернете» (ТЗ §16 «Адрес в интернете»; владелец — NET) — только в справке, у способа «Без
## программ — для знатоков». Сначала UPnP роутера (discover блокирует — всё в отдельном потоке): он же открывает
## порт 7777 (UDP) и показывает, если провайдер не даёт своего адреса (внешний адрес роутера из 10.x, 172.16–31.x,
## 192.168.x или 100.64/10 — «у вашего провайдера так не выйдет»). Запасной путь — сайт ipify (адрес есть, порт
## не открыт). Порт открывается С АРЕНДОЙ (LEASE, 2 ч) и продлевается, пока игра создана (NetSession, раз в RENEW):
## упала игра или её сняли в диспетчере задач — роутер сам закроет порт.
## «Отмена» у хозяина, закрытый лист «Игра с другом» и выход — cancel(): поиск, если он ещё идёт, бросается (поток
## сам закроет порт, если роутер успел его открыть), открытый порт закрывается. Перед выходом из игры поток
## дожидаются (shutdown): он пишет в этот объект, а ipify бросает сразу, роутер — не дольше пары секунд.
##
## Итог — result, когда busy снова false (и сигнал finished): {kind, addr}
##   green — адрес нашли, порт открыт; gold — адрес есть, а роутер порт сам не открыл;
##   red   — у провайдера так не выйдет (адрес не свой); none — не узнать (нет роутера с UPnP и нет интернета)
##           или поиск отменили ({cancelled: true}).

signal finished(result: Dictionary)

const LEASE := 7200
const RENEW := 1800.0
const DESC := "Ordo"
const IPIFY_HOST := "api.ipify.org"
const HTTP_WAIT_MS := 6000

var busy := false
var mapped := false
var result := {}

var _thread: Thread
var _renew: Thread
var _port := NetProto.PORT
var _gateway: UPNPDevice
var _out := {}
## Поиск отменили: поток бросает дело на ближайшем шаге (порт, если открыл, закрывает сам)
var _cancel := false


## Узнать адрес (поток); итог — poll() на главном потоке (NetSession._process) → finished
func find(port: int) -> void:
	if busy:
		return
	busy = true
	_cancel = false
	_port = port
	_out = {}
	_thread = Thread.new()
	_thread.start(_work)


## Главный поток: поток кончил — итог и сигнал
func poll() -> void:
	if _renew != null and not _renew.is_alive():
		_renew.wait_to_finish()
		_renew = null
	if _thread == null or _thread.is_alive():
		return
	_finish_find()


func _finish_find() -> void:
	_thread.wait_to_finish()
	_thread = null
	busy = false
	result = _out
	if bool(result.get("mapped", false)):
		if _cancel:
			# отменили, когда роутер уже открыл порт, — закрыть
			_gateway.delete_port_mapping(_port, "UDP")
			result = {"kind": "none", "addr": "", "cancelled": true}
		else:
			mapped = true
	finished.emit(result)


## Продлить аренду порта (пока игра создана) — в потоке, игра не ждёт роутер
func renew() -> void:
	if not mapped or _gateway == null or busy or _renew != null:
		return
	var gw := _gateway
	var p := _port
	_renew = Thread.new()
	_renew.start(func() -> void: gw.add_port_mapping(p, p, DESC, "UDP", LEASE))


## Бросить поиск (если идёт) и закрыть порт на роутере: «Отмена» у хозяина, лист «Игра с другом» закрыт, выход
func cancel() -> void:
	if busy:
		_cancel = true
	remove()


## Закрыть порт на роутере (быстрый запрос по своей сети)
func remove() -> void:
	if _renew != null:
		_renew.wait_to_finish()
		_renew = null
	if not mapped or _gateway == null:
		return
	mapped = false
	_gateway.delete_port_mapping(_port, "UDP")


## Выход из игры: поиск отменить и дождаться потоков (они пишут в этот объект), порт закрыть
func shutdown() -> void:
	if _thread != null:
		_cancel = true
		_finish_find()
	remove()


func _work() -> void:
	var u := UPNP.new()
	var err := u.discover(2000, 2, "InternetGatewayDevice")
	if _cancel:
		_out = {"kind": "none", "addr": "", "cancelled": true}
		return
	var gw: UPNPDevice = u.get_gateway() if err == UPNP.UPNP_RESULT_SUCCESS else null
	if gw != null and gw.is_valid_gateway():
		var ext := gw.query_external_address()
		if ext != "" and NetAddr.is_not_public(ext):
			_out = {"kind": "red", "addr": ""}
			return
		if ext != "" and not _cancel:
			var m := gw.add_port_mapping(_port, _port, DESC, "UDP", LEASE)
			_gateway = gw
			if m == UPNP.UPNP_RESULT_SUCCESS:
				if _cancel:
					# отменили, пока роутер открывал порт, — закрыть сразу
					gw.delete_port_mapping(_port, "UDP")
					_out = {"kind": "none", "addr": "", "cancelled": true}
				else:
					_out = {"kind": "green", "addr": ext, "mapped": true}
			else:
				_out = {"kind": "gold", "addr": ext}
			return
	if _cancel:
		_out = {"kind": "none", "addr": "", "cancelled": true}
		return
	var addr := _ipify()
	if addr != "":
		_out = {"kind": "red" if NetAddr.is_not_public(addr) else "gold", "addr": addr}
	else:
		_out = {"kind": "none", "addr": "", "cancelled": _cancel}


## Свой адрес в интернете с сайта ipify (запасной путь): «» — не вышло или поиск отменили
func _ipify() -> String:
	var http := HTTPClient.new()
	if http.connect_to_host("https://" + IPIFY_HOST, 443) != OK:
		return ""
	var t0 := Time.get_ticks_msec()
	while http.get_status() in [HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING]:
		http.poll()
		OS.delay_msec(20)
		if _cancel or Time.get_ticks_msec() - t0 > HTTP_WAIT_MS:
			return ""
	if http.get_status() != HTTPClient.STATUS_CONNECTED:
		return ""
	if http.request(HTTPClient.METHOD_GET, "/", ["User-Agent: Ordo"]) != OK:
		return ""
	while http.get_status() == HTTPClient.STATUS_REQUESTING:
		http.poll()
		OS.delay_msec(20)
		if _cancel or Time.get_ticks_msec() - t0 > HTTP_WAIT_MS:
			return ""
	if not http.has_response() or http.get_response_code() != 200:
		return ""
	var body := PackedByteArray()
	while http.get_status() == HTTPClient.STATUS_BODY:
		http.poll()
		body.append_array(http.read_response_body_chunk())
		if _cancel or Time.get_ticks_msec() - t0 > HTTP_WAIT_MS:
			break
		OS.delay_msec(5)
	var s := body.get_string_from_utf8().strip_edges()
	return s if NetAddr.is_v4(s) else ""
