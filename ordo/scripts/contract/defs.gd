class_name Defs
extends RefCounted
## Определения «Города» (ARCHITECTURE §6.4): все файлы scripts/data/* (константы GDScript),
## собранные один раз в плотные таблицы. Индексы записей = порядок в файлах данных; приказы
## (SimCmd) и повторы хранят индексы, повтор — ещё и hash().
##
##   var defs := Defs.shared()                                  # общий экземпляр
##   var d := Defs.build({"buildings": {"uy": {"hp": 900}}})    # тесты: правка чисел
##   defs.building(&"uy"), defs.res(&"wood"), defs.b_cost[b * defs.R + r]
##
## Правки (overrides): {раздел: {id: {ключ: значение}}} — словари сливаются вглубь, прочее заменяется;
## разделы: resources, units, buildings, nodes, herds, recipes, factions, modifiers, seasons,
## rules ({"GOROD": {...}}), ai ({"RAID": {...}}), maps ({"valley": {...}}).
##
## Единицы скомпилированных таблиц: ресурсы — милли (1 = 1000), HP — санти (× 100), время — такты
## (1/30 с), «в минуту»/«в секунду» — милли за минуту/секунду, raid_value — десятые доли.
## Боевые числа юнитов — в UnitStats/BattleSim.type_index, не здесь.
##
## Только ведущий меняет этот файл (значения — в scripts/data/*).

enum BKind { BUILDING, FIELD, WALL, GATE, TOWER, LINK, DAM }
enum Render { SCENE, MULTIMESH }
const BF_HQ := 1; const BF_DROP := 2; const BF_HOUSE := 4; const BF_PACKABLE := 8; const BF_PEN := 16
const BF_TERRITORY := 32; const BF_BLOCKS := 64; const BF_ROUND := 128; const BF_NETWORK := 256
const BF_MARKET := 512; const BF_WALKABLE := 1024

const TICKS_PER_S := 30
const CELL := 4.0                               # = NavApi.CELL (клетка навигации, м)

const KIND_NAMES := {"building": BKind.BUILDING, "field": BKind.FIELD, "wall": BKind.WALL, "gate": BKind.GATE,
	"tower": BKind.TOWER, "link": BKind.LINK, "dam": BKind.DAM}
const FLAG_NAMES := {"hq": BF_HQ, "drop": BF_DROP, "house": BF_HOUSE, "packable": BF_PACKABLE, "pen": BF_PEN,
	"territory": BF_TERRITORY, "blocks": BF_BLOCKS, "round": BF_ROUND, "network": BF_NETWORK,
	"market": BF_MARKET, "walkable": BF_WALKABLE}
const STAT_NAMES := ["atk", "speed", "stam_regen", "morale_regen", "range", "gather", "build", "upkeep"]
const DEFAULT_PLACE := {"max_slope": 1.2, "water": false, "territory": true}

## Допустимые ключи (замороженная схема; лишний ключ — ошибка validate)
const _KEYS := {
	"resources": ["name", "faction", "icon", "backing", "enabled"],
	"units": ["cost", "time", "pop", "upkeep", "carry", "gather", "build_rate", "trained_at", "squad_max", "enabled"],
	"buildings": ["name", "faction", "tab", "kind", "size", "hp", "cost", "build_time", "flags", "accepts", "place",
		"territory_r", "work", "yield", "link", "garrison", "herd", "aura", "network", "recipes", "passive",
		"unpack_s", "model", "render", "raid_value", "pop_cap", "enabled"],
	"nodes": ["name", "res", "amount", "workers_max", "work_aux", "blocks_cells", "scatter", "model", "enabled"],
	"herds": ["name", "yield", "growth", "graze", "graze_r", "backing", "capturable", "flock_max", "model", "enabled"],
	"recipes": ["name", "in", "out", "time", "workers", "enabled"],
	"factions": ["name", "hq", "worker", "officer", "start_res", "start_units", "traits", "ui_res", "tabs",
		"bounty", "color"],
	"modifiers": ["stat", "mul", "add", "when", "enabled"],
	"seasons": ["name", "duration_s", "mods"],
}
const _RULE_KEYS := ["econ", "pop_max", "upkeep", "famine", "loot", "trade", "tax", "herd_theft", "pack_r",
	"worker_resume_r", "corpse_s", "path_per_tick", "path_cells_per_tick", "breach_ratio", "input_delay",
	"ai_free_waves", "raids", "victory"]

static var _shared: Defs

# ---------------------------------------------------------------- ресурсы
var R := 0
var res_ids := PackedStringArray()
var r_name := PackedStringArray()
var r_faction := PackedStringArray()           # "" — общий
var r_icon := PackedStringArray()
var r_backing := PackedInt32Array()            # стадо (h_*), −1
var r_enabled := PackedInt32Array()

# ---------------------------------------------------------------- юниты (экономика; бой — UnitStats/BattleSim.type_index)
var unit_ids := PackedStringArray()
var u_cost := PackedInt32Array()               # [u * R + r] milli
var u_gather := PackedInt32Array()             # [u * R + r] milli per second
var u_train_ticks := PackedInt32Array()
var u_pop := PackedInt32Array()
var u_upkeep_milli_min := PackedInt32Array()   # еды в минуту, милли
var u_carry_milli := PackedInt32Array()
var u_build_rate := PackedInt32Array()         # милли (1000 — один работник)
var u_flags := PackedInt32Array()              # UnitStats.* (WORKER, RAIDER, MOUNTED…)
var u_squad_max := PackedInt32Array()
var u_trained_at: Array[PackedInt32Array] = []   # здания (b_*)
var u_name := PackedStringArray()
var u_faction := PackedStringArray()
var u_enabled := PackedInt32Array()

# ---------------------------------------------------------------- постройки
var b_ids := PackedStringArray()
var b_kind := PackedInt32Array()               # BKind
var b_flags := PackedInt32Array()              # BF_*
var b_hp_c := PackedInt32Array()
var b_build_ticks := PackedInt32Array()
var b_pop_cap := PackedInt32Array()
var b_accepts := PackedInt32Array()            # маска ресурсов (1 << r)
var b_cells_w := PackedInt32Array()            # клеток навигации при rot_q = 0
var b_cells_h := PackedInt32Array()
var b_work_slots := PackedInt32Array()
var b_gar_cap := PackedInt32Array()
var b_raid_value := PackedInt32Array()         # десятые доли
var b_herd := PackedInt32Array()               # тип стада загона (h_*), −1
var b_herd_start := PackedInt32Array()         # голов при постройке
var b_herd_cap := PackedInt32Array()
var b_render := PackedInt32Array()             # Render
var b_size := PackedVector2Array()
var b_cost := PackedInt32Array()               # [b * R + r]
var b_link_len := PackedFloat32Array()
var b_link_overlap := PackedFloat32Array()
var b_platform_h := PackedFloat32Array()
var b_range_mult := PackedFloat32Array()
var b_absorb := PackedFloat32Array()
var b_stone_range := PackedFloat32Array()
var b_territory_r := PackedFloat32Array()
var b_unpack_ticks := PackedInt32Array()
var b_enabled := PackedInt32Array()
var b_trains: Array[PackedInt32Array] = []     # юниты (из UnitEcon.trained_at)
var b_recipes: Array[PackedInt32Array] = []
var b_place: Array[Dictionary] = []            # DEFAULT_PLACE + place; near.nodes → PackedInt32Array
var b_work: Array[Dictionary] = []             # {res, slots, per_worker_min_milli, carry_to: PackedInt32Array} или {}
var b_yield: Array[Array] = []                 # [{field, below, mul, enabled}]
var b_aura: Array[Dictionary] = []             # {gather_mult, r, res_mask} или {}
var b_passive: Array[Array] = []               # [{kind, res (индекс), …}]
var b_network: Array[Dictionary] = []
var b_model := PackedStringArray()
var b_name := PackedStringArray()
var b_tab := PackedStringArray()
var b_faction := PackedStringArray()

# ---------------------------------------------------------------- узлы ресурсов
var n_ids := PackedStringArray()
var n_name := PackedStringArray()
var n_res := PackedInt32Array()
var n_amount_milli := PackedInt32Array()       # −1 — бесконечно
var n_workers_max := PackedInt32Array()
var n_work_aux := PackedFloat32Array()         # AnimSpec.WORK_*
var n_blocks_cells := PackedInt32Array()
var n_scatter_kind := PackedInt32Array()       # ScatterData.KINDS, −1
var n_model := PackedStringArray()
var n_enabled := PackedInt32Array()

# ---------------------------------------------------------------- стада
var h_ids := PackedStringArray()
var h_name := PackedStringArray()
var h_yield := PackedInt32Array()              # [h * R + r] милли за голову в минуту
var h_growth_milli := PackedInt32Array()       # прирост: милли-голов на голову в минуту
var h_graze := PackedInt32Array()              # травы (0..1000) на голову в минуту
var h_graze_r := PackedFloat32Array()
var h_backing := PackedInt32Array()            # ресурс, −1
var h_capturable := PackedInt32Array()
var h_flock_max := PackedInt32Array()
var h_model := PackedStringArray()
var h_enabled := PackedInt32Array()

# ---------------------------------------------------------------- рецепты
var rc_ids := PackedStringArray()
var rc_name := PackedStringArray()
var rc_in := PackedInt32Array()                # [rc * R + r] milli за партию
var rc_out := PackedInt32Array()
var rc_ticks := PackedInt32Array()
var rc_workers := PackedInt32Array()
var rc_enabled := PackedInt32Array()

# ---------------------------------------------------------------- стороны
var f_ids := PackedStringArray()
var f_name := PackedStringArray()
var f_hq := PackedInt32Array()                 # постройка
var f_worker := PackedInt32Array()             # юнит
var f_officer := PackedInt32Array()
var f_start_res := PackedInt32Array()          # [f * R + r] milli
var f_start_units: Array[PackedInt32Array] = []  # пары [юнит, число, …]
var f_traits := PackedInt32Array()             # маска 1 << индекс FactionDefs.TRAITS
var f_ui_res: Array[PackedInt32Array] = []
var f_tabs: Array[Dictionary] = []             # {вкладка: PackedInt32Array построек}
var f_bounty_kill := PackedInt32Array()        # [f * R + r] milli
var f_bounty_worker := PackedInt32Array()
var f_bounty_hq := PackedInt32Array()
var f_bounty_share_pm := PackedInt32Array()    # доля цены разорённого здания, промилле
var f_color := PackedColorArray()

# ---------------------------------------------------------------- множители и сезоны
var m_ids := PackedStringArray()
var m_stat := PackedInt32Array()               # PlayerTable.Stat
var m_mul := PackedFloat32Array()
var m_add := PackedFloat32Array()
var m_when := PackedStringArray()
var m_enabled := PackedInt32Array()
var s_ids := PackedStringArray()
var s_name := PackedStringArray()
var s_ticks := PackedInt32Array()
var s_mods: Array[PackedInt32Array] = []

# ---------------------------------------------------------------- правила, ИИ, карты
var rules := {}                                # {"GOROD": {...}, "BATTLE": {...}} (+ *_ticks)
var ai := {}                                   # {"RAID": {...}, "GARRISON": {...}} (+ *_ticks)
var maps := {}                                 # {"valley": MapValley.MAP}

var _src := {}
var _index := {}                               # раздел → {id: индекс}
var _hash := 0


static func shared() -> Defs:
	if _shared == null:
		_shared = build()
	return _shared


static func build(overrides := {}) -> Defs:
	var d := Defs.new()
	d._compile(_source(overrides))
	return d


## Устойчивая сумма скомпилированных чисел (без подписей): повтор сверяет её с записанной
func hash() -> int:
	return _hash


func res(id: StringName) -> int: return _find("resources", id)
func unit(id: StringName) -> int: return _find("units", id)
func building(id: StringName) -> int: return _find("buildings", id)
func node(id: StringName) -> int: return _find("nodes", id)
func herd(id: StringName) -> int: return _find("herds", id)
func recipe(id: StringName) -> int: return _find("recipes", id)
func faction(id: StringName) -> int: return _find("factions", id)
func modifier(id: StringName) -> int: return _find("modifiers", id)
func season(id: StringName) -> int: return _find("seasons", id)


## {ресурс: число} → милли по индексам ресурсов, длина R
func cost_of(d: Dictionary) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(R)
	for k: Variant in d:
		var r := res(StringName(str(k)))
		if r >= 0:
			out[r] = roundi(float(d[k]) * 1000.0)
	return out


## Цена постройки b (милли, длина R)
func building_cost(b: int) -> PackedInt32Array:
	return b_cost.slice(b * R, b * R + R)


## Цена юнита u (милли, длина R)
func unit_cost(u: int) -> PackedInt32Array:
	return u_cost.slice(u * R, u * R + R)


## Клетки следа постройки с учётом поворота: Vector2i(ширина по x, глубина по z)
func cells_of(b: int, rot_q: int) -> Vector2i:
	if rot_q & 1:
		return Vector2i(b_cells_h[b], b_cells_w[b])
	return Vector2i(b_cells_w[b], b_cells_h[b])


func has_trait(f: int, trait_id: String) -> bool:
	var k := FactionDefs.TRAITS.find(trait_id)
	return k >= 0 and f_traits[f] & (1 << k) != 0


## Скомпилированные правила режима ("GOROD" | "BATTLE")
func rules_of(id: StringName) -> Dictionary:
	return rules.get(String(id), {})


# ================================================================= проверка (tests/test_defs.gd)

## Перекрёстные ссылки, обязательные ключи, размеры, цены ≥ 0, лишние ключи схемы
func validate() -> PackedStringArray:
	var e := PackedStringArray()
	for sec: String in _KEYS:
		var allowed: Array = _KEYS[sec]
		var table: Dictionary = _src.get(sec, {})
		for id: String in table:
			for k: String in table[id]:
				if not k in allowed:
					e.append("%s.%s: неизвестный ключ «%s»" % [sec, id, k])
	var res_t: Dictionary = _src["resources"]
	for id: String in res_t:
		var d: Dictionary = res_t[id]
		if d.has("backing") and herd(d["backing"]) < 0:
			e.append("resources.%s: нет стада %s" % [id, d["backing"]])
		if d.get("faction", "") != "" and faction(d["faction"]) < 0:
			e.append("resources.%s: нет стороны %s" % [id, d["faction"]])
	# юниты: те же, что в UnitStats
	var units_t: Dictionary = _src["units"]
	for id: String in UnitStats.UNITS:
		if not units_t.has(id):
			e.append("units: нет записи UnitEcon для %s" % id)
	for id: String in units_t:
		var d: Dictionary = units_t[id]
		if UnitStats.get_stats(id).is_empty():
			e.append("units.%s: нет в UnitStats" % id)
		if not d.has("cost") or not d.has("time"):
			e.append("units.%s: нужны cost и time" % id)
		_check_res_dict(e, "units.%s.cost" % id, d.get("cost", {}), true)
		_check_res_dict(e, "units.%s.gather" % id, d.get("gather", {}), true)
		for b: String in d.get("trained_at", []):
			if building(b) < 0:
				e.append("units.%s: нет постройки %s" % [id, b])
		if float(d.get("time", 0)) < 0.0:
			e.append("units.%s: время < 0" % id)
	# постройки
	var b_t: Dictionary = _src["buildings"]
	for id: String in b_t:
		var d: Dictionary = b_t[id]
		var w := "buildings.%s" % id
		for k: String in ["name", "faction", "kind", "size"]:
			if not d.has(k):
				e.append("%s: нет обязательного ключа %s" % [w, k])
		if d.has("kind") and not KIND_NAMES.has(d["kind"]):
			e.append("%s: неизвестный вид %s" % [w, d["kind"]])
		if d.has("faction") and faction(d["faction"]) < 0:
			e.append("%s: нет стороны %s" % [w, d["faction"]])
		var size: Vector2 = d.get("size", Vector2.ZERO)
		if size.x <= 0.0 or size.y <= 0.0:
			e.append("%s: размер должен быть > 0" % w)
		if int(d.get("hp", 1)) <= 0:
			e.append("%s: hp должно быть > 0" % w)
		_check_res_dict(e, w + ".cost", d.get("cost", {}), true)
		for f: String in d.get("flags", []):
			if not FLAG_NAMES.has(f):
				e.append("%s: неизвестный флаг %s" % [w, f])
		for r: String in d.get("accepts", []):
			if res(r) < 0:
				e.append("%s: accepts — нет ресурса %s" % [w, r])
		if "drop" in d.get("flags", []) and d.get("accepts", []).is_empty():
			e.append("%s: склад без accepts" % w)
		for rc: String in d.get("recipes", []):
			if recipe(rc) < 0:
				e.append("%s: нет рецепта %s" % [w, rc])
		var kind: String = d.get("kind", "")
		if kind in ["wall", "link"]:
			var ln: Dictionary = d.get("link", {})
			if float(ln.get("len", 0.0)) <= float(ln.get("overlap", 0.0)) or float(ln.get("overlap", 0.0)) < 0.0:
				e.append("%s: link.len должно быть > overlap ≥ 0" % w)
		if kind == "tower" and not d.has("garrison"):
			e.append("%s: башне нужен garrison" % w)
		if d.has("work"):
			var wk: Dictionary = d["work"]
			if res(wk.get("res", "")) < 0:
				e.append("%s: work.res — нет ресурса" % w)
			for c: String in wk.get("carry_to", []):
				if building(c) < 0:
					e.append("%s: work.carry_to — нет постройки %s" % [w, c])
		if d.has("herd") and herd(d["herd"].get("htype", "")) < 0:
			e.append("%s: herd.htype — нет стада" % w)
		var near: Dictionary = d.get("place", {}).get("near", {})
		for n: String in near.get("nodes", []):
			if node(n) < 0:
				e.append("%s: place.near — нет узла %s" % [w, n])
		for r: String in d.get("aura", {}).get("res", []):
			if res(r) < 0:
				e.append("%s: aura.res — нет ресурса %s" % [w, r])
		for p: Dictionary in d.get("passive", []):
			if p.has("res") and res(p["res"]) < 0:
				e.append("%s: passive — нет ресурса %s" % [w, p["res"]])
		if "packable" in d.get("flags", []) and int(d.get("unpack_s", 0)) <= 0:
			e.append("%s: сворачиваемой постройке нужен unpack_s" % w)
		if "territory" in d.get("flags", []) and float(d.get("territory_r", 0.0)) <= 0.0:
			e.append("%s: territory без territory_r" % w)
	# узлы, стада, рецепты
	var n_t: Dictionary = _src["nodes"]
	for id: String in n_t:
		var d: Dictionary = n_t[id]
		if res(d.get("res", "")) < 0:
			e.append("nodes.%s: нет ресурса" % id)
		if int(d.get("amount", 0)) == 0 or int(d.get("amount", 0)) < -1:
			e.append("nodes.%s: amount — > 0 или −1" % id)
		var sk: String = d.get("scatter", "")
		if sk != "" and not sk in ScatterData.KINDS:
			e.append("nodes.%s: нет вида дерева %s" % [id, sk])
	var h_t: Dictionary = _src["herds"]
	for id: String in h_t:
		var d: Dictionary = h_t[id]
		_check_res_dict(e, "herds.%s.yield" % id, d.get("yield", {}), true)
		if d.has("backing") and res(d["backing"]) < 0:
			e.append("herds.%s: backing — нет ресурса" % id)
	var rc_t: Dictionary = _src["recipes"]
	for id: String in rc_t:
		var d: Dictionary = rc_t[id]
		_check_res_dict(e, "recipes.%s.in" % id, d.get("in", {}), false)
		_check_res_dict(e, "recipes.%s.out" % id, d.get("out", {}), false)
		if float(d.get("time", 0)) <= 0.0:
			e.append("recipes.%s: time должно быть > 0" % id)
	# стороны
	var f_t: Dictionary = _src["factions"]
	for id: String in f_t:
		var d: Dictionary = f_t[id]
		var w := "factions.%s" % id
		var hq := building(d.get("hq", ""))
		if hq < 0 or b_flags[hq] & BF_HQ == 0 or b_faction[hq] != id:
			e.append("%s: hq — нужна ставка этой стороны" % w)
		var wu := unit(d.get("worker", ""))
		if wu < 0 or u_flags[wu] & UnitStats.WORKER == 0:
			e.append("%s: worker — нужен работник" % w)
		var ou := unit(d.get("officer", ""))
		if ou < 0 or u_flags[ou] & UnitStats.OFFICER == 0:
			e.append("%s: officer — нужен офицер" % w)
		_check_res_dict(e, w + ".start_res", d.get("start_res", {}), true)
		for u: String in d.get("start_units", {}):
			if unit(u) < 0:
				e.append("%s: start_units — нет юнита %s" % [w, u])
		for t: String in d.get("traits", []):
			if not t in FactionDefs.TRAITS:
				e.append("%s: неизвестная черта %s" % [w, t])
		for r: String in d.get("ui_res", []):
			if res(r) < 0:
				e.append("%s: ui_res — нет ресурса %s" % [w, r])
		var tabs: Dictionary = d.get("tabs", {})
		for tab: String in tabs:
			for b: String in tabs[tab]:
				var bi := building(b)
				if bi < 0:
					e.append("%s: tabs.%s — нет постройки %s" % [w, tab, b])
				elif b_faction[bi] != id or b_tab[bi] != tab:
					e.append("%s: tabs.%s — %s другой стороны или вкладки" % [w, tab, b])
		var bounty: Dictionary = d.get("bounty", {})
		for k: String in ["kill", "worker", "hq"]:
			_check_res_dict(e, "%s.bounty.%s" % [w, k], bounty.get(k, {}), true)
	# множители, сезоны
	var m_t: Dictionary = _src["modifiers"]
	for id: String in m_t:
		if not m_t[id].get("stat", "") in STAT_NAMES:
			e.append("modifiers.%s: неизвестный stat" % id)
	var s_t: Dictionary = _src["seasons"]
	for id: String in s_t:
		for m: String in s_t[id].get("mods", []):
			if modifier(m) < 0:
				e.append("seasons.%s: нет множителя %s" % [id, m])
		if int(s_t[id].get("duration_s", 0)) <= 0:
			e.append("seasons.%s: duration_s должно быть > 0" % id)
	# правила
	for rid: String in ["GOROD", "BATTLE"]:
		var rd: Dictionary = _src["rules"].get(rid, {})
		for k: String in _RULE_KEYS:
			if not rd.has(k):
				e.append("rules.%s: нет ключа %s" % [rid, k])
		for m: String in rd.get("famine", {}).get("mods", []):
			if modifier(m) < 0:
				e.append("rules.%s.famine: нет множителя %s" % [rid, m])
	# карты
	for mid: String in _src["maps"]:
		var md: Dictionary = _src["maps"][mid]
		for site: Dictionary in md.get("sites", []):
			if faction(site.get("faction", "")) < 0:
				e.append("maps.%s: место для неизвестной стороны" % mid)
			for it: Array in site.get("buildings", []):
				if building(it[0]) < 0:
					e.append("maps.%s: нет постройки %s" % [mid, it[0]])
		for it: Array in md.get("deposits", []):
			if node(it[0]) < 0:
				e.append("maps.%s: нет узла %s" % [mid, it[0]])
	return e


func _check_res_dict(e: PackedStringArray, where: String, d: Dictionary, allow_zero: bool) -> void:
	for k: Variant in d:
		if res(StringName(str(k))) < 0:
			e.append("%s: нет ресурса %s" % [where, k])
		elif float(d[k]) < 0.0 or (not allow_zero and float(d[k]) == 0.0):
			e.append("%s: %s — число должно быть %s" % [where, k, "≥ 0" if allow_zero else "> 0"])


# ================================================================= сборка

static func _source(overrides: Dictionary) -> Dictionary:
	var s := {
		"resources": ResourceDefs.RESOURCES.duplicate(true),
		"units": UnitEcon.UNITS.duplicate(true),
		"buildings": BuildingDefs.BUILDINGS.duplicate(true),
		"nodes": NodeDefs.NODES.duplicate(true),
		"herds": HerdDefs.HERDS.duplicate(true),
		"recipes": RecipeDefs.RECIPES.duplicate(true),
		"factions": FactionDefs.FACTIONS.duplicate(true),
		"modifiers": ModifierDefs.MODIFIERS.duplicate(true),
		"seasons": ModifierDefs.SEASONS.duplicate(true),
		"rules": {"GOROD": GameRules.GOROD.duplicate(true), "BATTLE": GameRules.BATTLE.duplicate(true)},
		"ai": {"RAID": AiDefs.RAID.duplicate(true), "GARRISON": AiDefs.GARRISON.duplicate(true)},
		"maps": {"valley": MapValley.MAP.duplicate(true)},
	}
	_merge(s, overrides)
	return s


static func _merge(dst: Dictionary, src: Dictionary) -> void:
	for k: Variant in src:
		if dst.has(k) and dst[k] is Dictionary and src[k] is Dictionary:
			_merge(dst[k], src[k])
		else:
			dst[k] = src[k].duplicate(true) if (src[k] is Dictionary or src[k] is Array) else src[k]


func _find(sec: String, id: StringName) -> int:
	return int(_index.get(sec, {}).get(String(id), -1))


func _ids_of(sec: String, table: Dictionary) -> PackedStringArray:
	var ids := PackedStringArray()
	var idx := {}
	for id: Variant in table:
		idx[String(id)] = ids.size()
		ids.append(String(id))
	_index[sec] = idx
	return ids


static func _on(d: Dictionary) -> int:
	return 1 if bool(d.get("enabled", true)) else 0


static func _ticks(seconds: float) -> int:
	return roundi(seconds * TICKS_PER_S)


func _milli_row(out: PackedInt32Array, d: Dictionary) -> void:
	out.append_array(cost_of(d))


func _mask(list: Array, sec: String) -> int:
	var m := 0
	for id: Variant in list:
		var i := _find(sec, StringName(str(id)))
		if i >= 0:
			m |= 1 << i
	return m


func _indices(list: Array, sec: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	for id: Variant in list:
		out.append(_find(sec, StringName(str(id))))
	return out


func _compile(s: Dictionary) -> void:
	_src = s
	# индексы всех разделов — до ссылок между ними
	res_ids = _ids_of("resources", s["resources"])
	unit_ids = _ids_of("units", s["units"])
	b_ids = _ids_of("buildings", s["buildings"])
	n_ids = _ids_of("nodes", s["nodes"])
	h_ids = _ids_of("herds", s["herds"])
	rc_ids = _ids_of("recipes", s["recipes"])
	f_ids = _ids_of("factions", s["factions"])
	m_ids = _ids_of("modifiers", s["modifiers"])
	s_ids = _ids_of("seasons", s["seasons"])
	R = res_ids.size()
	# ресурсы
	for id in res_ids:
		var d: Dictionary = s["resources"][id]
		r_name.append(String(d.get("name", id)))
		r_faction.append(String(d.get("faction", "")))
		r_icon.append(String(d.get("icon", id)))
		r_backing.append(herd(d.get("backing", "")))
		r_enabled.append(_on(d))
	# юниты
	for id in unit_ids:
		var d: Dictionary = s["units"][id]
		var st := UnitStats.get_stats(id)
		_milli_row(u_cost, d.get("cost", {}))
		_milli_row(u_gather, d.get("gather", {}))
		u_train_ticks.append(_ticks(float(d.get("time", 0))))
		u_pop.append(int(d.get("pop", 1)))
		u_upkeep_milli_min.append(roundi(float(d.get("upkeep", 0.0)) * 1000.0))
		u_carry_milli.append(roundi(float(d.get("carry", 0)) * 1000.0))
		u_build_rate.append(roundi(float(d.get("build_rate", 0.0)) * 1000.0))
		u_flags.append(int(st.get("flags", 0)))
		u_squad_max.append(int(d.get("squad_max", 0)))
		u_trained_at.append(_indices(d.get("trained_at", []), "buildings"))
		u_name.append(String(st.get("name", id)))
		u_faction.append(String(st.get("faction", "")))
		u_enabled.append(_on(d))
	# постройки
	for id in b_ids:
		var d: Dictionary = s["buildings"][id]
		var size: Vector2 = d.get("size", Vector2(CELL, CELL))
		var flags := 0
		for f: Variant in d.get("flags", []):
			flags |= int(FLAG_NAMES.get(String(f), 0))
		var gar: Dictionary = d.get("garrison", {})
		var ln: Dictionary = d.get("link", {})
		var hd: Dictionary = d.get("herd", {})
		b_kind.append(int(KIND_NAMES.get(String(d.get("kind", "building")), BKind.BUILDING)))
		b_flags.append(flags)
		b_hp_c.append(roundi(float(d.get("hp", 1)) * 100.0))
		b_build_ticks.append(_ticks(float(d.get("build_time", 0))))
		b_pop_cap.append(int(d.get("pop_cap", 0)))
		b_accepts.append(_mask(d.get("accepts", []), "resources"))
		b_cells_w.append(maxi(1, ceili(size.x / CELL - 0.1)))
		b_cells_h.append(maxi(1, ceili(size.y / CELL - 0.1)))
		b_work_slots.append(int(d.get("work", {}).get("slots", 0)))
		b_gar_cap.append(int(gar.get("cap", 0)))
		b_raid_value.append(roundi(float(d.get("raid_value", 0.0)) * 10.0))
		b_herd.append(herd(hd.get("htype", "")) if not hd.is_empty() else -1)
		b_herd_start.append(int(hd.get("start", 0)))
		b_herd_cap.append(int(hd.get("cap", 0)))
		b_render.append(Render.MULTIMESH if d.get("render", "scene") == "multimesh" else Render.SCENE)
		b_size.append(size)
		_milli_row(b_cost, d.get("cost", {}))
		b_link_len.append(float(ln.get("len", 0.0)))
		b_link_overlap.append(float(ln.get("overlap", 0.0)))
		b_platform_h.append(float(gar.get("platform_h", 0.0)))
		b_range_mult.append(float(gar.get("range_mult", 1.0)))
		b_absorb.append(float(gar.get("absorb", 0.0)))
		b_stone_range.append(float(gar.get("stone_range", 0.0)))
		b_territory_r.append(float(d.get("territory_r", 0.0)))
		b_unpack_ticks.append(_ticks(float(d.get("unpack_s", 0))))
		b_enabled.append(_on(d))
		b_trains.append(PackedInt32Array())
		b_recipes.append(_indices(d.get("recipes", []), "recipes"))
		var place := DEFAULT_PLACE.duplicate(true)
		place.merge(d.get("place", {}).duplicate(true), true)
		if place.has("near"):
			place["near"]["nodes"] = _indices(place["near"].get("nodes", []), "nodes")
		b_place.append(place)
		var work := {}
		if d.has("work"):
			var wk: Dictionary = d["work"]
			work = {"res": res(wk.get("res", "")), "slots": int(wk.get("slots", 0)),
				"per_worker_min_milli": roundi(float(wk.get("per_worker_min", 0)) * 1000.0),
				"carry_to": _indices(wk.get("carry_to", []), "buildings")}
		b_work.append(work)
		var yl: Array = []
		for y: Dictionary in d.get("yield", []):
			yl.append({"field": String(y.get("field", "")), "below": int(y.get("below", 0)),
				"mul": float(y.get("mul", 1.0)), "enabled": bool(y.get("enabled", true))})
		b_yield.append(yl)
		var aura := {}
		if d.has("aura"):
			var au: Dictionary = d["aura"]
			aura = {"gather_mult": float(au.get("gather_mult", 1.0)), "r": float(au.get("r", 0.0)),
				"res_mask": _mask(au.get("res", []), "resources")}
		b_aura.append(aura)
		var passive: Array = []
		for p: Dictionary in d.get("passive", []):
			var pc := p.duplicate(true)
			if pc.has("res"):
				pc["res"] = res(pc["res"])
			passive.append(pc)
		b_passive.append(passive)
		b_network.append(d.get("network", {}).duplicate(true))
		b_model.append(String(d.get("model", id)))
		b_name.append(String(d.get("name", id)))
		b_tab.append(String(d.get("tab", "")))
		b_faction.append(String(d.get("faction", "")))
	# кто где нанимается — обратная таблица UnitEcon.trained_at
	for u in unit_ids.size():
		for b in u_trained_at[u]:
			if b >= 0:
				b_trains[b].append(u)
	# узлы
	for id in n_ids:
		var d: Dictionary = s["nodes"][id]
		var amount := int(d.get("amount", -1))
		n_name.append(String(d.get("name", id)))
		n_res.append(res(d.get("res", "")))
		n_amount_milli.append(-1 if amount < 0 else amount * 1000)
		n_workers_max.append(int(d.get("workers_max", 1)))
		n_work_aux.append(float(d.get("work_aux", 0.0)))
		n_blocks_cells.append(int(d.get("blocks_cells", 0)))
		n_scatter_kind.append(ScatterData.KINDS.find(String(d.get("scatter", ""))))
		n_model.append(String(d.get("model", "")))
		n_enabled.append(_on(d))
	# стада
	for id in h_ids:
		var d: Dictionary = s["herds"][id]
		h_name.append(String(d.get("name", id)))
		_milli_row(h_yield, d.get("yield", {}))
		h_growth_milli.append(roundi(float(d.get("growth", 0.0)) * 1000.0))
		h_graze.append(roundi(float(d.get("graze", 0.0))))
		h_graze_r.append(float(d.get("graze_r", 20.0)))
		h_backing.append(res(d.get("backing", "")))
		h_capturable.append(1 if bool(d.get("capturable", false)) else 0)
		h_flock_max.append(int(d.get("flock_max", 80)))
		h_model.append(String(d.get("model", id)))
		h_enabled.append(_on(d))
	# рецепты
	for id in rc_ids:
		var d: Dictionary = s["recipes"][id]
		rc_name.append(String(d.get("name", id)))
		_milli_row(rc_in, d.get("in", {}))
		_milli_row(rc_out, d.get("out", {}))
		rc_ticks.append(_ticks(float(d.get("time", 0))))
		rc_workers.append(int(d.get("workers", 1)))
		rc_enabled.append(_on(d))
	# стороны
	for id in f_ids:
		var d: Dictionary = s["factions"][id]
		var bounty: Dictionary = d.get("bounty", {})
		f_name.append(String(d.get("name", id)))
		f_hq.append(building(d.get("hq", "")))
		f_worker.append(unit(d.get("worker", "")))
		f_officer.append(unit(d.get("officer", "")))
		_milli_row(f_start_res, d.get("start_res", {}))
		var su := PackedInt32Array()
		var su_d: Dictionary = d.get("start_units", {})
		for u: Variant in su_d:
			su.append(unit(StringName(str(u))))
			su.append(int(su_d[u]))
		f_start_units.append(su)
		var tr := 0
		for t: Variant in d.get("traits", []):
			var k := FactionDefs.TRAITS.find(String(t))
			if k >= 0:
				tr |= 1 << k
		f_traits.append(tr)
		f_ui_res.append(_indices(d.get("ui_res", []), "resources"))
		var tabs := {}
		var tabs_d: Dictionary = d.get("tabs", {})
		for tab: Variant in tabs_d:
			tabs[String(tab)] = _indices(tabs_d[tab], "buildings")
		f_tabs.append(tabs)
		_milli_row(f_bounty_kill, bounty.get("kill", {}))
		_milli_row(f_bounty_worker, bounty.get("worker", {}))
		_milli_row(f_bounty_hq, bounty.get("hq", {}))
		f_bounty_share_pm.append(roundi(float(bounty.get("building_share", 0.0)) * 1000.0))
		f_color.append(d.get("color", Color.WHITE))
	# множители и сезоны
	for id in m_ids:
		var d: Dictionary = s["modifiers"][id]
		m_stat.append(STAT_NAMES.find(String(d.get("stat", ""))))
		m_mul.append(float(d.get("mul", 1.0)))
		m_add.append(float(d.get("add", 0.0)))
		m_when.append(String(d.get("when", "always")))
		m_enabled.append(_on(d))
	for id in s_ids:
		var d: Dictionary = s["seasons"][id]
		s_name.append(String(d.get("name", id)))
		s_ticks.append(_ticks(float(d.get("duration_s", 0))))
		s_mods.append(_indices(d.get("mods", []), "modifiers"))
	# правила, ИИ, карты: секунды → такты
	rules = {}
	for rid: Variant in s["rules"]:
		var rd: Dictionary = s["rules"][rid].duplicate(true)
		_add_ticks(rd)
		if rd.has("famine"):
			rd["famine"]["mod_ids"] = _indices(rd["famine"].get("mods", []), "modifiers")
		rules[String(rid)] = rd
	ai = s["ai"].duplicate(true)
	_add_ticks(ai)
	maps = s["maps"].duplicate(true)
	_hash = _compute_hash()


## Ключи *_s (секунды) получают пару *_ticks; списки секунд — списки тактов
static func _add_ticks(d: Dictionary) -> void:
	for k: Variant in d.keys():
		var v: Variant = d[k]
		if v is Dictionary:
			_add_ticks(v)
		elif String(k).ends_with("_s") and (v is int or v is float):
			var key := String(k).trim_suffix("_s") + "_ticks"
			d[key] = -1 if float(v) < 0.0 else _ticks(float(v))
		elif String(k).ends_with("_s") and v is Array:
			var key := String(k).trim_suffix("_s") + "_ticks"
			var out: Array = []
			for x: Variant in v:
				out.append(_ticks(float(x)))
			d[key] = out


func _compute_hash() -> int:
	var data := [R, r_backing, r_enabled,
		u_cost, u_gather, u_train_ticks, u_pop, u_upkeep_milli_min, u_carry_milli, u_build_rate, u_flags,
		u_squad_max, u_trained_at, u_enabled,
		b_kind, b_flags, b_hp_c, b_build_ticks, b_pop_cap, b_accepts, b_cells_w, b_cells_h, b_work_slots,
		b_gar_cap, b_raid_value, b_herd, b_herd_start, b_herd_cap, b_size, b_cost, b_link_len,
		b_link_overlap, b_platform_h, b_range_mult, b_absorb, b_stone_range, b_territory_r, b_unpack_ticks,
		b_enabled, b_trains, b_recipes, b_place, b_work, b_yield, b_aura, b_passive, b_network,
		n_res, n_amount_milli, n_workers_max, n_work_aux, n_blocks_cells, n_scatter_kind, n_enabled,
		h_yield, h_growth_milli, h_graze, h_graze_r, h_backing, h_capturable, h_enabled,
		rc_in, rc_out, rc_ticks, rc_workers, rc_enabled,
		f_hq, f_worker, f_officer, f_start_res, f_start_units, f_traits, f_bounty_kill, f_bounty_worker,
		f_bounty_hq, f_bounty_share_pm,
		m_stat, m_mul, m_add, m_when, m_enabled, s_ticks, s_mods,
		rules, ai, maps]
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(var_to_bytes(data))
	return ctx.finish().decode_u32(0) & 0x7FFFFFFF
