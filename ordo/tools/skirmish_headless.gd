extends SceneTree
## Автобои «Города» без графики (ТЗ 14 «автобои ИИ против ИИ»; ARCHITECTURE §15): N матчей ИИ против ИИ,
## стороны меняются местами через матч; каждый матч проверяется повтором (вторая прогонка из записи
## должна дать те же контрольные суммы), запись повтора кладётся в renders/skirmish/.
## Запуск — tools/skirmish_headless.sh N [--minutes=M] [--seed=S] [--difficulty=D] [--stub | --impl=stub]
## (реализации — GameSim.impl_for: по умолчанию настоящие, если они в проекте; ORDO_IMPL=stub — тоже заглушки)
##   godot --headless --path ordo --script res://tools/skirmish_headless.gd -- --n=2 --minutes=15
## Код выхода 1 — повтор разошёлся с матчем.

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
		var t0 := Time.get_ticks_usec()
		while g.tick < end and not g.over:
			g.step()
		var ms_tick := (Time.get_ticks_usec() - t0) / 1000.0 / maxi(g.tick, 1)
		var st := _stats(g)
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
	print("")
	print("Итог: Коканд %d, кыпчаки %d, без победителя %d; повторов разошлось: %d" % [wins["kokand"], wins["kipchak"], wins["—"], fails])
	print("ИТОГ: ", "ВСЁ ПРОШЛО" if fails == 0 else "ПРОВАЛОВ: %d" % fails)
	quit(1 if fails > 0 else 0)


func _clock(t: int) -> String:
	var s := t / 30
	return "%d:%02d" % [s / 60, s % 60]


func _stats(g: GameSim) -> Dictionary:
	var raids := [0, 0]
	var max_wave := [0, 0]
	var died := 0
	var destroyed := 0
	var rejected := 0
	var r := g.events.range_since(0)
	var E := g.events
	for seq in range(r.x, r.y):
		var i := E.at(seq)
		match E.e_kind[i]:
			SimEvents.Ev.RAID_STARTED:
				var p := E.e_a[i]
				if p >= 0 and p < 2:
					raids[p] += 1
					max_wave[p] = maxi(max_wave[p], E.e_b[i])
			SimEvents.Ev.UNIT_DIED:
				died += 1
			SimEvents.Ev.BUILDING_DESTROYED:
				destroyed += 1
			SimEvents.Ev.CMD_REJECTED:
				rejected += 1
	return {"raids": raids, "max_wave": max_wave, "died": died, "destroyed": destroyed, "rejected": rejected}
