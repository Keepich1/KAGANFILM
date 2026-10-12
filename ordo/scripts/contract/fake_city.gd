class_name FakeCity
extends GameQuery
## Поддельный живой город (ARCHITECTURE §19.0 #10) — GameQuery для VIEW и UI до I4.
## Настоящее ядро BattleSim и настоящие таблицы, но без экономики и навигации:
##   • Коканд (игрок 0, команда 0) — урда на восточном лугу (184, 56), дома, поля, склады, стена с
##     воротами и башней; кыпчаки (игрок 1, команда 1) — лагерь среза (−60, 20), юрты, загоны, кен;
##   • стройки на разных стадиях (растут, достраиваются, BUILDING_DONE, потом снова стройка), руины;
##   • 40 одиночек-работников ходят по кругу: к дереву/залежи/полю/стройке → работа (u_act = WORK,
##     вид работы — work_aux / u_work) → назад с грузом (WORK_CARRY) → сдача (RES_DELIVERED);
##   • 3 отряда: сарбозы маршируют, жоокеры ходят у лагеря, киличбозы бьются с налётчиками-жоокерами
##     (налёт повторяется: RAID_WARNING → RAID_STARTED → бой → RAID_ENDED);
##   • деревья карты (ScatterData) и залежи, 2 стада, трава и полив, ресурсы растут;
##   • события по таймеру: BUILDING_DONE, TRAINED, RAID_WARNING, FAMINE, LOOT, TREE_FELLED, RES_DELIVERED.
##
##   var city := FakeCity.new()
##   city.setup(1)
##   city.step()          # 1/30 с; драйвер (узел) зовёт step() как SimDriver
##   city.submit(0, SimCmd.move(ids, Vector2(150, 60)))   # приказ: отряд выходит из сценария
##
## Детерминирован (своё BattleRng). Ведущий (M0); после I4 VIEW и UI переходят на GameQueryImpl.

const KOK := 0
const KIP := 1
const KOK_HQ := Vector2(184, 56)
const KIP_HQ := Vector2(-60, 20)
const ACT_WORK := 4                     # BattleSim.Act.WORK (до объявления в ядре)
const FIGHT_AT := Vector2(112, 132)
const RAID_EVERY := 3600                # тактов между набегами (2 мин)
const RAID_WARN := 900                  # предупреждение за 30 с
const HOTKEYS := ["Q", "W", "E", "R", "T", "A", "S", "D", "F", "G", "Z", "X", "C", "V"]

var sim: BattleSim
var work_aux := PackedFloat32Array()    # вид работы по юнитам ядра, −1 — нет (зеркало u_work)
var submitted: Array[PackedInt32Array] = []

var _tick := 0
var _defs: Defs
var _players := PlayerTable.new()
var _buildings := BuildingTable.new()
var _nodes := NodeTable.new()
var _herds := HerdTable.new()
var _events := SimEvents.new()
var _nav := NavStub.new()
var _rng: BattleRng
var _grass := PackedByteArray()         # 64 × 64 (16 м)
var _water := PackedByteArray()         # 128 × 128 (8 м)
var _walkers: Array[Dictionary] = []
var _sites: Array[Dictionary] = []      # {b, rate (промилле за такт × 1000), done_t}
var _scripted := {}                     # отряд ядра → true (под сценарием)
var _dead_seen := PackedByteArray()
var _drill := -1
var _patrol := -1
var _defenders := -1
var _raiders := -1
var _raid_t := 0                        # тактов до следующего набега
var _raid_wave := 0
var _raid_on := false
var _trained := 0
var _idle: Array[int] = []              # юниты ядра — «свободные работники»
var _ombor := Vector2.ZERO
var _tegirmon := Vector2.ZERO
var _ken := Vector2.ZERO


# ================================================================= сборка

func setup(p_seed := 1) -> void:
	sim = BattleSim.new(p_seed)
	_rng = BattleRng.new(p_seed * 0x9E37 + 7)
	_defs = Defs.shared()
	_nav.setup(Terrain.info(), _defs, null, null)
	_players.add(KOK, _defs.faction(&"kokand"), PlayerTable.Ctrl.HUMAN, _defs.R)
	_players.add(KIP, _defs.faction(&"kipchak"), PlayerTable.Ctrl.AI, _defs.R)
	for p in 2:
		var f := _players.faction[p]
		for r in _defs.R:
			_players.res[p * _defs.R + r] = _defs.f_start_res[f * _defs.R + r]
	_players.season[KIP] = 0
	_build_town()
	_build_camp()
	_build_nodes()
	_build_herds()
	_build_fields()
	_build_units()
	_raid_t = RAID_WARN + 300
	_update_pop()


func _build_town() -> void:
	_add(KOK, &"urda", KOK_HQ, 3)
	_add(KOK, &"uy", Vector2(206, 30), 3)
	_add(KOK, &"uy", Vector2(206, 82), 3)
	_add(KOK, &"uy", Vector2(222, 44), 3)
	_site(KOK, &"uy", Vector2(222, 70), 3, 400, 2)
	_add(KOK, &"dala", Vector2(148, 98), 0)
	_add(KOK, &"dala", Vector2(166, 98), 0)
	_tegirmon = Vector2(170, 80)
	_add(KOK, &"tegirmon", _tegirmon, 3)
	_ombor = Vector2(166, 30)
	_add(KOK, &"ombor", _ombor, 3)
	_site(KOK, &"kazarma", Vector2(214, 8), 0, 300, 3)
	_site(KOK, &"otxona", Vector2(234, 104), 2, 700, 1)
	_add(KOK, &"topxona", Vector2(240, 36), 3, BuildingTable.State.RUIN)
	# стена: звенья вдоль z, ворота посередине, бурж на южном конце, последние звенья — стройка
	var dv := _defs.building(&"devor")
	var pitch := _defs.b_link_len[dv] - _defs.b_link_overlap[dv]
	var chain := 1
	for i in 14:
		var z := 10.0 + i * pitch
		if z > 26.0 and z < 36.0:
			continue
		var st := BuildingTable.State.SITE if i >= 11 else BuildingTable.State.ACTIVE
		var b := _link(KOK, dv, Vector2(140, z - pitch * 0.5), Vector2(140, z + pitch * 0.5), chain, st)
		if st == BuildingTable.State.SITE:
			_buildings.progress[b] = (i - 11) * 300
	var g := _add(KOK, &"darvoza", Vector2(140, 31), 3)
	_buildings.rot[g] = -PI / 2.0
	_add(KOK, &"burj", Vector2(140, 4), 0)


func _build_camp() -> void:
	_add(KIP, &"ordo", KIP_HQ, 0)
	var site: Dictionary = MapValley.MAP["sites"][0]
	for it: Array in site["buildings"]:
		_add(KIP, StringName(it[0]), it[1], it[2])
	_ken = Vector2(-42, 150)
	_add(KIP, &"ken", _ken, 0)
	_site(KIP, &"jooker", Vector2(-98, 96), 1, 500, 2)
	_add(KIP, &"kurultai", Vector2(-132, 22), 0, BuildingTable.State.RUIN)
	var ch := _defs.building(&"chep")
	var pitch := _defs.b_link_len[ch] - _defs.b_link_overlap[ch]
	for i in 10:
		var x := -108.0 + i * pitch
		var st := BuildingTable.State.SITE if i >= 8 else BuildingTable.State.ACTIVE
		_link(KIP, ch, Vector2(x - pitch * 0.5, -40), Vector2(x + pitch * 0.5, -40), 2, st)
	_add(KIP, &"munara", Vector2(-114, -40), 0)


func _build_nodes() -> void:
	var kinds := PackedInt32Array()
	for k in ScatterData.KINDS.size():
		kinds.append(_defs.node(StringName("tree_" + ScatterData.KINDS[k])))
	for t: Array in ScatterData.trees():
		var nt := kinds[t[0]]
		var n := _nodes.alloc(nt)
		_fill_node(n, nt, Vector2(t[2], t[3]), ScatterData.ref(t[0], t[1]))
	for it: Array in [["stone", Vector2(-206, 12)], ["gold", Vector2(-56, 168)], ["stone", Vector2(266, -66)],
			["gold", Vector2(206, 168)], ["clay", Vector2(142, -132)]]:
		var nt := _defs.node(StringName(it[0]))
		var n := _nodes.alloc(nt)
		_fill_node(n, nt, it[1], -1)


func _build_herds() -> void:
	for it: Array in [[KIP, &"sheep", &"koroo", 24], [KIP, &"horse", &"jylky", 12]]:
		var pen := _find_building(it[0], it[2])
		var h := _herds.alloc(HerdTable.State.PEN)
		var ht := _defs.herd(it[1])
		_herds.htype[h] = ht
		_herds.owner[h] = it[0]
		_herds.pen_b[h] = _buildings.handle(pen)
		_herds.heads_milli[h] = int(it[3]) * 1000
		_herds.x[h] = _buildings.x[pen]
		_herds.z[h] = _buildings.z[pen]
		_herds.graze_r[h] = _defs.h_graze_r[ht]


## Трава (16 м): свежая, вытоптанная у загона и под постройками; полив (8 м): у реки и у полей
func _build_fields() -> void:
	_grass.resize(64 * 64)
	for j in 64:
		for i in 64:
			var p := Vector2(-512.0 + (i + 0.5) * 16.0, -512.0 + (j + 0.5) * 16.0)
			var v := 600.0 + 400.0 * BattleRng.hash01(i * 131 + j * 7)
			v *= clampf(p.distance_to(Vector2(-115, 65)) / 60.0, 0.15, 1.0)
			_grass[j * 64 + i] = int(v * 255.0 / 1000.0)
	_water.resize(128 * 128)
	for j in 128:
		for i in 128:
			var p := Vector2(-512.0 + (i + 0.5) * 8.0, -512.0 + (j + 0.5) * 8.0)
			var v := 0.0
			if Terrain.is_water(p.x, p.y):
				v = 1000.0
			elif p.distance_to(Vector2(157, 98)) < 26.0:
				v = 800.0
			_water[j * 128 + i] = int(v * 255.0 / 1000.0)


func _build_units() -> void:
	# работники: [игрок, тип, работа, вид работы, куда сдавать]
	var kok_trees := _nearest_trees(_ombor, 6)
	var kip_trees := _nearest_trees(KIP_HQ, 5)
	var kok_stone := _node_at(Vector2(266, -66))
	var kip_gold := _node_at(Vector2(-56, 168))
	var dala := _find_building(KOK, &"dala")
	var kaz := _find_building(KOK, &"kazarma")
	var jook := _find_building(KIP, &"jooker")
	var wall_site := _first_site_of(KOK, &"devor")
	var chep_site := _first_site_of(KIP, &"chep")
	for i in 6:
		_walker(KOK, "dehqon", _node_pos(kok_trees[i]), AnimSpec.WORK_CHOP, _ombor, kok_trees[i], 150)
	for i in 4:
		var spot := Vector2(_buildings.x[dala] - 5.0 + (i % 2) * 10.0, _buildings.z[dala] - 5.0 + (i / 2) * 10.0)
		_walker(KOK, "dehqon", spot, AnimSpec.WORK_DIG, _tegirmon, 0, 240)
	for i in 3:
		_walker(KOK, "dehqon", _site_spot(kaz, i), AnimSpec.WORK_BUILD, Vector2.INF, 0, 0)
	for i in 4:
		_walker(KOK, "dehqon", _node_pos(kok_stone) + Vector2(4.0 - i * 2.5, 3.0), AnimSpec.WORK_DIG, _ombor, kok_stone, 180)
	_walker(KOK, "dehqon", _site_spot(wall_site, 0), AnimSpec.WORK_BUILD, Vector2.INF, 0, 0)
	_walker(KOK, "dehqon", _site_spot(wall_site, 1), AnimSpec.WORK_BUILD, Vector2.INF, 0, 0)
	_idle.append(_walker(KOK, "dehqon", KOK_HQ + Vector2(-14, 4), -1.0, Vector2.INF, 0, 0))    # свободный
	for i in 6:
		_walker(KIP, "malchy", _node_pos(kip_gold) + Vector2(-4.0 + i * 1.8, -3.0), AnimSpec.WORK_DIG, _ken, kip_gold, 150)
	for i in 5:
		_walker(KIP, "malchy", _node_pos(kip_trees[i]), AnimSpec.WORK_CHOP, KIP_HQ + Vector2(6, 8), kip_trees[i], 150)
	for i in 3:
		_walker(KIP, "malchy", _site_spot(jook, i), AnimSpec.WORK_BUILD, Vector2.INF, 0, 0)
	for i in 3:
		# пастухи обходят короо
		_walker(KIP, "malchy", Vector2(-115, 65) + Vector2(14, 0).rotated(i * 2.1), -1.0, Vector2(-115, 65) + Vector2(-14, 4).rotated(i * 2.1), 0, 60)
	_walker(KIP, "malchy", _site_spot(chep_site, 0), AnimSpec.WORK_BUILD, Vector2.INF, 0, 0)
	_walker(KIP, "malchy", _site_spot(chep_site, 1), AnimSpec.WORK_BUILD, Vector2.INF, 0, 0)
	_idle.append(_walker(KIP, "malchy", KIP_HQ + Vector2(10, -10), -1.0, Vector2.INF, 0, 0))       # свободный
	# отряды
	_drill = sim.add_squad(KOK, "sarboz", 30, Vector2(118, 44), -PI / 2, BattleSim.Formation.LINE, 15, "yuzboshi", true, 0.3)
	_scripted[_drill] = true
	_patrol = sim.add_squad(KIP, "jooker", 30, Vector2(-14, 52), PI / 2, BattleSim.Formation.LINE, 15, "juz_bashy", true, 0.3)
	_scripted[_patrol] = true
	_spawn_defenders()
	_spawn_raiders()
	sim.order_attack(_raiders, _defenders, BattleSim.Gait.RUN)
	sim.allow_charge(_raiders, true)
	_raid_on = true
	_sync_unit_arrays()


# ================================================================= такт

func step() -> void:
	_tick += 1
	_events.tick = _tick
	_script_walkers()
	_script_squads()
	_script_raid()
	sim.step()
	_sync_unit_arrays()
	_scan_deaths()
	_grow_sites()
	if _tick % 30 == 0:
		_economy_second()
	if _tick % 450 == 0:
		_train_one()
	if _tick % 2700 == 900:
		var on := 1 - _players.famine[KIP]
		_players.famine[KIP] = on
		_events.push(SimEvents.Ev.FAMINE, KIP, on, 0, 0, KIP_HQ)
	if _tick % 7200 == 0:
		_players.season[KIP] = (_players.season[KIP] + 1) % _defs.s_ids.size()
		_events.push(SimEvents.Ev.SEASON, KIP, _players.season[KIP], 7200, 0, KIP_HQ)


## Приказ от интерфейса: форма проверяется; MOVE/ATTACK_MOVE/STOP/HOLD выполняются ядром,
## и отряд выходит из сценария. Прочее только записывается (submitted).
func submit(player: int, cmd: PackedInt32Array) -> void:
	var c := cmd.duplicate()
	c[SimCmd.H_PLAYER] = player
	c[SimCmd.H_TICK] = _tick + 1
	c[SimCmd.H_SEQ] = submitted.size()
	submitted.append(c)
	if not SimCmd.validate_shape(c):
		_events.push(SimEvents.Ev.CMD_REJECTED, player, c[SimCmd.H_OP], EconApi.Err.INVALID, c[SimCmd.H_SEQ])
		return
	var sqs := PackedInt32Array()
	for h in SimCmd.ids(c):
		var u := unit_index(h)
		if u >= 0 and sim.u_side[u] == _players.team[player] and not sqs.has(sim.u_squad[u]):
			sqs.append(sim.u_squad[u])
	for s in sqs:
		_scripted.erase(s)
		_release_walker(s)
		match c[SimCmd.H_OP]:
			SimCmd.Op.MOVE, SimCmd.Op.ATTACK_MOVE:
				var to := SimCmd.arg_pos(c, 0)
				var run := c[SimCmd.H_OP] == SimCmd.Op.ATTACK_MOVE or SimCmd.arg(c, 2) == 1
				var facing := SimCmd.arg_angle(c, 3) if c[SimCmd.H_OP] == SimCmd.Op.MOVE else NAN
				sim.order_move(s, to, BattleSim.Gait.RUN if run else BattleSim.Gait.WALK, facing)
			SimCmd.Op.STOP, SimCmd.Op.HOLD:
				sim.order_hold(s)


func _script_walkers() -> void:
	for w in _walkers:
		if not w["on"]:
			continue
		var s: int = w["s"]
		var u: int = w["u"]
		if sim.u_life[u] != BattleSim.Life.ALIVE:
			w["on"] = false
			continue
		w["t"] += 1
		var arrived := sim.sq_order[s] == BattleSim.Order.HOLD
		match w["phase"]:
			0:  # идёт к работе
				if arrived:
					w["phase"] = 1
					w["t"] = 0
					if w["aux"] >= 0.0:
						_set_work(u, w["aux"])
			1:  # работает
				if w["drop"] != Vector2.INF and w["t"] >= w["work_t"]:
					w["phase"] = 2
					_set_work(u, AnimSpec.WORK_CARRY if w["aux"] >= 0.0 else -1.0)
					_go(s, w["drop"])
					_chop(w)
			2:  # несёт
				if arrived:
					w["phase"] = 3
					w["t"] = 0
					_set_work(u, -1.0)
					if w["aux"] >= 0.0:
						var r := _defs.res(&"wood") if w["aux"] == AnimSpec.WORK_CHOP else _defs.res(&"stone")
						if w["drop"] == _tegirmon:
							r = _defs.res(&"food")
						elif w["drop"] == _ken:
							r = _defs.res(&"gold")
						var p: int = w["p"]
						_players.res[p * _defs.R + r] += 10000
						_events.push(SimEvents.Ev.RES_DELIVERED, p, r, 10000, 0, w["drop"])
			3:  # сдал — снова к работе
				if w["t"] >= 20:
					w["phase"] = 0
					_go(s, w["spot"])


func _script_squads() -> void:
	if _scripted.has(_drill) and sim.sq_order[_drill] == BattleSim.Order.HOLD and _tick % 300 == 0:
		var east := sim.squad_centroid(_drill).y < 60.0
		sim.set_formation(_drill, BattleSim.Formation.COLUMN if east else BattleSim.Formation.LINE)
		sim.order_move(_drill, Vector2(118, 76) if east else Vector2(118, 44), BattleSim.Gait.WALK, -PI / 2)
	if _scripted.has(_patrol) and sim.sq_order[_patrol] == BattleSim.Order.HOLD and _tick % 450 == 0:
		var near := sim.squad_centroid(_patrol).x < 0.0
		sim.order_move(_patrol, Vector2(14, 34) if near else Vector2(-14, 52), BattleSim.Gait.WALK, PI / 2)


func _script_raid() -> void:
	_raid_t -= 1
	if _raid_t == RAID_WARN:
		_raid_wave += 1
		_events.push(SimEvents.Ev.RAID_WARNING, KOK, RAID_WARN, KIP, _raid_wave, FIGHT_AT)
	if _raid_t <= 0:
		_raid_t = RAID_EVERY
		if sim.squad_alive(_defenders) == 0 or sim.is_fleeing(_defenders):
			_spawn_defenders()
		_spawn_raiders()
		_events.push(SimEvents.Ev.RAID_STARTED, KOK, KIP, sim.squad_alive(_raiders), _raid_wave, FIGHT_AT)
		_raid_on = true
	if _raid_on and _tick % 15 == 0:
		if sim.squad_alive(_raiders) > 0 and not sim.is_fleeing(_raiders):
			if sim.sq_order[_raiders] != BattleSim.Order.ATTACK and sim.squad_alive(_defenders) > 0:
				sim.order_attack(_raiders, _defenders, BattleSim.Gait.RUN)
				sim.allow_charge(_raiders, true)
			if sim.squad_alive(_defenders) > 0 and not sim.is_fleeing(_defenders) \
					and sim.sq_order[_defenders] != BattleSim.Order.ATTACK:
				sim.order_attack(_defenders, _raiders, BattleSim.Gait.RUN)
		else:
			_raid_on = false
			_events.push(SimEvents.Ev.RAID_ENDED, KOK, KIP, sim.squad_alive(_raiders), _raid_wave, FIGHT_AT)


func _spawn_defenders() -> void:
	_defenders = sim.add_squad(KOK, "kilichboz", 20, FIGHT_AT + Vector2(14, 0), -PI / 2, BattleSim.Formation.LINE, 10, "", true, 0.3)
	_scripted[_defenders] = true


func _spawn_raiders() -> void:
	_raiders = sim.add_squad(KIP, "jooker", 24, FIGHT_AT + Vector2(-18, 6), PI / 2, BattleSim.Formation.LINE, 12, "", true, 1.2)
	_scripted[_raiders] = true


func _scan_deaths() -> void:
	var n := sim.n
	if _dead_seen.size() < n:
		_dead_seen.resize(n)
	for u in n:
		if _dead_seen[u] == 0 and sim.u_life[u] != BattleSim.Life.ALIVE:
			_dead_seen[u] = 1
			var p := sim.u_side[u]
			var killer := _killer_of(u)
			_events.push(SimEvents.Ev.UNIT_DIED, p, unit_handle(u), killer, _defs.unit(StringName(sim.type_of(u))),
				Vector2(sim.u_x[u], sim.u_z[u]))
			if p == KOK:
				# олжо кыпчакам (ТЗ 5.4): 4 золота и 6 еды за убитого
				var g := _defs.res(&"gold")
				_players.res[KIP * _defs.R + g] += 4000
				_players.res[KIP * _defs.R + _defs.res(&"food")] += 6000
				_events.push(SimEvents.Ev.LOOT, KIP, g, 4000, unit_handle(u), Vector2(sim.u_x[u], sim.u_z[u]))


func _grow_sites() -> void:
	for sd in _sites:
		var b: int = sd["b"]
		var st := _buildings.state[b]
		if st == BuildingTable.State.SITE:
			sd["acc"] += sd["rate"]
			_buildings.progress[b] = mini(1000, _buildings.progress[b] + sd["acc"] / 1000)
			sd["acc"] %= 1000
			_buildings.hp_c[b] = maxi(100, _buildings.hp_max_c[b] * _buildings.progress[b] / 1000)
			if _buildings.progress[b] >= 1000:
				_buildings.state[b] = BuildingTable.State.ACTIVE
				_buildings.hp_c[b] = _buildings.hp_max_c[b]
				sd["done_t"] = _tick
				_events.push(SimEvents.Ev.BUILDING_DONE, _buildings.owner[b], _buildings.handle(b), _buildings.btype[b], 0,
					Vector2(_buildings.x[b], _buildings.z[b]))
				_update_pop()
		elif st == BuildingTable.State.ACTIVE and _tick - int(sd["done_t"]) > 900:
			# через 30 с — снова стройка (для кадров VIEW)
			_buildings.state[b] = BuildingTable.State.SITE
			_buildings.progress[b] = 0
			_buildings.hp_c[b] = 100
			_events.push(SimEvents.Ev.SITE_PLACED, _buildings.owner[b], _buildings.handle(b), _buildings.btype[b],
				_buildings.chain[b], Vector2(_buildings.x[b], _buildings.z[b]))
			_update_pop()


func _economy_second() -> void:
	var R := _defs.R
	for p in 2:
		# доход в минуту для балки: работники приносят, плюс ровный поток
		for r in 4:
			var inc := 6000 + 2000 * r if p == KOK else 5000 + 1500 * ((r + 1) % 4)
			_players.income[p * R + r] = inc
			_players.res[p * R + r] += inc / 60
	_update_pop()


func _train_one() -> void:
	if _trained >= 40:
		return
	_trained += 1
	var urda := _find_building(KOK, &"urda")
	var door := KOK_HQ + Vector2(-12, 0)
	var s := sim.add_squad(KOK, "dehqon", 1, door, -PI / 2, BattleSim.Formation.LINE, 1, "", false)
	sim.sq_single[s] = 1
	_scripted[s] = true
	_go(s, door + Vector2(-8.0 - (_trained % 5) * 2.0, -10.0 + (_trained / 5 % 8) * 2.5))
	_sync_unit_arrays()
	var u := sim.sq_members[s][0]
	_events.push(SimEvents.Ev.TRAINED, KOK, unit_handle(u), _buildings.handle(urda), _defs.unit(&"dehqon"), door)


# ================================================================= GameQuery

func tick() -> int:
	return _tick


func defs() -> Defs:
	return _defs


func battle() -> BattleSim:
	return sim


func players() -> PlayerTable:
	return _players


func buildings() -> BuildingTable:
	return _buildings


func nodes() -> NodeTable:
	return _nodes


func herds() -> HerdTable:
	return _herds


func events() -> SimEvents:
	return _events


func grass() -> PackedByteArray:
	return _grass


func water() -> PackedByteArray:
	return _water


func field_dims() -> Vector4i:
	return Vector4i(64, 64, 128, 128)


func unit_handle(u: int) -> int:
	return Ids.make(Ids.Kind.UNIT, u, _ugen(u))


func unit_index(h: int) -> int:
	var u := Ids.slot(h)
	if Ids.kind(h) != Ids.Kind.UNIT or u >= sim.n or _ugen(u) != Ids.gen(h):
		return -1
	return u


func pick(p: int, world: Vector2, r: float) -> int:
	# сначала свой юнит, потом чужой, потом здание под точкой, узел, стадо
	var team := _players.team[p]
	for pass_own in [true, false]:
		var best := -1
		var bd := r * r
		for u in sim.n:
			if sim.u_life[u] != BattleSim.Life.ALIVE or (sim.u_side[u] == team) != pass_own:
				continue
			var d := Vector2(sim.u_x[u], sim.u_z[u]).distance_squared_to(world)
			if d <= bd:
				bd = d
				best = u
		if best >= 0:
			return unit_handle(best)
	for b in _buildings.hw:
		if _buildings.state[b] != BuildingTable.State.FREE and _in_footprint(b, world):
			return _buildings.handle(b)
	var nb := 0
	var nd := maxf(r, 3.0) * maxf(r, 3.0)
	for n in _nodes.hw:
		if _nodes.ntype[n] >= 0 and _nodes.amount_milli[n] != 0:
			var d := Vector2(_nodes.x[n], _nodes.z[n]).distance_squared_to(world)
			if d <= nd:
				nd = d
				nb = _nodes.handle(n)
	if nb != 0:
		return nb
	for h in _herds.hw:
		if _herds.state[h] != HerdTable.State.FREE and Vector2(_herds.x[h], _herds.z[h]).distance_to(world) <= _herds.graze_r[h]:
			return _herds.handle(h)
	return 0


func units_of(p: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var team := _players.team[p]
	for u in sim.n:
		if sim.u_life[u] == BattleSim.Life.ALIVE and sim.u_side[u] == team:
			out.append(unit_handle(u))
	return out


func selection_info(hs: PackedInt32Array) -> Dictionary:
	if hs.is_empty():
		return {"kind": "none", "cards": []}
	match Ids.kind(hs[0]):
		Ids.Kind.BUILDING:
			return {"kind": "building", "cards": [], "panel": building_panel(hs[0])}
		Ids.Kind.NODE:
			var n := _nodes.slot(hs[0])
			return {"kind": "node", "cards": [], "name": tr(_defs.n_name[_nodes.ntype[n]]),
				"amount": _nodes.amount_milli[n] / 1000}
		Ids.Kind.HERD:
			var h := _herds.slot(hs[0])
			return {"kind": "herd", "cards": [], "name": tr(_defs.h_name[_herds.htype[h]]), "heads": _herds.heads(h)}
	var cards: Array = []
	var by_squad := {}
	var singles := {}
	for h in hs:
		var u := unit_index(h)
		if u < 0 or sim.u_life[u] != BattleSim.Life.ALIVE:
			continue
		var s := sim.u_squad[u]
		if sim.sq_single[s] == 1 or sim.sq_members[s].size() == 1:
			var t := sim.type_of(u)
			if not singles.has(t):
				singles[t] = [0, 0.0]
			singles[t][0] += 1
			singles[t][1] += sim.u_hp[u] / sim.t_hp[sim.u_type[u]]
		elif not by_squad.has(s):
			by_squad[s] = true
			var hp := 0.0
			for m in sim.sq_members[s]:
				if sim.u_life[m] == BattleSim.Life.ALIVE:
					hp += sim.u_hp[m] / sim.t_hp[sim.u_type[m]]
			var alive := maxi(sim.sq_alive[s], 1)
			var t := sim.type_ids[sim.sq_type[s]]
			cards.append({"type": t, "name": tr(UnitStats.get_stats(t).get("name", t)), "count": sim.sq_alive[s],
				"hp": hp / alive, "morale": sim.sq_morale[s] / 100.0, "stamina": sim.sq_stam[s] / 100.0,
				"banner": sim.sq_banner[s] >= 0, "squad": Ids.make(Ids.Kind.SQUAD, s, 1)})
	for t: String in singles:
		cards.append({"type": t, "name": tr(UnitStats.get_stats(t).get("name", t)), "count": singles[t][0],
			"hp": singles[t][1] / singles[t][0], "morale": 1.0, "stamina": 1.0, "banner": false, "squad": 0})
	return {"kind": "units", "cards": cards}


func building_panel(b_h: int) -> Dictionary:
	if not _buildings.valid(b_h):
		return {}
	var b := _buildings.slot(b_h)
	var bt := _buildings.btype[b]
	var p := _buildings.owner[b]
	var queue: Array = []
	for i in _buildings.q_n[b]:
		var u := _buildings.q[b * BuildingTable.QMAX + i]
		queue.append({"utype": u, "name": tr(_defs.u_name[u]),
			"t": float(_buildings.q_t[b]) / maxi(_defs.u_train_ticks[u], 1) if i == 0 else 0.0})
	var trains: Array = []
	for u in _defs.b_trains[bt]:
		var cost := _defs.unit_cost(u)
		var why := _why_cost(p, cost)
		if _buildings.state[b] != BuildingTable.State.ACTIVE:
			why = tr("Здание ещё строится")
		elif _players.pop_used[p] + _defs.u_pop[u] > _players.pop_cap[p]:
			why = tr("Нет мест: нужен дом")
		trains.append({"utype": u, "name": tr(_defs.u_name[u]), "cost": cost, "enabled": why == "", "why": why})
	var herd := {}
	for h in _herds.hw:
		if _herds.state[h] != HerdTable.State.FREE and _herds.pen_b[h] == b_h:
			herd = {"heads": _herds.heads(h), "cap": _defs.b_herd_cap[bt], "grass": _grass_at(Vector2(_herds.x[h], _herds.z[h]))}
	var water := -1.0
	if _defs.b_kind[bt] == Defs.BKind.FIELD:
		water = _water_at(Vector2(_buildings.x[b], _buildings.z[b]))
	return {"handle": b_h, "btype": bt, "name": tr(_defs.b_name[bt]),
		"hp": _buildings.hp_c[b] / 100, "hp_max": _buildings.hp_max_c[b] / 100,
		"state": _buildings.state[b], "progress": _buildings.progress[b] / 1000.0,
		"queue": queue, "trains": trains,
		"recipe": tr(_defs.rc_name[_buildings.recipe[b]]) if _buildings.recipe[b] >= 0 else "",
		"herd": herd, "water": water,
		"gar": {"n": _buildings.gar_n[b], "cap": _defs.b_gar_cap[bt]}}


func build_menu(p: int, tab: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var tabs: Dictionary = _defs.f_tabs[_players.faction[p]]
	var list: PackedInt32Array = tabs.get(String(tab), PackedInt32Array())
	for i in list.size():
		var b := list[i]
		var cost := _defs.building_cost(b)
		var why := tr("Ещё не готово") if _defs.b_enabled[b] == 0 else _why_cost(p, cost)
		out.append({"btype": b, "name": tr(_defs.b_name[b]), "cost": cost,
			"hotkey": HOTKEYS[i] if i < HOTKEYS.size() else "", "enabled": why == "", "why": why})
	return out


func orders_for(p: int, hs: PackedInt32Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if hs.is_empty():
		return out
	if Ids.kind(hs[0]) == Ids.Kind.BUILDING:
		if not _buildings.valid(hs[0]):
			return out
		var bt := _buildings.btype[_buildings.slot(hs[0])]
		out.append(_order(SimCmd.Op.RALLY, "Место сбора", "ПКМ", not _defs.b_trains[bt].is_empty()))
		if _defs.b_flags[bt] & Defs.BF_PACKABLE:
			out.append(_order(SimCmd.Op.PACK, "Свернуть", "K", true))
		if _defs.b_flags[bt] & Defs.BF_HQ and _defs.b_flags[bt] & Defs.BF_PACKABLE:
			out.append(_order(SimCmd.Op.PACK_ALL, "Свернуть лагерь", "Shift+K", true))
		if not _defs.b_recipes[bt].is_empty():
			out.append(_order(SimCmd.Op.SET_RECIPE, "Рецепт", "", true))
		out.append(_order(SimCmd.Op.DEMOLISH, "Снести", "Del", _defs.b_flags[bt] & Defs.BF_HQ == 0))
		return out
	var flags := 0
	var soldiers := false
	var squad := false
	for h in hs:
		var u := unit_index(h)
		if u < 0:
			continue
		var f := sim.t_flags[sim.u_type[u]]
		flags |= f
		if f & (UnitStats.WORKER | UnitStats.WAGON) == 0:
			soldiers = true
		if sim.sq_single[sim.u_squad[u]] == 0 and sim.sq_members[sim.u_squad[u]].size() > 1:
			squad = true
	out.append(_order(SimCmd.Op.MOVE, "Идти", "ПКМ", true))
	out.append(_order(SimCmd.Op.STOP, "Стой", "H", true))
	if soldiers:
		out.append(_order(SimCmd.Op.ATTACK_MOVE, "В атаку", "ПКМ", true))
		out.append(_order(SimCmd.Op.FORMATION, "Строй", "F", squad))
		out.append(_order(SimCmd.Op.STANCE, "Стойка", "", true))
		out.append(_order(SimCmd.Op.KACHYP, "Качып атуу", "G", flags & UnitStats.KACHYP != 0))
		out.append(_order(SimCmd.Op.FIRE_MODE, "Стрельба / рукопашная", "R", flags & (UnitStats.BOW | UnitStats.MUSKET) != 0))
		out.append(_order(SimCmd.Op.WAR_CRY, "Боевой клич", "V", flags & UnitStats.GENERAL != 0))
		out.append(_order(SimCmd.Op.DISBAND if squad else SimCmd.Op.FORM_SQUAD,
			"Распустить отряд" if squad else "Собрать отряд", "U", squad or flags & UnitStats.OFFICER != 0))
	if flags & UnitStats.WORKER and flags & UnitStats.WAGON == 0:
		out.append(_order(SimCmd.Op.GATHER, "Добывать", "ПКМ", true))
		out.append(_order(SimCmd.Op.BUILD, "Строить", "B", true))
		out.append(_order(SimCmd.Op.ASSIST, "Помочь строить", "ПКМ", true))
	if flags & UnitStats.WAGON:
		out.append(_order(SimCmd.Op.UNPACK, "Развернуть", "K", true))
	return out


func check_place(p: int, btype: int, center: Vector2, rot_q: int) -> int:
	return _nav.check_place(p, btype, center, rot_q)


func place_cells(p: int, btype: int, center: Vector2, rot_q: int) -> PackedByteArray:
	return _nav.place_cells(p, btype, center, rot_q)


func plan_wall(p: int, wtype: int, pts: PackedVector2Array) -> Dictionary:
	return _nav.plan_wall(p, wtype, pts)


func snap(btype: int, p: Vector2, rot_q: int) -> Vector2:
	return _nav.snap(btype, p, rot_q)


func idle_workers(p: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for u in _idle:
		if sim.u_side[u] == _players.team[p] and sim.u_life[u] == BattleSim.Life.ALIVE:
			out.append(unit_handle(u))
	return out


func raid_eta_ticks(p: int) -> int:
	return _raid_t if p == KOK and _raid_t <= RAID_WARN else -1


func minimap(p: int) -> Dictionary:
	var units := PackedVector3Array()
	for u in sim.n:
		if sim.u_life[u] == BattleSim.Life.ALIVE:
			units.append(Vector3(sim.u_x[u], sim.u_z[u], sim.u_side[u]))
	var bl := PackedVector3Array()
	for b in _buildings.hw:
		if _buildings.state[b] != BuildingTable.State.FREE:
			bl.append(Vector3(_buildings.x[b], _buildings.z[b], _buildings.team[b]))
	var nl := PackedVector3Array()
	for n in _nodes.hw:
		if _nodes.ntype[n] >= 0 and _nodes.amount_milli[n] != 0 and _defs.n_scatter_kind[_nodes.ntype[n]] < 0:
			nl.append(Vector3(_nodes.x[n], _nodes.z[n], _nodes.res[n]))
	return {"units": units, "buildings": bl, "nodes": nl}


# ================================================================= служебное

func _ugen(u: int) -> int:
	return 1


## Массивы FakeCity по юнитам ядра растут вместе с ним
func _sync_unit_arrays() -> void:
	while work_aux.size() < sim.n:
		work_aux.append(-1.0)


func _set_work(u: int, aux: float) -> void:
	_sync_unit_arrays()
	work_aux[u] = aux
	sim.u_act[u] = ACT_WORK if aux >= 0.0 else BattleSim.Act.NONE


func _go(s: int, to: Vector2) -> void:
	# одиночка сразу смотрит на цель (в ядре разворот якоря медленный — до R2)
	var c := sim.squad_anchor(s)
	if c.distance_squared_to(to) > 0.01:
		sim.sq_h[s] = atan2(to.x - c.x, to.y - c.y)
	sim.order_move(s, to, BattleSim.Gait.WALK)


## Работник-одиночка по кругу «работа ↔ сдача»; начальная фаза разная (сразу видны все виды работы)
func _walker(p: int, type_id: String, spot: Vector2, aux: float, drop: Vector2, node_h: int, work_t: int) -> int:
	var team := _players.team[p]
	var phase := 1 if drop == Vector2.INF else _walkers.size() % 3
	var start := drop if phase == 0 else spot
	start += Vector2(_rng.range_f(-1.5, 1.5), _rng.range_f(-1.5, 1.5))
	var s := sim.add_squad(team, type_id, 1, start, 0.0, BattleSim.Formation.LINE, 1, "", false)
	sim.sq_single[s] = 1
	_scripted[s] = true
	var u := sim.sq_members[s][0]
	var wt := work_t + _rng.range_i(60)
	_walkers.append({"p": p, "s": s, "u": u, "spot": spot, "aux": aux, "drop": drop, "node": node_h,
		"work_t": wt, "phase": phase, "t": _rng.range_i(maxi(wt, 1)) if phase == 1 else 0, "on": true})
	match phase:
		0:
			_go(s, spot)
		1:
			if aux >= 0.0:
				_set_work(u, aux)
		2:
			_set_work(u, AnimSpec.WORK_CARRY if aux >= 0.0 else -1.0)
			_go(s, drop)
	return u


func _release_walker(s: int) -> void:
	for w in _walkers:
		if w["s"] == s:
			w["on"] = false
			_set_work(w["u"], -1.0)


## Дерево у лесоруба: −10 за ходку; срублено → TREE_FELLED, лесоруб идёт к следующему
func _chop(w: Dictionary) -> void:
	var h: int = w["node"]
	if h == 0 or not _nodes.valid(h) or _defs.n_scatter_kind[_nodes.ntype[_nodes.slot(h)]] < 0:
		return
	var n := _nodes.slot(h)
	_nodes.amount_milli[n] = maxi(0, _nodes.amount_milli[n] - 10000)
	if _nodes.amount_milli[n] == 0:
		_events.push(SimEvents.Ev.TREE_FELLED, w["p"], h, _nodes.scatter_ref[n], _nodes.ntype[n],
			Vector2(_nodes.x[n], _nodes.z[n]))
		var next := _nearest_trees(w["drop"], 1)
		if not next.is_empty():
			w["node"] = next[0]
			w["spot"] = _node_pos(next[0])


func _add(p: int, id: StringName, center: Vector2, rot_q: int, state := BuildingTable.State.ACTIVE) -> int:
	var bt := _defs.building(id)
	var b := _buildings.alloc(state)
	_buildings.btype[b] = bt
	_buildings.owner[b] = p
	_buildings.team[b] = _players.team[p]
	_buildings.rot_q[b] = rot_q
	_buildings.flags[b] = _defs.b_flags[bt]
	_buildings.x[b] = center.x
	_buildings.z[b] = center.y
	_buildings.rot[b] = rot_q * PI * 0.5
	_buildings.hp_max_c[b] = _defs.b_hp_c[bt]
	_buildings.hp_c[b] = _defs.b_hp_c[bt] if state == BuildingTable.State.ACTIVE else _defs.b_hp_c[bt] / 5
	_buildings.progress[b] = 1000 if state == BuildingTable.State.ACTIVE else 0
	_buildings.store_mask[b] = _defs.b_accepts[bt]
	var r := NavApi.footprint(_defs, bt, center, rot_q, _nav.origin)
	_buildings.c0[b] = r.position.x
	_buildings.r0[b] = r.position.y
	_buildings.cw[b] = r.size.x
	_buildings.ch[b] = r.size.y
	if not _defs.b_trains[bt].is_empty():
		_buildings.rally_x[b] = center.x - 14.0
		_buildings.rally_z[b] = center.y
	if state != BuildingTable.State.RUIN:
		_nav.stamp_building(_buildings.handle(b), _players.team[p], center, bt, rot_q)
	if _defs.b_flags[bt] & Defs.BF_HQ:
		_players.hq_b[p] = _buildings.handle(b)
	if _defs.b_trains[bt].size() > 0 and state == BuildingTable.State.ACTIVE and _defs.b_flags[bt] & Defs.BF_HQ:
		# очередь найма у ставки: два работника
		var w := _defs.f_worker[_players.faction[p]]
		_buildings.q[b * BuildingTable.QMAX] = w
		_buildings.q[b * BuildingTable.QMAX + 1] = w
		_buildings.q_n[b] = 2
		_buildings.q_t[b] = _defs.u_train_ticks[w] / 3
	return b


func _site(p: int, id: StringName, center: Vector2, rot_q: int, progress: int, builders: int) -> int:
	var b := _add(p, id, center, rot_q, BuildingTable.State.SITE)
	_buildings.progress[b] = progress
	_buildings.workers_n[b] = builders
	_buildings.hp_c[b] = maxi(100, _buildings.hp_max_c[b] * progress / 1000)
	# скорость: промилле × 1000 за такт (≈ 1 мин на всю стройку при трёх строителях)
	_sites.append({"b": b, "rate": 180 * builders, "acc": 0, "done_t": 0})
	return b


func _link(p: int, bt: int, a: Vector2, b2: Vector2, chain: int, state: int) -> int:
	var c := (a + b2) * 0.5
	var b := _add(p, StringName(_defs.b_ids[bt]), c, 0, state)
	var seg := b2 - a
	_buildings.rot[b] = atan2(-seg.y, seg.x)
	_buildings.ax[b] = a.x
	_buildings.az[b] = a.y
	_buildings.bx[b] = b2.x
	_buildings.bz[b] = b2.y
	_buildings.chain[b] = chain
	_nav.unstamp(_buildings.handle(b))
	var r := _nav.stamp_link(_buildings.handle(b), _players.team[p], a, b2, bt)
	_buildings.c0[b] = r.position.x
	_buildings.r0[b] = r.position.y
	_buildings.cw[b] = r.size.x
	_buildings.ch[b] = r.size.y
	if state == BuildingTable.State.SITE:
		_sites.append({"b": b, "rate": 900, "acc": 0, "done_t": 0})
	return b


func _fill_node(n: int, nt: int, pos: Vector2, scatter_ref: int) -> void:
	_nodes.res[n] = _defs.n_res[nt]
	_nodes.amount_milli[n] = _defs.n_amount_milli[nt]
	_nodes.workers_max[n] = _defs.n_workers_max[nt]
	_nodes.scatter_ref[n] = scatter_ref
	_nodes.cell[n] = _nav.cell_of(pos)
	_nodes.x[n] = pos.x
	_nodes.z[n] = pos.y


func _find_building(p: int, id: StringName) -> int:
	var bt := _defs.building(id)
	for b in _buildings.hw:
		if _buildings.btype[b] == bt and _buildings.owner[b] == p:
			return b
	return -1


func _first_site_of(p: int, id: StringName) -> int:
	var bt := _defs.building(id)
	for b in _buildings.hw:
		if _buildings.btype[b] == bt and _buildings.owner[b] == p and _buildings.state[b] == BuildingTable.State.SITE:
			return b
	return _find_building(p, id)


## Место строителя у стройки: по периметру следа
func _site_spot(b: int, i: int) -> Vector2:
	var c := Vector2(_buildings.x[b], _buildings.z[b])
	var half := _defs.b_size[_buildings.btype[b]] * 0.5 + Vector2(1.2, 1.2)
	var spots := [Vector2(-half.x, 0), Vector2(half.x, 0), Vector2(0, -half.y), Vector2(0, half.y)]
	return c + spots[i % 4]


func _nearest_trees(p: Vector2, k: int) -> PackedInt32Array:
	var cand: Array = []
	for n in _nodes.hw:
		if _nodes.ntype[n] >= 0 and _nodes.amount_milli[n] > 0 and _defs.n_scatter_kind[_nodes.ntype[n]] >= 0:
			cand.append([Vector2(_nodes.x[n], _nodes.z[n]).distance_squared_to(p), n])
	cand.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var out := PackedInt32Array()
	for i in mini(k, cand.size()):
		out.append(_nodes.handle(cand[i][1]))
	while out.size() < k and not out.is_empty():
		out.append(out[0])
	return out


func _node_at(p: Vector2) -> int:
	for n in _nodes.hw:
		if _nodes.ntype[n] >= 0 and Vector2(_nodes.x[n], _nodes.z[n]).distance_squared_to(p) < 1.0:
			return _nodes.handle(n)
	return 0


func _node_pos(h: int) -> Vector2:
	var n := _nodes.slot(h)
	return Vector2(_nodes.x[n], _nodes.z[n])


func _killer_of(u: int) -> int:
	return 0


func _in_footprint(b: int, p: Vector2) -> bool:
	var c := Vector2(_buildings.x[b], _buildings.z[b])
	var size := _defs.b_size[_buildings.btype[b]]
	var d := (p - c).rotated(_buildings.rot[b])
	return absf(d.x) <= size.x * 0.5 and absf(d.y) <= size.y * 0.5


func _update_pop() -> void:
	for p in 2:
		var cap := 0
		for b in _buildings.hw:
			if _buildings.owner[b] == p and _buildings.state[b] == BuildingTable.State.ACTIVE:
				cap += _defs.b_pop_cap[_buildings.btype[b]]
		_players.pop_cap[p] = mini(cap, 500)
		var used := 0
		for u in sim.n:
			if sim.u_side[u] == _players.team[p] and sim.u_life[u] == BattleSim.Life.ALIVE:
				used += 1
		_players.pop_used[p] = used


func _grass_at(p: Vector2) -> float:
	var i := clampi(int((p.x + 512.0) / 16.0), 0, 63)
	var j := clampi(int((p.y + 512.0) / 16.0), 0, 63)
	return _grass[j * 64 + i] / 255.0


func _water_at(p: Vector2) -> float:
	var i := clampi(int((p.x + 512.0) / 8.0), 0, 127)
	var j := clampi(int((p.y + 512.0) / 8.0), 0, 127)
	return _water[j * 128 + i] / 255.0


func _why_cost(p: int, cost: PackedInt32Array) -> String:
	var miss := PackedStringArray()
	for r in cost.size():
		var lack := cost[r] - _players.res[p * _defs.R + r]
		if lack > 0:
			miss.append("%d %s" % [ceili(lack / 1000.0), tr(_defs.r_name[r]).to_lower()])
	return "" if miss.is_empty() else tr("Нужно: %s") % ", ".join(miss)


func _order(op: int, label: String, key: String, enabled: bool) -> Dictionary:
	return {"op": op, "label": tr(label), "key": key, "enabled": enabled}
