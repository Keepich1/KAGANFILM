extends SceneTree
## Игра по сети без сети (ТЗ §16; NET): всё, что можно проверить в одном процессе.
##   • первый пакет сверки: постоянная раскладка («ORDO», протокол, версия, дата, код — места и размеры полей),
##     туда и обратно; обрезанный и чужой — не разобрать; другой протокол — версия друга всё равно видна;
##   • кто обновляет игру: старая у меня / у друга (по дате, в один день — по номеру), номер тот же — «собраны
##     по-разному»; подписи версии («0.1.57 от 15 окт.», «рабочая сборка от …»);
##   • адреса хозяина: Radmin по имени адаптера и по 26.x, «Дома» без vEthernet / VirtualBox / Bluetooth, два
##     домашних — оба; адрес в интернете: частный и 100.64/10 — «у провайдера так не выйдет»;
##   • шаг в ногу двух GameDriver через трубу в памяти с задержкой: оба игрока — люди, сценарные приказы (найм,
##     стройка, добыча, ход) 900 тактов — суммы каждые 30 тактов и в конце совпадают; повтор партии по сети
##     совпадает с ней (Replay.verify); приказы обоих игроков — в журнале;
##   • барьер такта: без пакета друга такт не делается; задержка приказов — delay тактов;
##   • пауза общая: обе игры встают после одного такта, снять может друг; отменённая до своего такта пауза не
##     ставится ни у кого; скорость — у обоих с одного такта;
##   • оба на одном такте: скорость ×2 и ×0.5 — у обеих игр одна (игрока 1), записка «Друг сменил скорость» —
##     только у того, чью скорость перебили; паузу просили оба, один отменил свою — пауза друга встаёт у обоих;
##     отмена пришла, когда игра уже встала, — встала только по ней — снята; на ×2 свои приказы уходят на 2·delay
##     тактов вперёд (по часам — те же 133 мс), назад на ×1 — партия идёт, суммы совпадают; меню друга видно;
##   • обрыв: пакеты в пути пропали — после SYNC досланы, партия идёт дальше, суммы те же;
##   • расхождение: лишний приказ у одной игры — обе останавливаются на ближайшей сверке, повторы в user://net/;
##   • одиночная игра: can_step() всегда да, пауза и скорость — сразу (как было).
##   godot --headless --path ordo --script res://tests/test_net.gd

const TICKS := 900


class Pipe:
	## Труба между двумя NetMatch: сообщение приходит через latency кадров; cut — связи нет (теряются)
	var other: Pipe
	var net_match: NetMatch
	var slow := false
	var rtt_ms := 20.0
	var latency := 3
	var frame := 0
	var cut := false
	var q: Array = []
	var sent := 0

	func send(bytes: PackedByteArray) -> bool:
		if cut:
			return false
		other.q.append([other.frame + latency, bytes])
		sent += 1
		return true

	func pump() -> void:
		frame += 1
		while not q.is_empty() and int(q[0][0]) <= frame:
			var b: PackedByteArray = q.pop_front()[1]
			if not cut:
				net_match.on_bytes(b)

	func lose_all() -> void:
		q.clear()


## Разобрать пару: трубы и партии ссылаются друг на друга (RefCounted по кругу) — разорвать и освободить игры
static func _free_pair(pair: Array) -> void:
	for i in 2:
		var p: Pipe = pair[2 + i]
		p.other = null
		p.net_match = null
		var d: GameDriver = pair[i]
		if d.net:
			d.net.session = null
			d.net.driver = null
		d.free()
	pair.clear()


var _impl := {}


func _init() -> void:
	_impl = GameSim.impl_for(OS.get_cmdline_user_args(), OS.get_environment("ORDO_IMPL"))
	_test_auth_packet()
	_test_verdict()
	_test_addr()
	_test_lockstep()
	_test_pause_speed()
	_test_same_tick()
	_test_drop()
	_test_desync()
	_test_single()
	SimHarness.finish(self)


# ================================================================= первый пакет

func _test_auth_packet() -> void:
	print("[первый пакет сверки — постоянная раскладка]")
	var info := {"number": "0.1.57", "date": 20261015, "code": "7a3f00112233aabb".hex_decode()}
	var p := NetProto.auth_packet(info, NetProto.Auth.HELLO, PackedInt64Array([0, 0xDEADBEEF, 7]))
	SimHarness.check(p.slice(0, 4).get_string_from_ascii() == "ORDO" and p[4] == 0 and p[5] == NetProto.PROTOCOL,
		"0–3 «ORDO», 4–5 номер протокола %d (старший байт первым)" % NetProto.PROTOCOL)
	SimHarness.check(p.slice(6, 12).get_string_from_utf8() == "0.1.57" and p[12] == 0 and p[21] == 0,
		"6–21 версия, добита нулями до 16 байт")
	SimHarness.check(p[22] == 0x01 and p[23] == 0x35 and p[24] == 0x28 and p[25] == 0x97,
		"22–25 дата 20261015 (0x01352897, старший байт первым)")
	SimHarness.check(p.slice(26, 34).hex_encode() == "7a3f00112233aabb" and p[34] == NetProto.Auth.HELLO and p.size() == 34 + 1 + 12,
		"26–33 код 8 байт, 34 — вид пакета, дальше поля по 4 байта (%d байт)" % p.size())
	var back := NetProto.read_auth(p)
	SimHarness.check(back.get("number") == "0.1.57" and int(back.get("date")) == 20261015 and back.get("code") == info["code"]
		and int(back.get("kind")) == NetProto.Auth.HELLO and (back.get("fields") as PackedInt64Array) == PackedInt64Array([0, 0xDEADBEEF, 7]),
		"туда и обратно: версия, дата, код, вид, поля")
	SimHarness.check(NetProto.read_auth(p.slice(0, 20)).is_empty() and NetProto.read_auth("HELLO".to_ascii_buffer()).is_empty(),
		"обрезанный и чужой пакет — не разобрать (→ «Разные версии игры»)")
	var other := p.duplicate()
	other[5] = NetProto.PROTOCOL + 1
	var o := NetProto.read_auth(other)
	SimHarness.check(int(o.get("kind", -1)) == NetProto.Auth.NONE and o.get("number") == "0.1.57" and int(o.get("date")) == 20261015,
		"другой номер протокола: вид не читаем, а версию и дату друга видно")
	var long := NetProto.auth_packet({"number": "0.1.123456789012345678", "date": 1, "code": PackedByteArray()}, NetProto.Auth.WELCOME)
	SimHarness.check(long.size() == 35 and long[34] == NetProto.Auth.WELCOME, "длинная версия обрезана до 16 байт — поля не сдвигаются")
	var b := NetProto.batch(57, 50, NetProto.F_PAUSE, 0, [SimCmd.stop(PackedInt32Array([Ids.make(Ids.Kind.UNIT, 3, 1)]))] as Array[PackedInt32Array])
	var m := NetProto.read_msg(b)
	var cmds := NetProto.batch_cmds(m)
	SimHarness.check(m[0] == NetProto.Msg.BATCH and m[1] == 57 and m[2] == 50 and m[3] == NetProto.F_PAUSE and cmds.size() == 1
		and cmds[0][SimCmd.H_OP] == SimCmd.Op.STOP, "пакет такта: такт, подтверждение, флаги, приказы")
	var blob := NetProto.blob(NetProto.Msg.REPLAY, "abcde".to_ascii_buffer())
	SimHarness.check(NetProto.read_blob(blob).get_string_from_ascii() == "abcde" and blob.size() % 4 == 0, "байты в хвосте (повтор)")
	SimHarness.check(NetProto.join64(NetProto.split64(0xAB_CDEF_1234)[0], NetProto.split64(0xAB_CDEF_1234)[1]) == 0xAB_CDEF_1234,
		"сумма 40 бит — в два числа и обратно")


func _test_verdict() -> void:
	print("[кто обновляет игру]")
	var code_a := "7a3f000000000000".hex_decode()
	var code_b := "9b12000000000000".hex_decode()
	var new := {"number": "0.1.57", "date": 20261015, "code": code_a}
	var old := {"number": "0.1.52", "date": 20261002, "code": code_b}
	SimHarness.check(NetVersion.verdict(new, new) == "same", "та же игра — пускаем")
	SimHarness.check(NetVersion.verdict(old, new) == "mine_old" and NetVersion.verdict(new, old) == "theirs_old",
		"старая — у кого раньше дата")
	SimHarness.check(NetVersion.verdict(new, {"number": "0.1.57", "date": 20261015, "code": code_b}) == "odd",
		"номер тот же, код разный — «собраны по-разному»")
	SimHarness.check(NetVersion.verdict({"number": "0.1.9", "date": 20261015, "code": code_a},
		{"number": "0.1.10", "date": 20261015, "code": code_b}) == "mine_old", "в один день — по номеру (0.1.9 < 0.1.10)")
	SimHarness.check(NetVersion.verdict(new, {}) == "odd", "пакет друга не разобрать — «собраны по-разному»")
	SimHarness.check(NetVersion.label(new) == "0.1.57 от 15 окт." and NetVersion.label({"number": "", "date": 20260502}) == "рабочая сборка от 2 мая",
		"подписи: «0.1.57 от 15 окт.», «рабочая сборка от 2 мая»")
	SimHarness.check(NetVersion.code_text(code_a) == "7A3F", "код на экран — «7A3F»")
	NetVersion.wait()
	var me := NetVersion.info()
	SimHarness.check((me["code"] as PackedByteArray).size() == NetProto.CODE_BYTES and int(me["date"]) > 20200000
		and int(me["defs_hash"]) == Defs.shared().hash(), "своя версия посчитана: код %s, дата %d" % [NetVersion.code_text(me["code"]), me["date"]])


func _test_addr() -> void:
	print("[адреса хозяина]")
	var ifs := [
		{"name": "{A}", "friendly": "Loopback Pseudo-Interface 1", "addresses": ["127.0.0.1", "::1"]},
		{"name": "{B}", "friendly": "vEthernet (WSL)", "addresses": ["172.24.80.1"]},
		{"name": "{C}", "friendly": "Беспроводная сеть", "addresses": ["fe80::1", "192.168.1.34"]},
		{"name": "{D}", "friendly": "Radmin VPN", "addresses": ["26.115.40.12"]},
		{"name": "{E}", "friendly": "VirtualBox Host-Only Network", "addresses": ["192.168.56.1"]},
		{"name": "{F}", "friendly": "Сетевое подключение Bluetooth", "addresses": ["169.254.3.4"]},
		{"name": "{G}", "friendly": "Ethernet", "addresses": ["10.0.0.7"]},
	]
	var a := NetAddr.scan(ifs)
	SimHarness.check(a["radmin"] == "26.115.40.12", "Radmin VPN — по имени адаптера")
	SimHarness.check(a["home"] == PackedStringArray(["192.168.1.34", "10.0.0.7"]),
		"«Дома» — Wi-Fi и Ethernet, без vEthernet, VirtualBox, Bluetooth и петли (%s)" % ", ".join(a["home"]))
	var b := NetAddr.scan([{"name": "{X}", "friendly": "Сеть 3", "addresses": ["26.1.2.3"]}, {"name": "{Y}", "friendly": "Ethernet", "addresses": ["192.168.0.5"]}])
	SimHarness.check(b["radmin"] == "26.1.2.3" and b["home"] == PackedStringArray(["192.168.0.5"]),
		"Radmin VPN — и по сети 26.0.0.0/8 (адаптер переименован)")
	var c := NetAddr.scan([{"name": "{Y}", "friendly": "Ethernet", "addresses": ["192.168.0.5"]}])
	SimHarness.check(c["radmin"] == "", "нет Radmin VPN — «не найден»")
	SimHarness.check(NetAddr.is_not_public("100.72.1.1") and NetAddr.is_not_public("192.168.0.1") and NetAddr.is_not_public("10.1.1.1")
		and not NetAddr.is_not_public("203.0.113.57"), "адрес роутера 100.64/10 и частный — «у провайдера так не выйдет»")
	SimHarness.check(NetAddr.friend_ok("26.115.40.12") and not NetAddr.friend_ok("0.1.2.3") and not NetAddr.friend_ok("224.0.0.1")
		and not NetAddr.friend_ok("1.2.3"), "адрес друга: первое число 1–223, четыре числа")


# ================================================================= шаг в ногу

## Партия двух игр через трубы: host — игрок 0 (Коканд), guest — игрок 1 (кыпчаки)
func _pair(p_seed := 4242, delay := 4, latency := 3) -> Array:
	var ph := Pipe.new()
	var pg := Pipe.new()
	ph.other = pg
	pg.other = ph
	ph.latency = latency
	pg.latency = latency
	var mh := NetMatch.new(ph, {"seed": p_seed, "host_side": &"kokand", "local": 0, "delay": delay})
	var mg := NetMatch.new(pg, {"seed": p_seed, "host_side": &"kokand", "local": 1, "delay": delay})
	ph.net_match = mh
	pg.net_match = mg
	var dh := GameDriver.new()
	dh.autostart = false
	dh.game_impl = _impl.duplicate()
	var dg := GameDriver.new()
	dg.autostart = false
	dg.game_impl = _impl.duplicate()
	dh.start_net_game(mh)
	dg.start_net_game(mg)
	return [dh, dg, ph, pg]


## Кадр: трубы, потом каждая игра — не больше одного такта; после такта — сценарные приказы своего игрока
func _frame(pair: Array, bots: Array, limit: int) -> void:
	(pair[2] as Pipe).pump()
	(pair[3] as Pipe).pump()
	for i in 2:
		var d: GameDriver = pair[i]
		if d.game.tick >= limit:
			continue
		if d.can_step():
			d.step()
			if bots[i] != null:
				for c in (bots[i] as NetBot).commands(d.game.tick, d.query):
					d.issue(c)


func _run(pair: Array, bots: Array, limit: int, max_frames := 20000, hook := Callable()) -> int:
	var f := 0
	while f < max_frames and ((pair[0] as GameDriver).game.tick < limit or (pair[1] as GameDriver).game.tick < limit):
		_frame(pair, bots, limit)
		if hook.is_valid():
			hook.call(f)
		f += 1
	return f


func _test_lockstep() -> void:
	print("[шаг в ногу: два GameDriver, приказы обоих игроков, 900 тактов]")
	var pair := _pair()
	var dh: GameDriver = pair[0]
	var dg: GameDriver = pair[1]
	SimHarness.check(dh.local_player == 0 and dg.local_player == 1 and dh.game.players_cfg[1]["ctrl"] == PlayerTable.Ctrl.HUMAN
		and dh.game.ai.is_empty() and dg.game.ai.is_empty(), "оба игрока — люди, ИИ нет; местный у друга — 1")
	SimHarness.check(dh.game.checksum() == dg.game.checksum(), "начало партии одинаковое у обеих игр")
	# такт 1…delay−1 — без пакетов; дальше — только с пакетом друга
	var bots := [NetBot.new(0), NetBot.new(1)]
	var frames := _run(pair, bots, TICKS)
	var same := dh.game.checksums == dg.game.checksums and dh.game.checksums.size() == TICKS / 30
	SimHarness.check(dh.game.tick == TICKS and dg.game.tick == TICKS, "обе игры дошли до такта %d (%d кадров)" % [TICKS, frames])
	SimHarness.check(same, "суммы каждые 30 тактов совпадают (%d)" % dh.game.checksums.size())
	SimHarness.check(dh.game.checksum() == dg.game.checksum(), "сумма в конце совпадает")
	SimHarness.check(dh.net.link == &"ok" and dg.net.link == &"ok", "сверка не нашла расхождений")
	var log := dh.game.queue.external_log()
	var by := [0, 0]
	var ops := {}
	for c in log:
		by[c[SimCmd.H_PLAYER]] += 1
		ops[SimCmd.name_of(c[SimCmd.H_OP])] = true
	SimHarness.check(by[0] > 5 and by[1] > 5 and ops.has("TRAIN") and ops.has("BUILD") and ops.has("MOVE") and ops.has("GATHER"),
		"в журнале приказы обоих (%d и %d): %s" % [by[0], by[1], ", ".join(PackedStringArray(ops.keys()))])
	var a := dh.game.orders.applied
	SimHarness.check(a > 0 and a == dg.game.orders.applied and dh.game.orders.rejected == dg.game.orders.rejected,
		"исполнено %d, отклонено %d — одинаково" % [a, dh.game.orders.rejected])
	var late := 0
	for c in log:
		if c[SimCmd.H_TICK] < 4:
			late += 1
	SimHarness.check(late == 0, "задержка приказов: ни один не раньше такта delay")
	var rec := dh.game.replay_record()
	SimHarness.check(Replay.verify(rec, _impl), "повтор партии по сети совпадает с ней %s" % Replay.last_error)
	var rec2 := dg.game.replay_record()
	SimHarness.check(SimCmd.decode(rec["log"]) == SimCmd.decode(rec2["log"]), "журналы приказов у хозяина и друга одинаковые")
	_free_pair(pair)
	print("[барьер такта]")
	var p2 := _pair(7, 4, 1)
	var h2: GameDriver = p2[0]
	var g2: GameDriver = p2[1]
	SimHarness.check(h2.game.tick == 0 and not h2.can_step(), "пока друг не загрузился (READY) — ни одного такта")
	(p2[2] as Pipe).pump()
	(p2[3] as Pipe).pump()
	var steps := 0
	while h2.can_step() and steps < 50:
		h2.step()
		steps += 1
	SimHarness.check(h2.game.tick == 3, "без пакетов друга — только такты 1…delay−1 (такт %d)" % h2.game.tick)
	g2.step()
	(p2[3] as Pipe).pump()
	(p2[2] as Pipe).pump()
	(p2[2] as Pipe).pump()
	SimHarness.check(h2.can_step(), "пакет друга на такт 4 пришёл — шаг можно")
	_free_pair(p2)


func _test_pause_speed() -> void:
	print("[пауза и скорость — общие]")
	var pair := _pair(99)
	var dh: GameDriver = pair[0]
	var dg: GameDriver = pair[1]
	var bots := [NetBot.new(0), NetBot.new(1)]
	_run(pair, bots, 120)
	dh.request_pause(true)
	SimHarness.check(dh.pause_wanted() and not dh.paused, "пауза отдана — встанет через задержку приказов")
	_run(pair, bots, 400, 300)
	var th := dh.game.tick
	var tg := dg.game.tick
	SimHarness.check(dh.paused and dg.paused and th == tg and dh.net.pause_by == 0 and dg.net.pause_by == 0,
		"обе игры встали после одного такта (%d и %d), поставил хозяин" % [th, tg])
	dg.request_pause(false)
	SimHarness.check(not dg.paused, "друг снял паузу — у него сразу")
	_run(pair, bots, th + 60, 400)
	SimHarness.check(not dh.paused and dh.game.tick == th + 60 and dg.game.tick == th + 60 and dh.net.resumed_by_friend,
		"у хозяина пауза снята тоже, игра идёт (такт %d)" % dh.game.tick)
	# пауза отдана и отменена до своего такта — не ставится ни у кого
	dg.request_pause(true)
	_frame(pair, bots, th + 61)
	dg.request_pause(false)
	_run(pair, bots, th + 120, 400)
	SimHarness.check(not dh.paused and not dg.paused and dh.game.tick == th + 120, "отменённая пауза не встала ни у кого")
	dg.request_speed(2.0)
	_run(pair, bots, th + 150, 400)
	SimHarness.check(is_equal_approx(dh.time_scale, 2.0) and is_equal_approx(dg.time_scale, 2.0), "скорость ×2 — у обоих")
	_run(pair, bots, th + 180, 400)
	SimHarness.check(dh.game.checksums == dg.game.checksums, "суммы совпадают и после пауз")
	_free_pair(pair)


## Оба игрока просят паузу или скорость на одном и том же такте: флаги — по игрокам, обе игры решают одинаково
## (раньше побеждал тот, чей пакет пришёл последним, — у двух игр по-разному)
func _test_same_tick() -> void:
	print("[пауза и скорость от обоих на одном такте; задержка на большой скорости]")
	var pair := _pair(77)
	var dh: GameDriver = pair[0]
	var dg: GameDriver = pair[1]
	var bots := [NetBot.new(0), NetBot.new(1)]
	_run(pair, bots, 60)
	dh.request_speed(2.0)
	dg.request_speed(0.5)
	_run(pair, bots, 90, 400)
	SimHarness.check(dh.game.tick == 90 and is_equal_approx(dh.time_scale, 0.5) and is_equal_approx(dg.time_scale, 0.5),
		"на одном такте хозяин ×2, друг ×0.5 — у обеих игр одна скорость, игрока 1 (×%s и ×%s)" % [
		NetHud._speed_text(dh.time_scale), NetHud._speed_text(dg.time_scale)])
	SimHarness.check(is_equal_approx(dh.net.speed_by_friend, 0.5) and dg.net.speed_by_friend == 0.0,
		"«Друг сменил скорость: ×0.5» — у хозяина; у друга (его скорость) — нет")
	# паузу просят оба на одном такте, хозяин тут же отменяет свою — встаёт пауза друга, у обоих на одном такте
	dh.request_speed(1.0)
	_run(pair, bots, 120, 400)
	dh.request_pause(true)
	dg.request_pause(true)
	_frame(pair, bots, 1000)
	dh.request_pause(false)
	_run(pair, bots, 200, 60)
	SimHarness.check(dh.paused and dg.paused and dh.game.tick == dg.game.tick and dh.game.tick < 200,
		"паузу просили оба, хозяин отменил свою — встали оба на такте %d (и %d)" % [dh.game.tick, dg.game.tick])
	SimHarness.check(dh.net.pause_by == 1 and dg.net.pause_by == 1 and dh.net.pause_mask == 2 and dg.net.pause_mask == 2,
		"пауза — друга у обоих: у хозяина «Друг поставил паузу», у друга «Пауза у обоих»")
	dh.request_pause(false)
	_run(pair, bots, 240, 400)
	SimHarness.check(not dh.paused and not dg.paused and dh.game.tick == 240, "хозяин снял паузу друга — идут оба")
	# отмена пришла, когда игра уже встала только по ней (пакет такта пришёл раньше отмены) — снята
	dh.request_pause(true)
	_run(pair, bots, 300, 60)
	var t := dg.game.tick
	SimHarness.check(dg.paused and dg.net.pause_mask == 1, "друг встал по паузе хозяина (такт %d)" % t)
	dg.net.on_bytes(NetProto.msg(NetProto.Msg.RESUME, PackedInt32Array([t, 0, NetMatch.RESUME_CANCEL])))
	SimHarness.check(not dg.paused and not dg.net.resumed_by_friend, "отмена паузы пришла позже — пауза снята, записки «снял» нет")
	dh.request_pause(false)
	_run(pair, bots, 330, 400)
	# большая скорость: свои приказы — на 2·delay тактов вперёд; потом снова ×1
	dg.request_speed(2.0)
	_run(pair, bots, 360, 400)
	SimHarness.check(dh.net.lead() == 8 and dg.net.lead() == 8 and dh.net.sent_upto - dh.game.tick >= 7,
		"на ×2 свои приказы — на 8 тактов вперёд (у хозяина закрыто до %d на такте %d)" % [dh.net.sent_upto, dh.game.tick])
	dh.request_speed(1.0)
	_run(pair, bots, 480, 600)
	SimHarness.check(dh.net.lead() == 4 and dh.game.tick == 480 and dg.game.tick == 480 and dh.game.checksums == dg.game.checksums,
		"снова ×1 — задержка 4, партия идёт, суммы совпадают (%d)" % dh.game.checksums.size())
	# меню друга
	dg.set_menu_open(true)
	_run(pair, bots, 490, 100)
	var seen := dh.net.friend_menu
	dg.set_menu_open(false)
	_run(pair, bots, 500, 100)
	SimHarness.check(seen and not dh.net.friend_menu, "друг открыл меню — хозяин видит; закрыл — тоже")
	_free_pair(pair)


func _test_drop() -> void:
	print("[обрыв связи посреди партии]")
	var pair := _pair(31, 4, 4)
	var dh: GameDriver = pair[0]
	var dg: GameDriver = pair[1]
	var ph: Pipe = pair[2]
	var pg: Pipe = pair[3]
	var bots := [NetBot.new(0), NetBot.new(1)]
	var stalled := [false]
	var hook := func(f: int) -> void:
		if dh.game.tick >= 300 and not ph.cut and dh.net.link == &"ok" and f < 100000:
			# обрыв: всё в пути пропало, обе стороны узнали
			ph.cut = true
			pg.cut = true
			ph.lose_all()
			pg.lose_all()
			dh.net.on_link(&"lost")
			dg.net.on_link(&"lost")
	_run(pair, bots, 360, 2000, hook)
	stalled[0] = dh.net.link == &"lost" and not dh.can_step() and not dg.can_step()
	var t_h := dh.game.tick
	var t_g := dg.game.tick
	SimHarness.check(stalled[0] and t_h < 360, "связь пропала — обе игры стоят (такты %d и %d)" % [t_h, t_g])
	ph.cut = false
	pg.cut = false
	dg.net.on_reconnected()
	dh.net.on_reconnected()
	_run(pair, bots, TICKS, 20000)
	SimHarness.check(dh.game.tick == TICKS and dg.game.tick == TICKS and dh.net.link == &"ok", "переподключились — партия дошла до %d" % TICKS)
	SimHarness.check(dh.game.checksums == dg.game.checksums and dh.game.checksum() == dg.game.checksum(), "суммы те же, что у друга")
	var ref := _pair(31, 4, 4)
	_run(ref, [NetBot.new(0), NetBot.new(1)], TICKS)
	SimHarness.check(dh.game.checksum() == (ref[0] as GameDriver).game.checksum(), "и те же, что у партии без обрыва")
	_free_pair(ref)
	_free_pair(pair)


func _test_desync() -> void:
	print("[расхождение]")
	var pair := _pair(5)
	var dh: GameDriver = pair[0]
	var dg: GameDriver = pair[1]
	var bots := [NetBot.new(0), NetBot.new(1)]
	_run(pair, bots, 100)
	# лишний приказ только у хозяина (как сбой): работник хозяина идёт в сторону
	var q := dh.game.query as GameQueryImpl
	var w := PackedInt32Array()
	for u in q.units_of(0):
		if q.unit_flags(u) & UnitStats.WORKER:
			w.append(u)
			break
	var c := SimCmd.move(w, q.unit_pos(w[0]) + Vector2(30, 0))
	c[SimCmd.H_PLAYER] = 0
	c[SimCmd.H_TICK] = dh.game.tick + 1
	c[SimCmd.H_SEQ] = 999999
	dh.game.queue.preload_cmds([c] as Array[PackedInt32Array])
	_run(pair, bots, 400, 600)
	var hit := dh.net.link == &"desync" and dg.net.link == &"desync"
	SimHarness.check(hit and dh.net.desync_tick == dg.net.desync_tick and dh.net.desync_tick <= 150,
		"обе игры остановились на сверке такта %d" % dh.net.desync_tick)
	SimHarness.check(dh.paused and dg.paused and not dh.can_step(), "дальше не шагают")
	var files := dh.net.saved.size() + dg.net.saved.size()
	var exist := true
	for p in dh.net.saved + dg.net.saved:
		exist = exist and FileAccess.file_exists(p)
	SimHarness.check(files == 4 and exist, "повторы обеих игр сохранены (свой и друга у каждой): %s" % ", ".join(dh.net.saved))
	for p in dh.net.saved + dg.net.saved:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	_free_pair(pair)


func _test_single() -> void:
	print("[одиночная игра — как была]")
	var d := GameDriver.new()
	d.autostart = false
	d.game_impl = _impl.duplicate()
	d.start_game(3, &"kokand", 0)
	SimHarness.check(d.net == null and d.can_step(), "без партии по сети can_step() — всегда да")
	d.request_pause(true)
	var p := d.paused
	d.request_pause(false)
	d.request_speed(3.0)
	SimHarness.check(p and not d.paused and is_equal_approx(d.time_scale, 3.0), "пауза и скорость — сразу")
	d.restart()
	SimHarness.check(d.game.tick == 0, "«Начать заново» работает")
	d.free()
