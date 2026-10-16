class_name NetMatch
extends RefCounted
## Партия «Города» по сети: шаг в ногу (lockstep) двух одинаковых GameSim (ТЗ §16; ARCHITECTURE §5.2 п. 6;
## владелец — NET). По сети идут только приказы; каждая игра считает всё сама.
##
## Игроки: 0 — хозяин (сторона из лобби), 1 — подключившийся (другая сторона); оба — люди, ИИ и набегов нет.
## Приказ, отданный на такте t, исполняется у обоих на такте t + delay (delay — задержка приказов, delay_for: 4–6
## тактов, 133–200 мс; решает хозяин по связи в лобби; на большой скорости — больше, lead). Приказы своего игрока
## за такт — один «пакет такта» (BATCH), он уходит другу и тогда, когда пуст: так друг знает, что приказов на этот
## такт больше не будет.
##
## Барьер такта: игра делает такт T, только когда у неё есть пакеты обоих игроков на T (свой — давно, чужой —
## пришёл по сети); нет — стоит (GameDriver.can_step → prepare). Порядок приказов внутри такта — (игрок, номер),
## как у CommandQueue.take: у обеих игр одинаковый.
##
## Задержка растёт со скоростью (lead): на ×2 свой пакет такта уходит на 2·delay тактов вперёд — по часам приказ
## исполняется так же скоро (133–200 мс), и запас на ответ друга тот же, что на ×1 (иначе на ×3–×4 игра шла бы
## рывками уже при ответе друга 70–90 мс). Барьеру это всё равно: у каждого пакета свой такт.
##
## Пауза и скорость — общие, флагами в пакете такта: «пауза после такта X» и «скорость с такта X» — обе игры
## встают на одном и том же такте. Флаги хранятся по игрокам: обе игры знают оба пакета такта X, прежде чем его
## сделать, и решают одинаково — пауза, если её просил хоть один (и не отменил), скорость — игрока 1, если на
## одном такте просили оба. Снять стоящую паузу (RESUME, вид NOW) можно сразу: обе стоят на X; отменить свою
## ещё не наступившую (вид CANCEL) — снимает только свою, пауза друга на том же такте встанет у обоих.
## Сверка: раз в 30 тактов обе игры шлют свою сумму (GameSim.checksums — отпечатки повтора); разошлись — партия
## останавливается, обе игры сохраняют свой повтор в user://net/ и шлют его другу (для разбора).
## Связь пропала — игра стоит (барьер) и ждёт друга; переподключился (NetSession, метка партии) — обе игры
## обмениваются SYNC и досылают пакеты, которых друг не получил (они хранятся до подтверждения).
##
## Транспорт — session: send(bytes) -> bool, rtt_ms (NetSession; в тестах — труба в памяти).

signal changed

const Msg := NetProto.Msg
const CHECK_EVERY := GameSim.CHECK_EVERY
## Задержка приказов, тактов: 4 (133 мс) — ровно до ответа ~150 мс; 5 — до ~220 мс; 6 (200 мс) — медленнее
const DELAY_MIN := 4
const DELAY_MAX := 6
## Задержка на большой скорости (lead) — не больше, тактов
const LEAD_MAX := 24
## RESUME: снять стоящую паузу у обоих / отменить свою, ещё не наступившую
const RESUME_NOW := 1
const RESUME_CANCEL := 0
const BOTH := 3
## Папка повторов партий по сети
const DIR := "user://net"
const LAST := "user://net/last_match.ordorep"
## Куда писать повтор партии (проверки — свой файл, не повтор игрока)
static var last_path := LAST

## Связь: ok; lost — пропала (ждём друга); left — друг вышел сам; desync — игры разошлись (стоп)
var link := &"ok"
var seed := 1
var host_side := &"kokand"
var local := 0
var remote := 1
var delay := DELAY_MIN
var session: Object
var driver: GameDriver
var game: GameSim
## Обе игры загружены и на такте 0
var me_ready := false
var peer_ready := false
## Общая пауза: стоит ли, на каком такте, кто просил (маска игроков 1 << p) и кто поставил для записки: местный,
## если просил и он, иначе друг
var paused := false
var paused_tick := -1
var pause_mask := 0
var pause_by := -1
## Последний закрытый свой пакет и последний полученный подряд пакет друга
var sent_upto := 0
var recv_upto := 0
## Разошлись: на каком такте; сохранённые повторы (свой и друга)
var desync_tick := -1
var saved := PackedStringArray()
## Друг снял паузу (для записки), друг вернулся после обрыва; связь пропала тогда-то (мс, «ждём уже 0:42»)
var resumed_by_friend := false
var back_at_ms := 0
var lost_at_ms := 0
## Друг сменил общую скорость (для записки «Друг сменил скорость: ×2»; 0 — нет); у друга открыто меню
var speed_by_friend := 0.0
var friend_menu := false
## Партия кончилась (победа) — дальше связь не важна
var over := false
## Сверка: последний такт, где суммы обеих игр совпали, и сколько сверок совпало
var checked_upto := 0
var checks_ok := 0
## Печатать сверки в журнал (ключ --net_log)
var log_checks := false

var _seq := 0
var _out := {}
var _future := {}
## Такт → маска игроков, просивших паузу после него; такт → маска отменивших (BOTH — паузу сняли раньше такта)
var _pause_at := {}
var _cancel_at := {}
## Такт → [скорость игрока 0, игрока 1] × 100 (0 — не просил)
var _speed_at := {}
## Посланные RESUME [такт, игрок, вид] — дослать после переподключения (последние RECENT)
var _resume_sent: Array[PackedInt32Array] = []
var _want_pause := false
var _want_speed := 0
var _menu_open := false
var _my_checks := {}
var _their_checks := {}
## Последние свои суммы [такт, сумма] — дослать после переподключения
var _recent: Array[PackedInt64Array] = []
const RECENT := 8
var _stall_since := -1


## cfg: {seed, host_side, local (0 — хозяин, 1 — друг), delay}
func _init(p_session: Object, cfg: Dictionary) -> void:
	session = p_session
	seed = int(cfg.get("seed", 1))
	host_side = StringName(str(cfg.get("host_side", "kokand")))
	local = int(cfg.get("local", 0))
	remote = 1 - local
	delay = clampi(int(cfg.get("delay", DELAY_MIN)), 1, 30)


## Задержка приказов по ответу друга (мс) — решает хозяин при «Начать игру»
static func delay_for(rtt_ms: float) -> int:
	if rtt_ms < 150.0:
		return DELAY_MIN
	if rtt_ms < 220.0:
		return DELAY_MIN + 1
	return DELAY_MAX


## Игроки партии: 0 — хозяин, 1 — друг; оба люди (без ИИ и набегов)
func players() -> Array[Dictionary]:
	var other := &"kipchak" if host_side == &"kokand" else &"kokand"
	return [{"faction": host_side, "team": 0, "ctrl": PlayerTable.Ctrl.HUMAN, "difficulty": 0},
		{"faction": other, "team": 1, "ctrl": PlayerTable.Ctrl.HUMAN, "difficulty": 0}]


func faction_of(p: int) -> StringName:
	return StringName(players()[p]["faction"])


## Игра готова (GameDriver.start_net_game): такты 1…delay−1 пусты у обоих; друг узнаёт, что мы загрузились
func bind(d: GameDriver) -> void:
	driver = d
	game = d.game
	sent_upto = delay - 1
	recv_upto = delay - 1
	me_ready = true
	_send(NetProto.msg(Msg.READY))
	if demo_state != "":
		_apply_demo()
	changed.emit()


func bound() -> bool:
	return game != null


# ================================================================= такт

## Перед тактом t → t+1: закрыть свои пакеты до t + lead() (входящие приказы игрока, пауза, скорость — в последний)
## — один раз на такт; вернуть, можно ли шагать (есть пакет друга на t + 1, связь есть, паузы нет). Скорость
## упала — пакеты уже закрыты дальше t + lead(): новых не закрываем, пока такт их не догонит (приказы ждут)
func prepare(t: int) -> bool:
	if game == null or link != &"ok" or paused or not (me_ready and peer_ready):
		_stall(false)
		return false
	var top := t + lead()
	while sent_upto < top:
		sent_upto += 1
		var cmds: Array[PackedInt32Array] = []
		var flags := 0
		var value := 0
		if sent_upto == top:
			cmds = driver.take_inbox()
			if _want_pause:
				_want_pause = false
				flags |= NetProto.F_PAUSE
				_pause_at[sent_upto] = int(_pause_at.get(sent_upto, 0)) | (1 << local)
			if _want_speed > 0:
				flags |= NetProto.F_SPEED
				value = _want_speed
				_set_speed(sent_upto, local, value)
				_want_speed = 0
		for i in cmds.size():
			var c := cmds[i].duplicate()
			if c.size() < SimCmd.H_IDS:
				c.resize(SimCmd.H_IDS)        # испорченный приказ: Orders отклонит по форме у обоих
			c[SimCmd.H_PLAYER] = local
			c[SimCmd.H_TICK] = sent_upto
			c[SimCmd.H_SEQ] = _seq
			_seq += 1
			cmds[i] = c
		game.queue.preload_cmds(cmds)
		var bytes := NetProto.batch(sent_upto, recv_upto, flags, value, cmds)
		_out[sent_upto] = bytes
		_send(bytes)
	var ok := recv_upto >= t + 1
	_stall(not ok)
	return ok


## Можно ли сделать такт t1 (без побочных действий)
func ready_for(t1: int) -> bool:
	return game != null and link == &"ok" and not paused and me_ready and peer_ready and recv_upto >= t1


## Задержка своих приказов сейчас, тактов: delay, на скорости выше ×1 — больше во столько же раз (по часам те же
## 133–200 мс и тот же запас на ответ друга), не больше LEAD_MAX
func lead() -> int:
	var s := driver.time_scale if driver != null else 1.0
	return clampi(ceili(delay * s - 0.001), delay, LEAD_MAX)


## После такта (GameDriver.step): сумма раз в 30 тактов — другу и сверка; скорость и пауза этого такта
func after_step() -> void:
	var t := game.tick
	if t % CHECK_EVERY == 0 and not game.checksums.is_empty():
		var v := game.checksums[game.checksums.size() - 1]
		_my_checks[t] = v
		_recent.append(PackedInt64Array([t, v]))
		if _recent.size() > RECENT:
			_recent.pop_front()
		var m := PackedInt32Array([t])
		m.append_array(NetProto.split64(v))
		_send(NetProto.msg(Msg.CHECK, m))
		_compare(t)
	# пакеты обоих игроков на этот такт известны обеим играм — решают одинаково
	if _speed_at.has(t):
		var v: PackedInt32Array = _speed_at[t]
		_speed_at.erase(t)
		var p := 1 if v[1] > 0 else 0         # просили оба — скорость игрока 1 (у обеих игр одна)
		var s := v[p] / 100.0
		if not is_equal_approx(driver.time_scale, s):
			driver.time_scale = s
			if p == remote:
				speed_by_friend = s
			changed.emit()
	if _pause_at.has(t):
		var mask := int(_pause_at[t]) & ~int(_cancel_at.get(t, 0))
		_pause_at.erase(t)
		if mask != 0:
			paused = true
			paused_tick = t
			pause_mask = mask
			pause_by = _pauser(mask)
			resumed_by_friend = false
			driver.paused = true
			changed.emit()
	# отмены прошлых тактов больше не нужны
	for k: int in _cancel_at.keys():
		if k <= t:
			_cancel_at.erase(k)


## Кто поставил паузу — для записки: местный, если просил и он (тогда «Пауза у обоих»), иначе друг
func _pauser(mask: int) -> int:
	return local if mask & (1 << local) else remote


func _set_speed(t: int, p: int, v: int) -> void:
	var s: PackedInt32Array = _speed_at.get(t, PackedInt32Array([0, 0]))
	s[p] = v
	_speed_at[t] = s


## Сколько миллисекунд игра стоит у барьера (ждёт пакет друга); 0 — не стоит
func stall_ms() -> int:
	return 0 if _stall_since < 0 else Time.get_ticks_msec() - _stall_since


func _stall(on: bool) -> void:
	if not on:
		_stall_since = -1
	elif _stall_since < 0:
		_stall_since = Time.get_ticks_msec()


# ================================================================= пауза и скорость (игрок)

## Пауза общая: on — в ближайший свой пакет (обе игры встанут после того же такта); снять — сразу (обе стоят)
func request_pause(on: bool) -> void:
	if link == &"desync" or game == null:
		return
	if on:
		if not paused:
			_want_pause = true
		return
	_want_pause = false
	# своя пауза уже ушла пакетом, но её такт ещё не пришёл — отменить у обоих только её (пауза друга на том же
	# такте встанет)
	var bit := 1 << local
	for t: int in _pause_at.keys():
		if t > game.tick and int(_pause_at[t]) & bit:
			_cancel_at[t] = int(_cancel_at.get(t, 0)) | bit
			_resume(t, RESUME_CANCEL)
	if paused:
		_resume(paused_tick, RESUME_NOW)
		_unpause()
		changed.emit()


func _unpause() -> void:
	paused = false
	pause_mask = 0
	driver.paused = false


## Скорость общая: с ближайшего своего пакета у обоих
func request_speed(s: float) -> void:
	if link == &"desync" or game == null:
		return
	_want_speed = clampi(roundi(s * 100.0), 25, 400)


## Пауза стоит или уже отдана — и пакетом, чей такт ещё не пришёл (для кнопки на балке, P и меню: P дважды подряд
## отменяет, меню после P паузу своей не считает)
func pause_wanted() -> bool:
	if paused or _want_pause:
		return true
	var bit := 1 << local
	for t: int in _pause_at.keys():
		if game != null and t > game.tick and int(_pause_at[t]) & bit and not (int(_cancel_at.get(t, 0)) & bit):
			return true
	return false


## Скорость, которая будет: отданная (ещё в своём пакете или пакет ушёл, а такт не пришёл) или нынешняя
func speed_wanted() -> float:
	if _want_speed > 0:
		return _want_speed / 100.0
	var last := -1
	for t: int in _speed_at.keys():
		var v: PackedInt32Array = _speed_at[t]
		if v[local] > 0 and t > last:
			last = t
	if last >= 0:
		return (_speed_at[last] as PackedInt32Array)[local] / 100.0
	return driver.time_scale if driver else 1.0


## Связь медленная (ответ друга дольше четверти секунды)
func slow() -> bool:
	if demo_state != "":
		return demo_state == "slow"
	return session != null and bool(session.get("slow"))


## Друг стучится снова сам (подключившийся после обрыва), иначе ждём, пока друг подключится
func reconnecting() -> bool:
	return local == 1


## Меню игры открыто / закрыто (CityMenu через GameDriver): друг видит «Друг открыл меню», а не просто паузу
func set_menu(open: bool) -> void:
	if _menu_open == open:
		return
	_menu_open = open
	_send(NetProto.msg(Msg.MENU, PackedInt32Array([1 if open else 0])))


## Сколько секунд связи нет («ждём уже 0:42»); 0 — связь есть
func lost_sec() -> int:
	if link != &"lost":
		return 0
	return maxi(0, Time.get_ticks_msec() - lost_at_ms) / 1000


# ================================================================= кадры записок без сети

## Состояние записки для кадров (--net_demo): paused (друг поставил паузу), my_pause, menu (у друга открыто меню),
## waiting (ждём приказы друга), loading (у друга грузится игра), lost (связь пропала, у хозяина), lost_guest (у
## подключившегося), slow (связь медленная), back (друг снова на связи), speed (друг сменил скорость), desync
## (разошлись), left (друг вышел)
var demo_state := ""


static func demo(state: String, p_seed: int, side: StringName) -> NetMatch:
	var m := NetMatch.new(null, {"seed": p_seed, "host_side": side, "local": 1 if state == "lost_guest" else 0,
		"delay": DELAY_MIN})
	m.demo_state = state
	return m


func _apply_demo() -> void:
	peer_ready = demo_state != "loading"
	match demo_state:
		"paused", "my_pause", "menu":
			paused = true
			paused_tick = 0
			pause_by = local if demo_state == "my_pause" else remote
			pause_mask = 1 << pause_by
			friend_menu = demo_state == "menu"
			driver.paused = true
		"waiting":
			# пакетов друга нет с самого начала, ждём уже 3 с (кадр снимается быстрее настоящего времени)
			recv_upto = 0
			_stall_since = Time.get_ticks_msec() - 3000
		"lost", "lost_guest":
			link = &"lost"
			lost_at_ms = Time.get_ticks_msec() - 42000
		"back":
			back_at_ms = Time.get_ticks_msec() + 60000
		"speed":
			speed_by_friend = 2.0
			driver.time_scale = 2.0
		"desync":
			link = &"desync"
			desync_tick = 2730
			saved = PackedStringArray(["%s/desync_%d_t2730_host.ordorep" % [DIR, seed],
				"%s/desync_%d_t2730_guest_friend.ordorep" % [DIR, seed]])
			driver.paused = true
		"left":
			link = &"left"


func _resume(t: int, kind: int) -> void:
	var r := PackedInt32Array([t, local, kind])
	_resume_sent.append(r)
	if _resume_sent.size() > RECENT:
		_resume_sent.pop_front()
	_send(NetProto.msg(Msg.RESUME, r))


# ================================================================= сообщения друга

## Сообщения партии от NetSession (и трубы тестов)
func on_bytes(bytes: PackedByteArray) -> void:
	var m := NetProto.read_msg(bytes)
	if m.is_empty():
		return
	match m[0]:
		Msg.READY:
			peer_ready = true
			changed.emit()
		Msg.BATCH:
			if m.size() >= 5:
				_on_batch(m)
		Msg.RESUME:
			if m.size() >= 4:
				_on_resume(m[1], clampi(m[2], 0, 1), m[3])
		Msg.MENU:
			if m.size() >= 2:
				friend_menu = m[1] != 0
				changed.emit()
		Msg.CHECK:
			# своя сумма этого такта уже сверена (досланная после обрыва) — не копить
			if m.size() >= 4 and not (game != null and m[1] <= game.tick and not _my_checks.has(m[1])):
				_their_checks[m[1]] = NetProto.join64(m[2], m[3])
				_compare(m[1])
		Msg.SYNC:
			if m.size() >= 3:
				_on_sync(m[1], m[2])
		Msg.REPLAY:
			_save_friend_replay(NetProto.read_blob(bytes))


func _on_batch(m: PackedInt32Array) -> void:
	_prune(m[2])
	var t := m[1]
	if t <= recv_upto or game == null:
		return
	_future[t] = m
	while _future.has(recv_upto + 1):
		var b: PackedInt32Array = _future[recv_upto + 1]
		_future.erase(recv_upto + 1)
		recv_upto += 1
		var cmds := NetProto.batch_cmds(b)
		for i in cmds.size():
			var c := cmds[i]
			if c.size() < SimCmd.H_IDS:
				c.resize(SimCmd.H_IDS)
			# игрок и такт — по пакету: чужой приказ не станет нашим и не опоздает
			c[SimCmd.H_PLAYER] = remote
			c[SimCmd.H_TICK] = recv_upto
			cmds[i] = c
		game.queue.preload_cmds(cmds)
		if b[3] & NetProto.F_PAUSE:
			_pause_at[recv_upto] = int(_pause_at.get(recv_upto, 0)) | (1 << remote)
		if b[3] & NetProto.F_SPEED:
			_set_speed(recv_upto, remote, clampi(b[4], 25, 400))


## Друг снял паузу (NOW: стоящую — у обоих) или отменил свою, такт которой ещё не наступил (CANCEL: только свою)
func _on_resume(t: int, p: int, kind: int) -> void:
	if kind == RESUME_NOW:
		if paused and paused_tick == t:
			_unpause()
			resumed_by_friend = true
			changed.emit()
		elif game == null or t > game.tick:
			_cancel_at[t] = BOTH          # сняли раньше, чем мы дошли до её такта
		return
	var bit := 1 << p
	if paused and paused_tick == t:
		# мы уже встали на этом такте (отмена пришла позже его пакета): стоим, только если просил ещё кто-то
		pause_mask &= ~bit
		if pause_mask == 0:
			_unpause()
		else:
			pause_by = _pauser(pause_mask)
		changed.emit()
	elif game == null or t > game.tick:
		_cancel_at[t] = int(_cancel_at.get(t, 0)) | bit


## Друг подтвердил пакеты до ack — их больше не досылать
func _prune(ack: int) -> void:
	for t: int in _out.keys():
		if t <= ack:
			_out.erase(t)


func _compare(t: int) -> void:
	if not (_my_checks.has(t) and _their_checks.has(t)):
		return
	if _my_checks[t] != _their_checks[t]:
		_desync(t)
		return
	_my_checks.erase(t)
	_their_checks.erase(t)
	checked_upto = maxi(checked_upto, t)
	checks_ok += 1
	if log_checks and checks_ok % 10 == 1:
		print("[сеть] такт %d: суммы совпали (%d сверок), задержка приказов %d, ответ друга %.0f мс" % [
			t, checks_ok, delay, float(session.get("rtt_ms")) if session != null else -1.0])


# ================================================================= связь

## NetSession: связь пропала (lost) или друг вышел сам (left)
func on_link(state: StringName) -> void:
	if link == &"desync" or link == state:
		return
	link = state
	if state == &"lost":
		lost_at_ms = Time.get_ticks_msec()
	if state == &"left":
		friend_menu = false
		save_last()
	changed.emit()


## NetSession: друг снова на связи (переподключился, метка партии та же): досылаем, чего он не получил
func on_reconnected() -> void:
	if link == &"desync" or link == &"left":
		return
	link = &"ok"
	lost_at_ms = 0
	back_at_ms = Time.get_ticks_msec()
	_send(NetProto.msg(Msg.SYNC, PackedInt32Array([game.tick if game else 0, recv_upto])))
	if me_ready:
		_send(NetProto.msg(Msg.READY))
	for r in _resume_sent:
		_send(NetProto.msg(Msg.RESUME, r))
	_send(NetProto.msg(Msg.MENU, PackedInt32Array([1 if _menu_open else 0])))
	changed.emit()


func _on_sync(_their_tick: int, their_recv: int) -> void:
	var ticks: Array = _out.keys()
	ticks.sort()
	for t: int in ticks:
		if t > their_recv:
			_send(_out[t])
	# последние свои суммы — друг мог их не получить (пропали в обрыве), лишние он отбросит
	for r: PackedInt64Array in _recent:
		var m := PackedInt32Array([r[0]])
		m.append_array(NetProto.split64(r[1]))
		_send(NetProto.msg(Msg.CHECK, m))


func _send(bytes: PackedByteArray) -> void:
	if session != null:
		session.call("send", bytes)
	elif demo_state in ["slow", "back"] and bytes.size() >= 8 and bytes.decode_s32(0) == Msg.BATCH:
		# кадры без сети: друг «играет» — его пакет такта пуст и приходит сразу
		var t := bytes.decode_s32(4)
		on_bytes(NetProto.batch(t, t, 0, 0, [] as Array[PackedInt32Array]))


# ================================================================= повторы

func role_name(p: int) -> String:
	return "host" if p == 0 else "guest"


## Партия разошлась на такте t: стоп, свой повтор — в user://net/, другу — тоже (для разбора)
func _desync(t: int) -> void:
	if link == &"desync":
		return
	link = &"desync"
	desync_tick = t
	if driver:
		driver.paused = true
	var rec := game.replay_record()
	var path := "%s/desync_%d_t%d_%s.ordorep" % [DIR, seed, t, role_name(local)]
	if _save(path, rec):
		saved.append(path)
	_send(NetProto.blob(Msg.REPLAY, var_to_bytes(rec)))
	push_warning("NetMatch: партия разошлась на такте %d (сумма %d, у друга %d)" % [t, int(_my_checks[t]), int(_their_checks[t])])
	changed.emit()


func _save_friend_replay(bytes: PackedByteArray) -> void:
	if bytes.is_empty():
		return
	var v: Variant = bytes_to_var(bytes)
	if not (v is Dictionary):
		return
	var t := desync_tick if desync_tick >= 0 else (game.tick if game else 0)
	var path := "%s/desync_%d_t%d_%s_friend.ordorep" % [DIR, seed, t, role_name(remote)]
	if _save(path, v as Dictionary):
		saved.append(path)
	changed.emit()


## Повтор партии — как у одиночной (Replay): user://net/last_match.ordorep (конец партии, выход, друг вышел)
func save_last() -> String:
	if game == null or demo_state != "":
		return ""
	return last_path if _save(last_path, game.replay_record()) else ""


func _save(path: String, rec: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	return Replay.save(path, rec)
