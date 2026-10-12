extends SceneTree
## Проверка определений «Города» (ARCHITECTURE §15; ведущий → ECON после M0):
##   godot --headless --path ordo --script res://tests/test_defs.gd
## 1) Defs.validate() — схема и перекрёстные ссылки без ошибок;
## 2) размеры построек — ТЗ 11.6, клетки следа — §6.4; цены и старт — ТЗ 5.1–5.3, 6;
## 3) UnitEcon ≡ UnitStats по цене и времени найма (старое зеркало);
## 4) Defs.hash() устойчив: одинаков при повторной сборке, меняется от правки чисел.

## ТЗ 11.6: размеры в плане, м
const SIZES := {
	"urda": Vector2(18, 18), "uy": Vector2(8, 8), "tegirmon": Vector2(9, 9), "ombor": Vector2(9, 9),
	"kazarma": Vector2(16, 12), "otxona": Vector2(16, 12), "topxona": Vector2(14, 12), "burj": Vector2(7, 7),
	"darvoza": Vector2(7.2, 3), "ordo": Vector2(14, 14), "boz": Vector2(7, 7), "koroo": Vector2(14, 14),
	"ken": Vector2(8, 8), "jooker": Vector2(12, 10), "jylky": Vector2(16, 12), "kurultai": Vector2(14, 14),
	"munara": Vector2(5, 5), "darbaza": Vector2(6.4, 2.4), "devor": Vector2(3.6, 1.8), "tosh": Vector2(3.6, 2.2),
	"chep": Vector2(3.4, 1.2), "dala": Vector2(16, 16),
}
## ТЗ 5.2, 5.3, 6: цены
const COSTS := {
	"uy": {"wood": 80, "stone": 20}, "dala": {"wood": 60}, "tegirmon": {"wood": 120}, "ombor": {"wood": 100},
	"kazarma": {"wood": 200, "stone": 100}, "otxona": {"wood": 220, "stone": 60},
	"topxona": {"wood": 200, "stone": 200, "gold": 100},
	"boz": {"wood": 40}, "koroo": {"wood": 60}, "ken": {"wood": 80}, "jooker": {"wood": 120},
	"jylky": {"wood": 150, "gold": 40}, "kurultai": {"wood": 200, "gold": 150},
	"devor": {"wood": 3}, "tosh": {"stone": 8}, "darvoza": {"wood": 40, "stone": 30}, "burj": {"stone": 80, "wood": 30},
	"chep": {"wood": 5}, "darbaza": {"wood": 45}, "munara": {"wood": 70},
}
## ТЗ 6: HP укреплений; ТЗ 5.2–5.3: население
const HP := {"devor": 420, "chep": 260, "tosh": 1200, "darvoza": 1600, "darbaza": 700, "burj": 2000, "munara": 700}
const POP := {"urda": 25, "uy": 15, "ordo": 25, "boz": 10}
## §6.4: клетки следа
const CELLS := {"urda": Vector2i(5, 5), "uy": Vector2i(2, 2), "tegirmon": Vector2i(3, 3), "kazarma": Vector2i(4, 3),
	"boz": Vector2i(2, 2)}


func _init() -> void:
	var defs := Defs.build()
	print("[схема]")
	var errs := defs.validate()
	for e in errs:
		print("    ", e)
	SimHarness.check(errs.is_empty(), "Defs.validate() без ошибок (%d)" % errs.size())
	SimHarness.check(Defs.CELL == NavApi.CELL, "клетка Defs = клетка NavApi (4 м)")
	SimHarness.check(defs.res(&"food") == 0 and defs.res(&"wood") == 1 and defs.res(&"stone") == 2 and defs.res(&"gold") == 3,
		"общие ресурсы — первые четыре: еда, дерево, камень, золото")
	SimHarness.check(defs.R == ResourceDefs.RESOURCES.size() and defs.b_ids.size() == BuildingDefs.BUILDINGS.size(),
		"все записи собраны (ресурсов %d, построек %d)" % [defs.R, defs.b_ids.size()])
	_sizes(defs)
	_costs(defs)
	_units(defs)
	_factions(defs)
	_hash(defs)
	SimHarness.finish(self)


func _sizes(defs: Defs) -> void:
	print("[размеры ТЗ 11.6, клетки §6.4]")
	var bad := PackedStringArray()
	for id: String in SIZES:
		var b := defs.building(id)
		if b < 0 or not defs.b_size[b].is_equal_approx(SIZES[id]):
			bad.append(id)
	SimHarness.check(bad.is_empty(), "размеры построек по ТЗ 11.6 %s" % ("" if bad.is_empty() else str(bad)))
	for id: String in CELLS:
		var b := defs.building(id)
		var c := defs.cells_of(b, 0)
		SimHarness.check(c == CELLS[id], "клетки %s: %s" % [id, c])
	var kaz := defs.building(&"kazarma")
	SimHarness.check(defs.cells_of(kaz, 1) == Vector2i(3, 4), "поворот на четверть меняет клетки местами")
	SimHarness.check(is_equal_approx(defs.b_platform_h[defs.building(&"burj")], 8.4)
		and is_equal_approx(defs.b_platform_h[defs.building(&"munara")], 7.0), "площадки башен 8,4 и 7 м")
	var dv := defs.building(&"devor")
	var ch := defs.building(&"chep")
	SimHarness.check(is_equal_approx(defs.b_link_len[dv] - defs.b_link_overlap[dv], 3.2)
		and is_equal_approx(defs.b_link_len[ch] - defs.b_link_overlap[ch], 3.0), "шаг звеньев: девор 3,2 м, чеп 3,0 м")


func _costs(defs: Defs) -> void:
	print("[цены и HP ТЗ 5.2, 5.3, 6]")
	var bad := PackedStringArray()
	for id: String in COSTS:
		var b := defs.building(id)
		if b < 0 or defs.building_cost(b) != defs.cost_of(COSTS[id]):
			bad.append(id)
	SimHarness.check(bad.is_empty(), "цены построек %s" % ("" if bad.is_empty() else str(bad)))
	bad.clear()
	for id: String in HP:
		if defs.b_hp_c[defs.building(id)] != int(HP[id]) * 100:
			bad.append(id)
	SimHarness.check(bad.is_empty(), "HP укреплений %s" % ("" if bad.is_empty() else str(bad)))
	bad.clear()
	for id: String in POP:
		if defs.b_pop_cap[defs.building(id)] != POP[id]:
			bad.append(id)
	SimHarness.check(bad.is_empty(), "население: урда/ордо +25, уй +15, боз үй +10")
	SimHarness.check(defs.b_build_ticks[defs.building(&"boz")] == 12 * 30, "боз үй ставится за 12 с")
	var dala := defs.building(&"dala")
	SimHarness.check(defs.b_work_slots[dala] == 4 and defs.b_kind[dala] == Defs.BKind.FIELD, "дала — поле на 4 работника")


func _units(defs: Defs) -> void:
	print("[юниты: UnitEcon ≡ UnitStats]")
	var bad := PackedStringArray()
	for id: String in UnitStats.UNITS:
		var u := defs.unit(id)
		var st := UnitStats.get_stats(id)
		if u < 0 or defs.unit_cost(u) != defs.cost_of(st["cost"]) or defs.u_train_ticks[u] != roundi(float(st["time"]) * 30.0):
			bad.append(id)
	SimHarness.check(bad.is_empty(), "цена и время найма совпадают (%d юнитов) %s" % [UnitStats.UNITS.size(),
		"" if bad.is_empty() else str(bad)])
	var sarboz := defs.unit(&"sarboz")
	SimHarness.check(defs.u_upkeep_milli_min[sarboz] == 700, "содержание бойца 0,7 еды в минуту (ТЗ 5.1)")
	var kaz := defs.building(&"kazarma")
	SimHarness.check(defs.b_trains[kaz].has(sarboz) and defs.b_trains[kaz].has(defs.unit(&"yuzboshi")),
		"казарма нанимает сарбозов и юзбоши")
	SimHarness.check(defs.b_trains[defs.building(&"ordo")].has(defs.unit(&"malchy")), "ордо нанимает малчы")


func _factions(defs: Defs) -> void:
	print("[стороны ТЗ 5.1]")
	var kok := defs.faction(&"kokand")
	var kip := defs.faction(&"kipchak")
	var R := defs.R
	SimHarness.check(defs.f_start_res.slice(kok * R, kok * R + R) == defs.cost_of({"food": 500, "wood": 400, "stone": 250, "gold": 200}),
		"старт Коканда: 500 еды, 400 дерева, 250 камня, 200 золота")
	SimHarness.check(defs.f_start_res.slice(kip * R, kip * R + R) == defs.cost_of({"food": 350, "wood": 380, "gold": 150}),
		"старт кыпчаков: 350 еды, 380 дерева, 0 камня, 150 золота")
	SimHarness.check(defs.has_trait(kip, "koch") and not defs.has_trait(kok, "koch"), "көч — только у кыпчаков")
	var g := defs.res(&"gold")
	SimHarness.check(defs.f_bounty_kill[kip * R + g] == 4000 and defs.f_bounty_worker[kip * R + g] == 10000
		and defs.f_bounty_hq[kip * R + g] == 400000, "олжо: 4 / 10 / 400 золота (ТЗ 5.4)")
	var gorod := defs.rules_of(&"GOROD")
	SimHarness.check(gorod["corpse_ticks"] == 900 and gorod["path_per_tick"] == 16 and gorod["path_cells_per_tick"] == 8000,
		"правила «Города»: тела 30 с, 16 путей и 8000 клеток за такт")
	SimHarness.check(defs.rules_of(&"BATTLE")["corpse_ticks"] == -1, "в сражении тела не исчезают")
	SimHarness.check(defs.ai["RAID"]["peace_ticks"] == [9000, 14400, 21600], "мирный период 5/8/12 мин в тактах")


func _hash(defs: Defs) -> void:
	print("[сумма определений]")
	var h := defs.hash()
	print("  Defs.hash() = %d" % h)
	SimHarness.check(h != 0 and Defs.build().hash() == h, "повторная сборка — та же сумма")
	SimHarness.check(Defs.shared().hash() == h, "общий экземпляр — та же сумма")
	var patched := Defs.build({"buildings": {"uy": {"hp": 650}}})
	SimHarness.check(patched.hash() != h and patched.b_hp_c[patched.building(&"uy")] == 65000,
		"правка числа меняет сумму и попадает в таблицы")
	var renamed := Defs.build({"buildings": {"uy": {"name": "Дом"}}})
	SimHarness.check(renamed.hash() == h, "подписи в сумму не входят")
