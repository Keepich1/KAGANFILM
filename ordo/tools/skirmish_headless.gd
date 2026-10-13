extends SceneTree
## Автобои «Города» без графики (ТЗ 14 «автобои ИИ против ИИ»; ARCHITECTURE §15): N матчей ИИ против ИИ,
## стороны меняются местами через матч; каждый матч проверяется повтором (вторая прогонка из записи
## должна дать те же контрольные суммы), запись повтора кладётся в renders/skirmish/.
## Запуск — tools/skirmish_headless.sh N [--minutes=M] [--seed=S] [--difficulty=D] [--stub | --impl=stub] [--no_fort]
## (реализации — GameSim.impl_for: по умолчанию настоящие, если они в проекте; ORDO_IMPL=stub — тоже заглушки)
##   godot --headless --path ordo --script res://tools/skirmish_headless.gd -- --n=2 --minutes=15
## Своей экономики у ИИ нет (этап 3), поэтому стены, ворота, башню и көч кыпчаков ставит сценарий ScriptedFort
## (приказами через GameSim.submit — они в журнале повтора); --no_fort — без него.
## События считаются по ходу матча (курсор каждые 60 тактов: кольцо SimEvents — 8192 последних).
## Код выхода 1 — повтор разошёлся с матчем или (со сценарием, на настоящих модулях) чего-то из проверок
## не было: набеги обеих сторон, стены и ворота построены, көч (свернули и развернули), олжо кочевникам.

var _args := {}


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var n := int(_args.get("n", "2"))
	var minutes := float(_args.get("minutes", "15"))
	var seed0 := int(_args.get("seed", "1"))
	var diff := clampi(int(_args.get("difficulty", "0")), 0, 2)
	var out_dir := String(_args.get("out", "res://renders/skirmish"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var impl := GameSim.impl_for(OS.get_cmdline_user_args(), OS.get_environment("ORDO_IMPL"))
	if _args.has("stub"):
		impl = GameSim.impl_for(PackedStringArray(["--impl=stub"]))
	var fails := 0
	var wins := {"kokand": 0, "kipchak": 0, "—": 0}
	print("Автобои «Города»: матчей %d, по %.0f мин, зерно с %d, сложность %d" % [n, minutes, seed0, diff])
	for m in n:
		var f0 := &"kokand" if m % 2 == 0 else &"kipchak"
		var f1 := &"kipchak" if m % 2 == 0 else &"kokand"
		var players := [{"faction": f0, "team": 0, "ctrl": PlayerTable.Ctrl.AI, "difficulty": diff},
			{"faction": f1, "team": 1, "ctrl": PlayerTable.Ctrl.AI, "difficulty": diff}]
		var g := GameSim.new()
		g.impl = impl
		g.setup(MapValley.MAP, players, seed0 + m)
		if m == 0:
			print("реализации: ", g.impl_names())
		var end := roundi(minutes * 60.0 * 30.0)
		var forts: Array[ScriptedFort] = []
		if not _args.has("no_fort"):
			for p in players.size():
				forts.append(ScriptedFort.new(p))
		var st := _new_stats()
		var cursor := 0
		var t0 := Time.get_ticks_usec()
		while g.tick < end and not g.over:
			for f in forts:
				for c in f.commands(g.tick, g.query):
					g.submit(f.player, c)
			g.step()
			if g.tick % 60 == 0:
				cursor = _tally(g, st, cursor)
		cursor = _tally(g, st, cursor)
		var ms_tick := (Time.get_ticks_usec() - t0) / 1000.0 / maxi(g.tick, 1)
		var winner := "—"
		if g.over and g.winner >= 0:
			winner = String(players[g.winner]["faction"])
		wins[winner] += 1
		var rec := g.replay_record()
		var path := "%s/match_%02d_seed%d.ordorep" % [out_dir, m, seed0 + m]
		Replay.save(path, rec)
		var t1 := Time.get_ticks_usec()
		var ok := Replay.verify(rec, impl)
		var replay_s := (Time.get_ticks_usec() - t1) / 1.0e6
		if not ok:
			fails += 1
		print("матч %d (зерно %d): %s против %s — %s за %s; набеги %s; волны до %s; погибло %d; построек разрушено %d; отказов %d" % [
			m, seed0 + m, f0, f1, ("победа: " + winner) if winner != "—" else "без победителя", _clock(g.tick),
			str(st["raids"]), str(st["max_wave"]), st["died"], st["destroyed"], st["rejected"]])
		print("   %.3f мс/такт; контрольная сумма %d (%d записей); повтор %s за %.1f с; %s" % [ms_tick, g.checksum(),
			g.checksums.size(), "совпал" if ok else "РАЗОШЁЛСЯ: " + Replay.last_error, replay_s, path])
		print("   стены: построено звеньев %s, ворот %s, башен %s; разрушено звеньев и ворот %d; көч: свёрнуто %d, развёрнуто %d; олжо: %s; угнано стад %d" % [
			str(st["links"]), str(st["gates"]), str(st["towers"]), st["fort_lost"], st["packed"], st["unpacked"],
			_loot_text(st["loot"]), st["stolen"]])
		if not forts.is_empty() and g.real_impl():
			var miss := _missing(st, players, g)
			if not miss.is_empty():
				fails += 1
				print("   НЕ БЫЛО: ", ", ".join(miss))
	print("")
	print("Итог: Коканд %d, кыпчаки %d, без победителя %d; повторов разошлось: %d" % [wins["kokand"], wins["kipchak"], wins["—"], fails])
	print("ИТОГ: ", "ВСЁ ПРОШЛО" if fails == 0 else "ПРОВАЛОВ: %d" % fails)
	quit(1 if fails > 0 else 0)


func _clock(t: int) -> String:
	var s := t / 30
	return "%d:%02d" % [s / 60, s % 60]


func _new_stats() -> Dictionary:
	return {"raids": [0, 0], "max_wave": [0, 0], "died": 0, "destroyed": 0, "rejected": 0, "links": [0, 0],
		"gates": [0, 0], "towers": [0, 0], "fort_lost": 0, "packed": 0, "unpacked": 0, "loot": {}, "stolen": 0}


## События с курсора по сей такт → счётчики; вернёт новый курсор
func _tally(g: GameSim, st: Dictionary, cursor: int) -> int:
	var E := g.events
	var d := g.defs
	var r := E.range_since(cursor)
	for seq in range(r.x, r.y):
		var i := E.at(seq)
		var p := E.e_player[i]
		match E.e_kind[i]:
			SimEvents.Ev.RAID_STARTED:
				var rp := E.e_a[i]
				if rp >= 0 and rp < 2:
					st["raids"][rp] += 1
					st["max_wave"][rp] = maxi(st["max_wave"][rp], E.e_b[i])
			SimEvents.Ev.UNIT_DIED:
				st["died"] += 1
			SimEvents.Ev.BUILDING_DESTROYED:
				st["destroyed"] += 1
				var bt := E.e_b[i]
				if bt >= 0 and bt < d.b_kind.size() and (d.b_kind[bt] == Defs.BKind.WALL or d.b_kind[bt] == Defs.BKind.GATE):
					st["fort_lost"] += 1
			SimEvents.Ev.CMD_REJECTED:
				st["rejected"] += 1
			SimEvents.Ev.BUILDING_DONE:
				var bt := E.e_b[i]
				if p >= 0 and p < 2 and bt >= 0 and bt < d.b_kind.size():
					match d.b_kind[bt]:
						Defs.BKind.WALL: st["links"][p] += 1
						Defs.BKind.GATE: st["gates"][p] += 1
						Defs.BKind.TOWER: st["towers"][p] += 1
			SimEvents.Ev.PACKED:
				st["packed"] += 1
			SimEvents.Ev.UNPACKED:
				st["unpacked"] += 1
			SimEvents.Ev.LOOT:
				var res := d.res_ids[E.e_a[i]] if E.e_a[i] >= 0 and E.e_a[i] < d.res_ids.size() else "?"
				var key := "%d:%s" % [p, res]
				st["loot"][key] = int(st["loot"].get(key, 0)) + E.e_b[i]
			SimEvents.Ev.HERD_STOLEN:
				st["stolen"] += 1
	return r.y


func _loot_text(loot: Dictionary) -> String:
	if loot.is_empty():
		return "нет"
	var parts: Array[String] = []
	for k: String in loot:
		parts.append("игрок %s +%d" % [k.replace(":", " "), int(loot[k]) / 1000])
	return ", ".join(parts)


## Чего не было в матче со сценарием (пусто — всё было)
func _missing(st: Dictionary, players: Array, g: GameSim) -> Array[String]:
	var miss: Array[String] = []
	for p in 2:
		if st["raids"][p] == 0:
			miss.append("набегов игрока %d" % p)
		if st["links"][p] == 0:
			miss.append("стены игрока %d" % p)
		if st["gates"][p] == 0:
			miss.append("ворот игрока %d" % p)
	var kip := -1
	for p in players.size():
		if String(players[p]["faction"]) == "kipchak":
			kip = p
	if st["packed"] == 0 or st["unpacked"] == 0:
		miss.append("көч (свёрнуто %d, развёрнуто %d)" % [st["packed"], st["unpacked"]])
	var olzho := false
	for k: String in st["loot"]:
		olzho = olzho or k.begins_with("%d:" % kip)
	if not olzho:
		miss.append("олжо кыпчаков")
	return miss
