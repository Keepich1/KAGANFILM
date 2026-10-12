class_name SimHarness
extends RefCounted
## Общие помощники безголовых тестов «Города» (ARCHITECTURE §15, §19.0 #16). Ведущий (M0).
##
##   extends SceneTree
##   func _init() -> void:
##       var game := SimHarness.make_game()            # GameSim (когда GAME его сделает), иначе null
##       SimHarness.run_s(game, 10.0)
##       SimHarness.check(game.tick == 300, "10 с = 300 тактов")
##       SimHarness.check_range(x, 0.9, 1.1, "доход")
##       SimHarness.finish(self)                       # ИТОГ и код выхода
##
## До GameSim пакеты собирают свою связку на заглушках: SimHarness.make_stubs().

## Провалы с начала теста (finish() печатает итог и выходит с кодом 1, если были)
static var fails := 0


## Игра «Город» на карте MapValley: players — [{faction, team, ctrl, difficulty}] (пусто — Коканд-человек
## против кыпчаков-ИИ). Класс GameSim ищется по имени (его делает GAME); пока его нет — null.
## (Тип результата — RefCounted, пока scripts/game/game_sim.gd нет; GAME уточнит до GameSim.)
static func make_game(players: Array = [], rules_id := &"GOROD", p_seed := 1) -> RefCounted:
	var path := _class_path(&"GameSim")
	if path == "":
		push_error("SimHarness.make_game: нет класса GameSim (scripts/game/game_sim.gd)")
		return null
	var list := default_players()
	if not players.is_empty():
		list.clear()
		for p: Dictionary in players:
			list.append(p)
	var game: RefCounted = load(path).new()
	game.call("setup", MapValley.MAP, list, p_seed, rules_id)
	return game


static func default_players() -> Array[Dictionary]:
	return [{"faction": &"kokand", "team": 0, "ctrl": PlayerTable.Ctrl.HUMAN, "difficulty": 0},
		{"faction": &"kipchak", "team": 1, "ctrl": PlayerTable.Ctrl.AI, "difficulty": 0}]


## Связка на заглушках: {defs, events, port: CombatPortStub, nav: NavStub, econ: EconStub}
static func make_stubs(p_seed := 1, rules_id := &"GOROD") -> Dictionary:
	var defs := Defs.shared()
	var rules := defs.rules_of(rules_id)
	var events := SimEvents.new()
	var nav := NavStub.new()
	var port := CombatPortStub.new()
	var econ := EconStub.new()
	nav.setup(Terrain.info(), defs, econ, port)
	port.setup(defs, nav, {"teams": 2, "homes": PackedVector2Array(), "corpse_s": rules.get("corpse_s", -1),
		"bounds_origin": nav.origin, "bounds_size": Vector2(nav.w, nav.h) * NavApi.CELL})
	econ.setup(defs, rules, port, nav, events, p_seed)
	return {"defs": defs, "events": events, "port": port, "nav": nav, "econ": econ}


## Прогнать игру s секунд (game.step() × 30 · s)
static func run_s(game: Object, s: float) -> void:
	for i in roundi(s * 30.0):
		game.call("step")


static func check(ok: bool, what: String) -> bool:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		fails += 1
	return ok


static func check_range(v: float, lo: float, hi: float, what: String) -> bool:
	return check(v >= lo and v <= hi, "%s: %s в [%s, %s]" % [what, str(v), str(lo), str(hi)])


## Ровное место для тестов — луг поля боя (CONTRACT §3; Terrain.marker("meadow") = (90, 0))
static func flat_spot() -> Vector2:
	var m := Terrain.marker("meadow")
	return Vector2(m.x, m.z) if m != Vector3.ZERO else Vector2(90, 0)


## Печатает ИТОГ и завершает тест (код 1 при провалах)
static func finish(tree: SceneTree) -> void:
	print("")
	print("ИТОГ: ", "ВСЁ ПРОШЛО" if fails == 0 else "ПРОВАЛОВ: %d" % fails)
	tree.quit(1 if fails > 0 else 0)


static func _class_path(name: StringName) -> String:
	for c: Dictionary in ProjectSettings.get_global_class_list():
		if c["class"] == name:
			return c["path"]
	return ""
