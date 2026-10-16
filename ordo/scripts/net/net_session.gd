class_name NetSession
extends Node
## Связь двух игр (ТЗ §16 «Город по сети с другом»; владелец — NET): ENet по UDP 7777 и SceneMultiplayer со
## сверкой версий в первом пакете (auth_callback, NetProto), лобби (сторона и номер партии хозяина), ответ друга
## (пинг), «пока» и переподключение посреди партии. Живёт в /root/NetSession — переживает смену сцены
## (лобби → «Город»); партию (NetMatch) забирает GameDriver.
##
## Хозяин (host): сервер ENet (max_clients ≥ 2 — иначе третьего ENet молча не пустит, и тот увидит «Друг не
## ответил»). Первый пакет друга читает auth_callback: другая версия, место занято — отказ с причиной (send_auth) и
## не в том же кадре отключение: disconnect_peer чистит очередь отправки, причина не дошла бы. Друг, прочитав
## причину, отключается сам; запасной таймер REFUSE_HOLD, потом peer_disconnect_later.
## Друг (guest): клиент ENet к адресу хозяина; ждёт CONNECT_LIMIT секунд.
## Вышел сам и пропала связь различимы только так: уходящий («Отмена», «Выйти», закрытие окна) шлёт BYE и
## отключается, когда оно ушло; отключение без BYE — «Связь с другом пропала». Пришедшее BYE — окончательно сразу
## (друг ушёл: лобби и партия узнают в тот же миг, а не когда ENet заметит отключение — через 8–20 с).
## Закрытие окна (крестик) — как «Выйти»: BYE, и игра закрывается, когда оно ушло (не дольше BYE_WAIT) и поиск
## адреса в интернете (если шёл) кончился.
## Посреди партии друг стучится снова сам (тот же адрес); у него новый номер ENet, поэтому хозяин узнаёт его по
## метке партии (token — случайное число, выданное при входе), а не по номеру.
##
## События для лобби — сигнал event(вид, данные):
##   хозяин: friend_joined, friend_refused {why, their, verdict}, friend_left, friend_lost
##   друг:   reached (связь есть, сверяем версии), joined, refused {why: version|busy|no_match, their, verdict},
##           connect_failed {why}, lobby {side, seed}, start, host_left, host_lost
##   оба:    ping {rtt, slow}
## Ключи проверок: --net_bind=127.0.0.1 (слушать только свой компьютер: Windows не спросит про доступ к сети),
## --net_port=N (другой порт — только проверки), --net_no_save (не запоминать адрес друга).

signal event(kind: StringName, info: Dictionary)

enum Role { NONE, HOST, GUEST }

const NODE_NAME := "NetSession"
## Подключение: предел ожидания, с (лобби: «ещё 9 секунд»)
const CONNECT_LIMIT := 15.0
const PING_EVERY := 0.5
## Ответ друга дольше этого — «Связь медленная» (ТЗ §16: четверть секунды); быстрее GOOD_MS — снова хорошая
const SLOW_MS := 250.0
const GOOD_MS := 200.0
## Отказанного хозяин держит столько секунд (причина успевает дойти), потом отключает
const REFUSE_HOLD := 2.5
const AUTH_TIMEOUT := 6.0
## Посреди партии: друг не слышен столько секунд — подключившийся стучится заново сам (ENet может ещё не заметить)
const SILENCE_LOST := 8.0
const RECONNECT_EVERY := 2.0
## ENet: обрыв — после 8–20 с молчания (по умолчанию 5–30 с)
const ENET_TIMEOUT := Vector3i(32, 8000, 20000)
## Уходящий ждёт, пока BYE уйдёт, не дольше
const BYE_WAIT := 1.5

var role := Role.NONE
var api: SceneMultiplayer
var peer: ENetMultiplayerPeer
var port := NetProto.PORT
## Друг: адрес хозяина
var addr := ""
## Номер друга в ENet (у друга хозяин — 1); 0 — друга нет
var friend_id := 0
## Версия друга из его первого пакета
var friend_info := {}
## Метка партии: выдаёт хозяин при входе, друг предъявляет при переподключении
var token := 0
## Ответ друга, мс (−1 — ещё не мерили); медленная связь
var rtt_ms := -1.0
var slow := false
## Лобби: сторона хозяина (0 — Коканд, 1 — кыпчаки) и номер партии
var lobby_side := 0
var lobby_seed := 0
## Партия (после START) и забрала ли её игра
var net_match: NetMatch
var match_taken := false
## Узнать адрес в интернете (справка) и порт на роутере
var upnp: NetUpnp

var _mine := {}
var _accepted := 0
var _replaced := {}
var _bye_from := {}
var _refused := {}
var _connect_t := -1.0
var _ping_t := 0.0
var _heard_t := 0.0
var _reconnecting := false
var _reconnect_t := 0.0
var _leaving := -1.0
var _upnp_t := 0.0
## Пока отпускаем ENet, его сигналы не слушаем (set_multiplayer_peer(null) шлёт их сразу)
var _quiet := false
## Отпущенные ENet и SceneMultiplayer живут до следующего кадра
var _old: Array[RefCounted] = []
## Внутри SceneMultiplayer.poll() (его сигналы и сверка) ENet отпускать нельзя — poll читает его дальше: такие
## дела и события для лобби ждут конца poll (_later)
var _in_poll := false
var _later: Array[Callable] = []
## Окно закрыли: ждём, пока «пока» уйдёт (сессии больше нет) и поиск адреса кончится, — потом закрыть игру
var _quit_pending := false


## Сессия в /root (одна на игру); нет — создать
static func get_or_create(tree: SceneTree) -> NetSession:
	var n := tree.root.get_node_or_null(NODE_NAME) as NetSession
	if n == null:
		n = NetSession.new()
		n.name = NODE_NAME
		tree.root.add_child(n)
	return n


static func current(tree: SceneTree) -> NetSession:
	return tree.root.get_node_or_null(NODE_NAME) as NetSession if tree else null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	NetVersion.start()


## Своя версия (первый пакет); считается один раз
func mine() -> Dictionary:
	if _mine.is_empty():
		_mine = NetVersion.info()
	return _mine


func active() -> bool:
	return role != Role.NONE


func connected() -> bool:
	return friend_id != 0 and api != null and api.get_peers().has(friend_id)


# ================================================================= хозяин

## Создать игру: сервер на порту (7777). Не вышло (порт занят — открыто второе окно «Ордо») — ошибка
func host(p_port := -1) -> Error:
	close_now()
	port = p_port if p_port > 0 else _arg_port()
	# порт занят (почти всегда — второе окно «Ордо») — узнать заранее и тихо: ENet при неудаче пишет ошибку в журнал
	var probe := PacketPeerUDP.new()
	if probe.bind(port, _bind_ip()) != OK:
		return ERR_ALREADY_IN_USE
	probe.close()
	var p := ENetMultiplayerPeer.new()
	p.set_bind_ip(_bind_ip())
	var err := p.create_server(port, NetProto.MAX_CLIENTS, NetProto.CHANNELS)
	if err != OK:
		return err
	p.host.compress(ENetConnection.COMPRESS_NONE)
	_use(p)
	role = Role.HOST
	token = 0
	lobby_seed = 0
	_set_quit_guard(true)
	return OK


## Сторона и номер партии хозяина — другу (он видит сразу)
func send_lobby(side: int, p_seed: int) -> void:
	lobby_side = side
	lobby_seed = p_seed
	if role == Role.HOST and connected():
		send(NetProto.msg(NetProto.Msg.LOBBY, PackedInt32Array([side, p_seed])))


## «Начать игру»: обоим — одна партия (номер, стороны, карта, правила, задержка приказов)
func start_match(side: int, p_seed: int) -> NetMatch:
	if role != Role.HOST or not connected():
		return null
	var delay := NetMatch.delay_for(rtt_ms)
	send(NetProto.msg(NetProto.Msg.START, PackedInt32Array([p_seed, side, 0, 0, delay])))
	_make_match(p_seed, side, 0, delay)
	return net_match


# ================================================================= друг

## Подключиться к хозяину; keep_match — переподключение посреди партии (метка партии та же)
func join(p_addr: String, p_port := -1, keep_match := false) -> Error:
	if keep_match:
		_release()
	else:
		close_now()
	port = p_port if p_port > 0 else _arg_port()
	addr = p_addr
	var p := ENetMultiplayerPeer.new()
	# проверки (--net_bind=127.0.0.1): и клиент слушает только свой компьютер — Windows не спросит про сеть
	var local_port := 0
	if _bind_ip() != "*":
		p.set_bind_ip(_bind_ip())
		local_port = 20000 + randi() % 20000
	var err := p.create_client(p_addr, port, NetProto.CHANNELS, 0, 0, local_port)
	if err != OK:
		return err
	p.host.compress(ENetConnection.COMPRESS_NONE)
	_use(p)
	role = Role.GUEST
	_connect_t = -1.0 if keep_match else 0.0
	_set_quit_guard(true)
	return OK


## Подключаемся (ещё не впустили)
func connecting() -> bool:
	return role == Role.GUEST and _connect_t >= 0.0


# ================================================================= уход

## Уйти самому: BYE, отключиться, когда оно ушло (не дольше BYE_WAIT); партия кончена (её запись — в
## user://net/last_match.ordorep; друг вышел раньше — она уже записана)
func leave() -> void:
	if role == Role.NONE:
		return
	if net_match and net_match.bound() and not net_match.over and net_match.link != &"left":
		net_match.save_last()
	var had := connected()
	_say_bye()
	net_match = null
	match_taken = false
	_reconnecting = false
	_connect_t = -1.0
	if had:
		_leaving = 0.0
	else:
		close_now()


## Закрыть сразу (без BYE). Хозяин закрыл игру — порт на роутере закрыть (и бросить поиск адреса, если он идёт)
func close_now() -> void:
	_release()
	if role == Role.HOST and upnp != null:
		upnp.cancel()
	role = Role.NONE
	net_match = null
	match_taken = false
	token = 0
	_reconnecting = false
	friend_info = {}
	_set_quit_guard(false)


## Отпустить ENet (партия и метка остаются — для переподключения)
func _release() -> void:
	_quiet = true
	if peer != null:
		peer.close()
		_old.append(peer)
	if api != null:
		api.multiplayer_peer = null
		_old.append(api)
	_quiet = false
	peer = null
	api = null
	friend_id = 0
	_accepted = 0
	_refused.clear()
	_bye_from.clear()
	_replaced.clear()
	_connect_t = -1.0
	_leaving = -1.0
	rtt_ms = -1.0
	slow = false


func _say_bye() -> void:
	if not connected():
		return
	send(NetProto.msg(NetProto.Msg.BYE))
	peer.host.flush()
	var ep := peer.get_peer(friend_id)
	if ep:
		ep.peer_disconnect_later()


# ================================================================= партия

## Партия ждёт игру (сцена «Города» её заберёт: GameDriver)
func has_match_waiting() -> bool:
	return net_match != null and not match_taken


func take_match() -> NetMatch:
	match_taken = true
	return net_match


func _make_match(p_seed: int, side: int, local: int, delay: int) -> void:
	net_match = NetMatch.new(self, {"seed": p_seed, "host_side": &"kokand" if side == 0 else &"kipchak",
		"local": local, "delay": delay})
	match_taken = false


## Сообщение другу (надёжно, по порядку); нет связи — false (пакеты такта хранит NetMatch до подтверждения)
func send(bytes: PackedByteArray) -> bool:
	if not connected():
		return false
	return api.send_bytes(bytes, friend_id, MultiplayerPeer.TRANSFER_MODE_RELIABLE, 0) == OK


## Проверка: оборвать связь, как при сбое сети (без BYE); друг стучится снова сам
func simulate_drop() -> void:
	if role != Role.GUEST or peer == null:
		return
	_quiet = true
	peer.close()
	_quiet = false
	_on_server_gone()


# ================================================================= ENet и сверка

## Событие для лобби: изнутри poll — после него (лобби может сразу звать host / join / close_now)
func _emit(kind: StringName, info: Dictionary) -> void:
	if _in_poll:
		_later.append(event.emit.bind(kind, info))
	else:
		event.emit(kind, info)


## Изнутри poll — отложить c до его конца (true), иначе false: делать сразу
func _defer(c: Callable) -> bool:
	if _in_poll:
		_later.append(c)
		return true
	return false


func _poll() -> void:
	_in_poll = true
	api.poll()
	_in_poll = false
	while not _later.is_empty():
		var c: Callable = _later.pop_front()
		c.call()


func _use(p: ENetMultiplayerPeer) -> void:
	peer = p
	api = SceneMultiplayer.new()
	api.root_path = NodePath("/root/" + NODE_NAME)
	api.auth_callback = _on_auth
	api.auth_timeout = AUTH_TIMEOUT
	api.server_relay = false
	api.peer_authenticating.connect(_on_authenticating)
	api.peer_authentication_failed.connect(_on_auth_failed)
	api.peer_connected.connect(_on_peer_connected)
	api.peer_disconnected.connect(_on_peer_disconnected)
	api.connection_failed.connect(_on_connection_failed)
	api.server_disconnected.connect(_on_server_gone)
	api.peer_packet.connect(_on_packet)
	api.multiplayer_peer = p
	_heard_t = 0.0
	_ping_t = 0.0


## Номер ENet жив (впущен или ещё сверяется)
func _alive(id: int) -> bool:
	return api != null and (api.get_peers().has(id) or api.get_authenticating_peers().has(id))


## ENet соединился: друг шлёт первый пакет (хозяин ждёт его)
func _on_authenticating(id: int) -> void:
	if _quiet:
		return
	_tune_peer(id)
	if role == Role.GUEST:
		var fields := PackedInt64Array([token])
		fields.append_array(_defs_fields())
		api.send_auth(1, NetProto.auth_packet(mine(), NetProto.Auth.HELLO, fields))
		if net_match == null:
			_emit(&"reached", {})


func _on_auth(id: int, data: PackedByteArray) -> void:
	if _quiet or api == null:
		return
	if role == Role.HOST:
		_host_auth(id, data)
	else:
		_guest_auth(data)


func _host_auth(id: int, data: PackedByteArray) -> void:
	var their := NetProto.read_auth(data)
	var me := mine()
	var fields: PackedInt64Array = their.get("fields", PackedInt64Array())
	var ok_version := not their.is_empty() and int(their["kind"]) == NetProto.Auth.HELLO and NetVersion.same(me, their) \
		and _defs_of(their) == int(me["defs_hash"])
	if not ok_version:
		_refuse(id, NetProto.Why.VERSION)
		var verdict := NetVersion.verdict(me, their)
		if verdict == "same":
			verdict = "odd"         # тот же код, а данные другие — тоже «собраны по-разному»
		_emit(&"friend_refused", {"why": "version", "their": their, "verdict": verdict})
		return
	var their_token := int(fields[0]) if fields.size() > 0 else 0
	if net_match != null:
		# партия идёт (или вот-вот начнётся): впустить только своего друга (та же метка), чужого — «место занято»
		if their_token == 0 or their_token != token:
			_refuse(id, NetProto.Why.BUSY if their_token == 0 else NetProto.Why.NO_MATCH)
			return
		if friend_id != 0 and friend_id != id:
			# прежний номер друга ENet ещё помнит — отключить его (после poll), его уход — не «связь пропала»
			_replaced[friend_id] = true
			var old_id := friend_id
			_later.append(func() -> void:
				var old := peer.get_peer(old_id) if _alive(old_id) else null
				if old:
					old.peer_disconnect_now())
			friend_id = 0
		_accepted = id
		api.send_auth(id, NetProto.auth_packet(me, NetProto.Auth.WELCOME, PackedInt64Array([token, 1])))
		api.complete_auth(id)
		return
	if their_token != 0:
		_refuse(id, NetProto.Why.NO_MATCH)         # стук в старую партию, а её уже нет
		return
	if _accepted != 0 and _accepted != id and _alive(_accepted):
		_refuse(id, NetProto.Why.BUSY)
		return
	_accepted = id
	friend_info = their
	token = (randi() & 0x3FFFFFFF) | 1
	api.send_auth(id, NetProto.auth_packet(me, NetProto.Auth.WELCOME, PackedInt64Array([token, 0])))
	api.complete_auth(id)


## Отказ с причиной: отключаем не в том же кадре — сперва причина уходит (друг отключится сам)
func _refuse(id: int, why: int) -> void:
	api.send_auth(id, NetProto.auth_packet(mine(), NetProto.Auth.REFUSE, PackedInt64Array([why])))
	peer.host.flush()
	_refused[id] = 0.0


func _guest_auth(data: PackedByteArray) -> void:
	var their := NetProto.read_auth(data)
	var me := mine()
	var kind := int(their.get("kind", NetProto.Auth.NONE))
	var fields: PackedInt64Array = their.get("fields", PackedInt64Array())
	if their.is_empty() or kind == NetProto.Auth.NONE or (kind == NetProto.Auth.REFUSE and fields.size() > 0
			and int(fields[0]) == NetProto.Why.VERSION) or (kind == NetProto.Auth.WELCOME and not NetVersion.same(me, their)):
		_refused_by_host("version", their)
		return
	if kind == NetProto.Auth.REFUSE:
		_refused_by_host("busy" if fields.is_empty() or int(fields[0]) == NetProto.Why.BUSY else "no_match", their)
		return
	if net_match != null and (fields.size() < 2 or int(fields[1]) != 1):
		# стучались в свою партию, а у хозяина её больше нет
		_refused_by_host("no_match", their)
		return
	friend_info = their
	if fields.size() > 0:
		token = int(fields[0])
	api.complete_auth(1)


func _refused_by_host(why: String, their: Dictionary) -> void:
	if _defer(_refused_by_host.bind(why, their)):
		return
	var verdict := NetVersion.verdict(mine(), their) if why == "version" else ""
	if verdict == "same":
		verdict = "odd"
	var m := net_match
	# прочитали причину — отключаемся сами
	close_now()
	if m != null:
		m.on_link(&"left")          # переподключение не впустили: партии у хозяина больше нет
	_emit(&"refused", {"why": why, "their": their, "verdict": verdict})


func _on_auth_failed(id: int) -> void:
	if _quiet:
		return
	_refused.erase(id)
	if id == _accepted:
		_accepted = 0


func _on_peer_connected(id: int) -> void:
	if _quiet:
		return
	if role == Role.HOST:
		if id != _accepted:
			return
		friend_id = id
		_heard_t = 0.0
		if net_match != null:
			net_match.on_reconnected()
		else:
			_emit(&"friend_joined", {"their": friend_info})
			if lobby_seed != 0:
				send(NetProto.msg(NetProto.Msg.LOBBY, PackedInt32Array([lobby_side, lobby_seed])))
	elif id == 1:
		friend_id = 1
		_connect_t = -1.0
		_heard_t = 0.0
		if _reconnecting:
			_reconnecting = false
			if net_match:
				net_match.on_reconnected()
		else:
			_remember_addr(addr)
			_emit(&"joined", {"their": friend_info})


func _on_peer_disconnected(id: int) -> void:
	if _quiet:
		return
	_refused.erase(id)
	if role != Role.HOST:
		return
	if _replaced.has(id):
		_replaced.erase(id)
		return
	if _leaving >= 0.0:
		friend_id = 0
		return
	if id == _accepted and id != friend_id:
		_accepted = 0
		return
	if id != friend_id:
		return
	_friend_gone(_bye_from.has(id))


## Хозяин: друга больше нет — ушёл сам (left: пришло «пока») или пропала связь. В лобби — событие; в партии —
## связь пропала: ждём, пока он подключится снова; вышел сам — партия кончена: игру закрыть, чужой в неё не войдёт
func _friend_gone(left: bool) -> void:
	friend_id = 0
	_accepted = 0
	rtt_ms = -1.0
	slow = false
	if net_match != null:
		net_match.on_link(&"left" if left else &"lost")
		if left:
			net_match = null
			match_taken = false
			if not _defer(close_now):
				close_now()
		return
	_emit(&"friend_left" if left else &"friend_lost", {})


## Пришло «пока»: друг ушёл сам — сразу, не дожидаясь, пока ENet заметит отключение (у друга, закрывшего окно,
## оно может и не успеть уйти: ENet хозяина узнал бы об этом только через 8–20 с молчания)
func _on_bye(id: int) -> void:
	_bye_from[id] = true
	if _leaving >= 0.0:
		return                    # уходим и сами
	if role == Role.GUEST:
		_on_server_gone()         # хозяин ушёл (внутри poll — после него)
	elif not _defer(_host_bye.bind(id)):
		_host_bye(id)


func _host_bye(id: int) -> void:
	if role != Role.HOST or id != friend_id or _leaving >= 0.0:
		return
	# ENet: отпустить уходящего сразу — его игра (окно закрывают) выходит, как только узнает, что отключена; его
	# отключение потом — уже не событие (друга нет)
	var ep := peer.get_peer(id) if _alive(id) else null
	if ep:
		ep.peer_disconnect_now()
	_friend_gone(true)


func _on_connection_failed() -> void:
	if _quiet or role != Role.GUEST or _defer(_on_connection_failed):
		return
	if _reconnecting:
		_release()
		_reconnect_t = 0.0
		return
	close_now()
	_emit(&"connect_failed", {"why": "failed"})


func _on_server_gone() -> void:
	if _quiet or role != Role.GUEST or _defer(_on_server_gone):
		return
	if _leaving >= 0.0:
		close_now()
		return
	var left := _bye_from.has(1)
	if net_match != null and not left and net_match.link != &"desync":
		# посреди партии: стучимся снова сами
		net_match.on_link(&"lost")
		_release()
		_reconnecting = true
		_reconnect_t = 0.0
		return
	var m := net_match
	close_now()
	if m != null:
		m.on_link(&"left")
	_emit(&"host_left" if left else &"host_lost", {})


func _on_packet(id: int, bytes: PackedByteArray) -> void:
	if _quiet or id != friend_id:
		return
	_heard_t = 0.0
	var m := NetProto.read_msg(bytes)
	if m.is_empty():
		return
	match m[0]:
		NetProto.Msg.PING:
			if m.size() >= 2:
				send(NetProto.msg(NetProto.Msg.PONG, PackedInt32Array([m[1]])))
		NetProto.Msg.PONG:
			if m.size() >= 2:
				_on_pong(m[1])
		NetProto.Msg.BYE:
			_on_bye(id)
		NetProto.Msg.LOBBY:
			if role == Role.GUEST and m.size() >= 3:
				lobby_side = m[1]
				lobby_seed = m[2]
				_emit(&"lobby", {"side": m[1], "seed": m[2]})
		NetProto.Msg.START:
			if role == Role.GUEST and m.size() >= 6 and net_match == null:
				lobby_side = m[2]
				lobby_seed = m[1]
				_make_match(m[1], m[2], 1, m[5])
				_emit(&"start", {"seed": m[1], "side": m[2]})
		_:
			if net_match != null:
				net_match.on_bytes(bytes)


func _on_pong(t: int) -> void:
	var sample := float((Time.get_ticks_msec() & 0x3FFFFFFF) - t)
	if sample < 0.0 or sample > 60000.0:
		return
	rtt_ms = sample if rtt_ms < 0.0 else lerpf(rtt_ms, sample, 0.3)
	var was := slow
	if rtt_ms > SLOW_MS:
		slow = true
	elif rtt_ms < GOOD_MS:
		slow = false
	if slow != was:
		_emit(&"ping", {"rtt": rtt_ms, "slow": slow})


func _process(delta: float) -> void:
	_old.clear()
	if upnp != null:
		upnp.poll()
		if upnp.mapped and role == Role.HOST:
			_upnp_t += delta
			if _upnp_t >= NetUpnp.RENEW:
				_upnp_t = 0.0
				upnp.renew()
	if api != null:
		_poll()
	if _quit_pending:
		_try_quit()
	if role == Role.NONE:
		return
	# отказанные — отключить, когда причина дошла (друг обычно отключается сам раньше)
	for id: int in _refused.keys():
		_refused[id] = float(_refused[id]) + delta
		if float(_refused[id]) >= REFUSE_HOLD:
			_refused.erase(id)
			var ep := peer.get_peer(id) if _alive(id) else null
			if ep:
				ep.peer_disconnect_later()
	if _leaving >= 0.0:
		_leaving += delta
		if _leaving >= BYE_WAIT or not connected():
			close_now()
		return
	if role == Role.GUEST and _connect_t >= 0.0:
		_connect_t += delta
		if _connect_t >= CONNECT_LIMIT:
			close_now()
			_emit(&"connect_failed", {"why": "timeout"})
			return
	if _reconnecting:
		_reconnect_t += delta
		if peer == null and _reconnect_t >= RECONNECT_EVERY:
			_reconnect_t = 0.0
			if join(addr, port, true) != OK:
				_release()
			_reconnecting = true
		elif peer != null and _reconnect_t >= CONNECT_LIMIT:
			_release()
			_reconnect_t = RECONNECT_EVERY
		return
	if connected():
		_heard_t += delta
		_ping_t += delta
		if _ping_t >= PING_EVERY:
			_ping_t = 0.0
			send(NetProto.msg(NetProto.Msg.PING, PackedInt32Array([Time.get_ticks_msec() & 0x3FFFFFFF])))
		# посреди партии хозяин молчит — подключившийся стучится заново сам, не дожидаясь ENet
		if role == Role.GUEST and net_match != null and _heard_t >= SILENCE_LOST and net_match.link == &"ok":
			_on_server_gone()


func _tune_peer(id: int) -> void:
	var ep := peer.get_peer(id) if peer and _alive(id) else null
	if ep:
		ep.set_timeout(ENET_TIMEOUT.x, ENET_TIMEOUT.y, ENET_TIMEOUT.z)


func _defs_fields() -> PackedInt64Array:
	var h := int(mine()["defs_hash"])
	return PackedInt64Array([h & 0xFFFFFFFF, (h >> 32) & 0xFFFFFFFF])


## Defs.hash из HELLO: поля [метка, младшие 32, старшие 32]
func _defs_of(their: Dictionary) -> int:
	var f: PackedInt64Array = their.get("fields", PackedInt64Array())
	if f.size() < 3:
		return -1
	return (int(f[1]) & 0xFFFFFFFF) | ((int(f[2]) & 0xFFFFFFFF) << 32)


# ================================================================= адрес в интернете (справка)

## «Узнать мой адрес в интернете»: UPnP роутера (и порт на нём), запасной путь — ipify. Итог — upnp.result, когда
## upnp.busy снова false (сигнал upnp.finished)
func find_external() -> NetUpnp:
	if upnp == null:
		upnp = NetUpnp.new()
	if not upnp.busy:
		upnp.find(port if role == Role.HOST else _arg_port())
	return upnp


## Лист «Игра с другом» закрыт: порт, открытый из справки без «Создать игру», — закрыть, поиск адреса — бросить
## (аренда и так кончилась бы сама через 2 ч)
func forget_external() -> void:
	if upnp != null:
		upnp.cancel()


# ================================================================= окно и настройки

## Пока идёт сессия, закрытие окна сперва шлёт другу BYE (иначе у него «Связь пропала»)
func _set_quit_guard(on: bool) -> void:
	if is_inside_tree():
		get_tree().auto_accept_quit = not on


## Окно закрыли посреди сессии — уйти, как «Выйти» (запись партии, BYE), и закрыть игру, когда «пока» ушло:
## выйти в том же кадре нельзя — ENet не успел бы отправить ни BYE, ни отключение (у друга до 20 с «Ждём друга…»)
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and role != Role.NONE:
		if _quit_pending:
			return
		_quit_pending = true
		leave()
		if upnp != null:
			upnp.cancel()
		_try_quit()
	elif what == NOTIFICATION_PREDELETE:
		if upnp != null:
			upnp.shutdown()


## Закрыть игру, если ушли (сессии нет) и поиск адреса в интернете (поток) кончился; иначе — в следующем кадре
func _try_quit() -> void:
	if role != Role.NONE or (upnp != null and upnp.busy):
		return
	_quit_pending = false
	if upnp != null:
		upnp.remove()
	get_tree().quit()


## Адрес, к которому подключались в прошлый раз (лобби: «В прошлый раз»)
static func last_addr() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(_settings_path()) != OK:
		return ""
	return String(cfg.get_value("net", "last_addr", ""))


func _remember_addr(a: String) -> void:
	var o := get_node_or_null("/root/Ordo")
	if o and (o.call("has_arg", "shot") or o.call("has_arg", "net_no_save")):
		return
	var cfg := ConfigFile.new()
	cfg.load(_settings_path())
	cfg.set_value("net", "last_addr", a)
	cfg.save(_settings_path())


static func _settings_path() -> String:
	var tree := Engine.get_main_loop() as SceneTree
	var o: Node = tree.root.get_node_or_null("Ordo") if tree else null
	return String(o.get("settings_path")) if o else "user://settings.cfg"


func _bind_ip() -> String:
	var o := get_node_or_null("/root/Ordo")
	return String(o.call("arg", "net_bind", "*")) if o else "*"


func _arg_port() -> int:
	var o := get_node_or_null("/root/Ordo")
	if o and o.call("has_arg", "net_port"):
		return clampi(int(o.call("arg", "net_port")), 1, 65535)
	return NetProto.PORT
