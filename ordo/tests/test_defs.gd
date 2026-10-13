extends SceneTree
## Проверка определений «Города» (ARCHITECTURE §15; ведущий → ECON после M0):
##   godot --headless --path ordo --script res://tests/test_defs.gd
## 1) Defs.validate() — схема и перекрёстные ссылки без ошибок;
## 2) размеры построек — ТЗ 11.6 и docs/ECONOMY.md, клетки следа — ARCHITECTURE §6.4;
## 3) цены, HP, население — ТЗ 5.1–5.3, 6 с правками ECONOMY.md (там, где цифры расходятся, верны они);
## 4) UnitEcon ≡ UnitStats по цене (еда, дерево, камень, золото) и времени найма — старое зеркало;
## 5) ключевые числа ECONOMY.md: добыча, содержание, кони, короо, вода, голод, олжо;
## 6) Defs.hash() устойчив: одинаков при повторной сборке, меняется от правки чисел.

## ТЗ 11.6 и ECONOMY.md §2.1, §3.1: размеры в плане, м
const SIZES := {
	"urda": Vector2(18, 18), "uy": Vector2(8, 8), "tegirmon": Vector2(9, 9), "ombor": Vector2(9, 9),
	"kazarma": Vector2(16, 12), "otxona": Vector2(16, 12), "topxona": Vector2(14, 12), "burj": Vector2(7, 7),
	"darvoza": Vector2(7.2, 3), "ordo": Vector2(14, 14), "boz": Vector2(7, 7), "koroo": Vector2(14, 14),
	"ken": Vector2(8, 8), "jooker": Vector2(12, 10), "jylky": Vector2(16, 12), "kurultai": Vector2(14, 14),
	"munara": Vector2(5, 5), "darbaza": Vector2(6.4, 2.4), "devor": Vector2(3.6, 1.8), "tosh": Vector2(3.6, 2.2),
	"chep": Vector2(3.4, 1.2), "dala": Vector2(16, 16), "togon": Vector2(10, 6), "aryk": Vector2(4, 2),
	"xumdon": Vector2(10, 8), "bozor": Vector2(16, 16),
}
## ТЗ 5.2, 5.3, 6; ECONOMY §2.1, §2.9 (Тош девор и Бурж — за ғишт)
const COSTS := {
	"uy": {"wood": 80, "stone": 20}, "dala": {"wood": 60}, "tegirmon": {"wood": 120}, "ombor": {"wood": 100},
	"kazarma": {"wood": 200, "stone": 100}, "otxona": {"wood": 220, "stone": 60},
	"topxona": {"wood": 200, "stone": 200, "gold": 100}, "togon": {"wood": 80, "stone": 40},
	"aryk": {"wood": 2}, "xumdon": {"wood": 120, "stone": 60}, "bozor": {"wood": 150, "stone": 80},
	"boz": {"wood": 40}, "koroo": {"wood": 60}, "ken": {"wood": 80}, "jooker": {"wood": 120},
	"jylky": {"wood": 150, "gold": 40}, "kurultai": {"wood": 200, "gold": 150},
	"devor": {"wood": 3}, "tosh": {"brick": 6, "stone": 2}, "darvoza": {"wood": 40, "stone": 30},
	"burj": {"wood": 30, "stone": 30, "brick": 50}, "chep": {"wood": 5}, "darbaza": {"wood": 45}, "munara": {"wood": 70},
}
## ТЗ 6 (укрепления) и ECONOMY §2.1, §3.1 (хозяйство)
const HP := {"devor": 420, "chep": 260, "tosh": 1200, "darvoza": 1600, "darbaza": 700, "burj": 2000, "munara": 700,
	"urda": 4000, "uy": 800, "togon": 2500, "xumdon": 1000, "bozor": 1600, "kazarma": 1800, "otxona": 1700,
	"topxona": 2200, "ordo": 2500, "boz": 300, "koroo": 400, "ken": 400, "jooker": 800, "jylky": 800, "kurultai": 1600}
const POP := {"urda": 25, "uy": 15, "ordo": 25, "boz": 10}
## ARCHITECTURE §6.4: клетки следа
const CELLS := {"urda": Vector2i(5, 5), "uy": Vector2i(2, 2), "tegirmon": Vector2i(3, 3), "kazarma": Vector2i(4, 3),
	"boz": Vector2i(2, 2)}
## Старое зеркало UnitStats.cost — только эти ресурсы
const MIRROR_RES := ["food", "wood", "stone", "gold"]


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
	var bad_schema := Defs.build({"buildings": {"uy": {"colour": 1}}, "units": {"sarboz": {"trained_at": ["nowhere"]}}})
	SimHarness.check(bad_schema.validate().size() == 2, "лишний ключ и битая ссылка ловятся validate()")
	_sizes(defs)
	_costs(defs)
	_units(defs)
	_economy(defs)
	_factions(defs)
	_sb1(defs)
	_hash(defs)
	SimHarness.finish(self)


func _sizes(defs: Defs) -> void:
	print("[размеры ТЗ 11.6 и ECONOMY, клетки §6.4]")
	var bad := PackedStringArray()
	for id: String in SIZES:
		var b := defs.building(id)
		if b < 0 or not defs.b_size[b].is_equal_approx(SIZES[id]):
			bad.append(id)
	SimHarness.check(bad.is_empty(), "размеры построек %s" % ("" if bad.is_empty() else str(bad)))
	for id: String in CELLS:
		var c := defs.cells_of(defs.building(id), 0)
		SimHarness.check(c == CELLS[id], "клетки %s: %s" % [id, c])
	SimHarness.check(defs.cells_of(defs.building(&"kazarma"), 1) == Vector2i(3, 4), "поворот на четверть меняет клетки местами")
	SimHarness.check(is_equal_approx(defs.b_platform_h[defs.building(&"burj")], 8.4)
		and is_equal_approx(defs.b_platform_h[defs.building(&"munara")], 7.0), "площадки башен 8,4 и 7 м")
	var dv := defs.building(&"devor")
	var ch := defs.building(&"chep")
	SimHarness.check(is_equal_approx(defs.b_link_len[dv] - defs.b_link_overlap[dv], 3.2)
		and is_equal_approx(defs.b_link_len[ch] - defs.b_link_overlap[ch], 3.0), "шаг звеньев: девор 3,2 м, чеп 3,0 м")


func _costs(defs: Defs) -> void:
	print("[цены, HP, население]")
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
	SimHarness.check(bad.is_empty(), "HP построек %s" % ("" if bad.is_empty() else str(bad)))
	bad.clear()
	for id: String in POP:
		if defs.b_pop_cap[defs.building(id)] != POP[id]:
			bad.append(id)
	SimHarness.check(bad.is_empty(), "население: урда/ордо +25, уй +15, боз үй +10")
	SimHarness.check(defs.b_build_ticks[defs.building(&"boz")] == 12 * 30, "боз үй ставится за 12 с")
	var dala := defs.building(&"dala")
	SimHarness.check(defs.b_work_slots[dala] == 4 and defs.b_kind[dala] == Defs.BKind.FIELD
		and defs.b_flags[dala] & Defs.BF_UNBREAKABLE != 0, "дала — поле на 4 работника, не ломается")


func _units(defs: Defs) -> void:
	print("[юниты: UnitEcon ≡ UnitStats]")
	var bad := PackedStringArray()
	for id: String in UnitStats.UNITS:
		var u := defs.unit(id)
		var st := UnitStats.get_stats(id)
		var mirror := defs.cost_of(st["cost"])
		var own := defs.unit_cost(u) if u >= 0 else PackedInt32Array()
		var same := u >= 0 and defs.u_train_ticks[u] == roundi(float(st["time"]) * 30.0)
		for r: String in MIRROR_RES:
			var i := defs.res(r)
			same = same and own[i] == mirror[i]
		if not same:
			bad.append(id)
	SimHarness.check(bad.is_empty(), "цена и время найма совпадают (%d юнитов) %s" % [UnitStats.UNITS.size(),
		"" if bad.is_empty() else str(bad)])
	var R := defs.R
	var horse := defs.res(&"horse")
	var riders := 0
	for id in ["atchan", "chabuulchu", "sayisker", "juz_bashy", "batyr", "kolbashchy"]:
		riders += 1 if defs.u_cost[defs.unit(id) * R + horse] == 1000 else 0
	SimHarness.check(riders == 6, "всадник кыпчаков стоит 1 коня (ECONOMY §3.2)")
	SimHarness.check(defs.b_trains[defs.building(&"kazarma")].has(defs.unit(&"sarboz"))
		and defs.b_trains[defs.building(&"ordo")].has(defs.unit(&"malchy"))
		and defs.b_trains[defs.building(&"urda")].has(defs.unit(&"xos_navkar")), "кто где нанимается")
	SimHarness.check(defs.u_unique[defs.unit(&"lashkarboshi")] == 1 and defs.u_respawn_ticks[defs.unit(&"kolbashchy")] == 3600,
		"полководец — один, снова через 120 с")


func _economy(defs: Defs) -> void:
	print("[числа ECONOMY.md]")
	var R := defs.R
	var w := defs.unit(&"dehqon")
	SimHarness.check(defs.u_gather[w * R + defs.res(&"wood")] == 500 and defs.u_gather[w * R + defs.res(&"stone")] == 400
		and defs.u_gather[w * R + defs.res(&"gold")] == 350, "добыча: дерево 30, камень 24, золото 21 в минуту")
	SimHarness.check(defs.b_work[defs.building(&"dala")]["per_worker_min_milli"] == 30000, "поле у воды: 30 еды в минуту на работника")
	SimHarness.check(defs.u_upkeep_milli_min[defs.unit(&"sarboz")] == 700 and defs.u_upkeep_milli_min[defs.unit(&"navkar")] == 1400
		and defs.u_upkeep_milli_min[defs.unit(&"atchan")] == 700 and defs.u_upkeep_milli_min[defs.unit(&"zarbzan")] == 1000
		and defs.u_upkeep_milli_min[w] == 0, "содержание: пехота 0,7, конница Коканда 1,4, кыпчаков 0,7, пушка 1, работник 0")
	SimHarness.check(defs.u_pop[defs.unit(&"zarbzan")] == 3 and defs.u_pop[defs.unit(&"arba")] == 0, "население: пушка 3, арба 0")
	var ordo := defs.building(&"ordo")
	var koroo := defs.building(&"koroo")
	SimHarness.check(defs.b_herd[ordo] == defs.herd(&"horse") and defs.b_herd_start[ordo] == 6 and defs.b_herd_cap[ordo] == 10
		and defs.b_herd_breed[ordo] == 0, "коновязь ставки: 6 коней, до 10, без приплода")
	SimHarness.check(defs.b_herd_start[koroo] == 40 and defs.b_max_per_player[koroo] == 10 and defs.b_work_slots[koroo] == 2,
		"короо: отара 40, не больше 10, до 2 пастухов")
	SimHarness.check(defs.h_growth_steps[defs.herd(&"horse")] == PackedInt32Array([0, 0, 2, 3000, 10, 6000, 20, 9000]),
		"приплод коней по ступеням 0 / 3 / 6 / 9 в минуту")
	var togon := defs.building(&"togon")
	SimHarness.check(int(defs.b_network[togon]["places"]) == 8 and defs.b_water_place[defs.building(&"dala")] == 1
		and defs.b_rebuild_ticks[togon] == 450, "тўғон: 8 мест воды, восстановление 15 с")
	SimHarness.check(defs.b_tax_milli_min[defs.building(&"uy")] == 4000 and defs.b_max_per_player[defs.building(&"bozor")] == 1,
		"подать 4 золота с дома, один базар")
	var brick := defs.recipe(&"brick")
	SimHarness.check(defs.rc_out[brick * R + defs.res(&"brick")] * 60 / defs.rc_ticks[brick] * 30 == 12000,
		"Хумдон: 12 ғишт в минуту на работника")
	SimHarness.check(is_equal_approx(defs.m_mul[defs.modifier(&"famine_atk")], 0.8), "голод: атака −20%")


func _factions(defs: Defs) -> void:
	print("[стороны ТЗ 5.1, олжо, правила]")
	var kok := defs.faction(&"kokand")
	var kip := defs.faction(&"kipchak")
	var R := defs.R
	SimHarness.check(defs.f_start_res.slice(kok * R, kok * R + R) == defs.cost_of({"food": 500, "wood": 400, "stone": 250, "gold": 200}),
		"старт Коканда: 500 еды, 400 дерева, 250 камня, 200 золота")
	SimHarness.check(defs.f_start_res.slice(kip * R, kip * R + R) == defs.cost_of({"food": 350, "wood": 380, "gold": 150}),
		"старт кыпчаков: 350 еды, 380 дерева, 0 камня, 150 золота")
	SimHarness.check(defs.has_trait(kip, "koch") and not defs.has_trait(kok, "koch") and defs.has_trait(kok, "hashar"),
		"көч — у кыпчаков, Ҳашар — у Коканда")
	SimHarness.check(not defs.f_ui_res[kip].has(defs.res(&"stone")) and defs.f_ui_res[kip].has(defs.res(&"horse"))
		and defs.f_ui_res[kok].has(defs.res(&"brick")), "балка: у кыпчаков нет камня, есть кони; у Коканда — ғишт")
	var g := defs.res(&"gold")
	SimHarness.check(defs.f_bounty_kill[kip * R + g] == 4000 and defs.f_bounty_worker[kip * R + g] == 10000
		and defs.f_bounty_hq[kip * R + g] == 400000 and defs.f_bounty_share_pm[kip] == 300, "олжо: 4 / 10 / 400 золота, 30% цены здания")
	var gorod := defs.rules_of(&"GOROD")
	SimHarness.check(gorod["corpse_ticks"] == 900 and gorod["path_per_tick"] == 16 and gorod["path_cells_per_tick"] == 8000,
		"правила «Города»: тела 30 с, 16 путей и 8000 клеток за такт")
	SimHarness.check(defs.rules_of(&"BATTLE")["corpse_ticks"] == -1, "в сражении тела не исчезают")
	SimHarness.check(defs.ai["RAID"]["peace_ticks"] == [9000, 14400, 21600], "мирный период 5/8/12 мин в тактах")
	SimHarness.check(gorod["herd_theft"]["guard_r"] == 30.0 and gorod["herd_theft"]["circle_ticks"] == 180,
		"барымта: охрана 30 м, круг 6 с")


## Сб. 1 (ECONOMY §12.1, решения ведущего 2026-10-13): башни, стены и ворота — да, Сб. 2 — выключено
func _sb1(defs: Defs) -> void:
	print("[Сб. 1: что включено]")
	var on := func(id: String) -> bool: return defs.b_enabled[defs.building(id)] == 1
	SimHarness.check(on.call("burj") and on.call("munara") and on.call("xumdon"), "башни и Хумдон — в Сб. 1")
	SimHarness.check(on.call("devor") and on.call("tosh") and on.call("darvoza") and on.call("chep")
		and on.call("darbaza"), "стены и ворота — в Сб. 1 (автор просил стены у каждой стороны)")
	SimHarness.check(not on.call("temirchixona") and not on.call("kiyiz") and not on.call("temirchi")
		and defs.r_enabled[defs.res(&"felt")] == 0 and defs.r_enabled[defs.res(&"wool")] == 0, "кузницы и войлок — Сб. 2")
	SimHarness.check(defs.u_carry_milli[defs.unit(&"dehqon")] == 30000 and defs.u_carry_milli[defs.unit(&"malchy")] == 30000,
		"ноша работника 30 (−15% на каждые лишние 20 м пути)")
	var bd: Dictionary = defs.rules_of(&"GOROD").get("bld_dmg", {})
	SimHarness.check(is_equal_approx(float(bd.get("melee_inf", 0)), 0.5) and is_equal_approx(float(bd.get("melee_cav", 0)), 0.3)
		and is_equal_approx(float(bd.get("raider_econ", 0)), 0.4), "урон рукопашной по зданиям: ×0,5 / ×0,3 / налётчики ×0,4")
	SimHarness.check(defs.b_flags[defs.building(&"aryk")] & Defs.BF_TERRITORY != 0 and is_equal_approx(defs.b_territory_r[defs.building(&"urda")], 90.0),
		"своя земля: ставка 90 м, вдоль арыка 24 м")
	SimHarness.check(defs.b_tax_milli_min[defs.building(&"urda")] == 8000, "подать с Урды 8 золота в минуту")


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
