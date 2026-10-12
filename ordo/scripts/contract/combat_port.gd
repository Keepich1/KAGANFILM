class_name CombatPort
extends RefCounted
## Порт тел (ARCHITECTURE §7.1): экономика, приказы и ИИ двигают тела только через него.
## CORE делает CombatPortBattle extends CombatPort над BattleSim (единственный, кто зовёт
## изменяющие методы ядра); до I1/I2 пакеты работают на CombatPortStub.
## Этот класс — договор: методы пишут push_error и возвращают значения по умолчанию.
##
## Описатели на входе и на выходе (Ids): юниты — UNIT, отряды — SQUAD, здания — BUILDING.
## Описатель юнита в приказе означает его отряд; одиночки, которым приказали вместе,
## идут одним путём. Одиночка (нанятый по одному) — отряд из одного.
##
## Только ведущий меняет этот файл.

## cfg: {teams, homes: PackedVector2Array, corpse_s, bounds_origin: Vector2, bounds_size: Vector2}
func setup(defs: Defs, nav: NavApi, cfg: Dictionary) -> void:
	_todo("setup")


func battle() -> BattleSim:                                       # read-only kernel arrays (views); stub returns null
	_todo("battle")
	return null


# ---------------------------------------------------------------- жизнь

func spawn(owner: int, team: int, type_id: StringName, pos: Vector2, heading: float) -> int:   # unit handle (a single)
	_todo("spawn")
	return 0


func spawn_squad(owner: int, team: int, type_id: StringName, count: int, pos: Vector2, heading: float,
		officer_type: StringName = &"", formation := 0, files := 0) -> int:                     # squad handle
	_todo("spawn_squad")
	return 0


func remove(u_h: int) -> void:                 # leaves the world without dying (packed into an arba, consumed)
	_todo("remove")


func kill(u_h: int) -> void:                   # tests and SPAWN/cheat tooling only
	_todo("kill")


func valid(h: int) -> bool:
	_todo("valid")
	return false


# ---------------------------------------------------------------- чтение

func alive(u_h: int) -> bool:
	_todo("alive")
	return false


func pos(h: int) -> Vector2:                   # unit position or squad centroid
	_todo("pos")
	return Vector2.ZERO


func owner(h: int) -> int:
	_todo("owner")
	return -1


func team(h: int) -> int:
	_todo("team")
	return -1


func type_id(u_h: int) -> StringName:
	_todo("type_id")
	return &""


func squad_of(u_h: int) -> int:
	_todo("squad_of")
	return 0


func members(s_h: int) -> PackedInt32Array:
	_todo("members")
	return PackedInt32Array()


func is_idle(h: int) -> bool:
	_todo("is_idle")
	return false


func hurt_within(u_h: int, ticks: int) -> bool:
	_todo("hurt_within")
	return false


## Юниты команды team (enemies — чужих команд) в радиусе r; flags_any — UnitStats.* (0 — любые).
## Заполняет out (очищает) описателями юнитов, возвращает их число.
func units_near(team: int, pos: Vector2, r: float, enemies: bool, flags_any: int, out: PackedInt32Array) -> int:
	_todo("units_near")
	return 0


func enemy_near(team: int, pos: Vector2, r: float) -> bool:
	_todo("enemy_near")
	return false


# ---------------------------------------------------------------- приказы

func move(hs: PackedInt32Array, to: Vector2, run := false, facing := NAN, line_to := Vector2(NAN, NAN)) -> void:
	_todo("move")


func attack(hs: PackedInt32Array, target_h: int, run := true) -> void:      # unit, squad or building handle
	_todo("attack")


func attack_move(hs: PackedInt32Array, to: Vector2) -> void:
	_todo("attack_move")


func stop(hs: PackedInt32Array) -> void:
	_todo("stop")


func hold(hs: PackedInt32Array, facing := NAN) -> void:
	_todo("hold")


func set_stance(hs: PackedInt32Array, stance: int) -> void:
	_todo("set_stance")


func set_gait(hs: PackedInt32Array, gait: int) -> void:
	_todo("set_gait")


func set_formation(hs: PackedInt32Array, formation: int) -> void:
	_todo("set_formation")


func set_fire_mode(hs: PackedInt32Array, mode: int) -> void:                # stage 2
	_todo("set_fire_mode")


func set_kachyp(hs: PackedInt32Array, on: bool) -> void:                     # stage 2
	_todo("set_kachyp")


func war_cry(general_h: int) -> bool:
	_todo("war_cry")
	return false


func form_squad(officer_h: int, candidates: PackedInt32Array, formation := 0) -> int:   # squad handle or 0
	_todo("form_squad")
	return 0


func disband(s_h: int) -> PackedInt32Array:                                  # unit handles, now singles
	_todo("disband")
	return PackedInt32Array()


func set_work(u_h: int, aux: float) -> void:                                 # AnimSpec WORK aux; < 0 stops
	_todo("set_work")


func face(u_h: int, heading: float) -> void:
	_todo("face")


func garrison(hs: PackedInt32Array, b_h: int) -> void:                       # stage 2
	_todo("garrison")


func ungarrison(b_h: int, at: Vector2) -> void:                              # stage 2
	_todo("ungarrison")


# ---------------------------------------------------------------- зеркало мира (ECON → ядро)

func structure_set(b_h: int, team: int, center: Vector2, half: Vector2, rot: float, flags: int,
		top := 0.0, gar_cap := 0) -> void:
	_todo("structure_set")


func structure_clear(b_h: int) -> void:
	_todo("structure_clear")


func set_owner_mods(owner: int, mods: PackedFloat32Array) -> void:           # BattleSim.MOD_*
	_todo("set_owner_mods")


func upgrade_type(owner: int, type_id: StringName, overrides: Dictionary) -> void:   # stage 3
	_todo("upgrade_type")


func on_nav_changed() -> void:
	_todo("on_nav_changed")


# ---------------------------------------------------------------- такт (только GameSim)

func deliver_paths() -> void:
	_todo("deliver_paths")


func step() -> void:
	_todo("step")


func take_deaths() -> PackedInt32Array:            # pairs [unit_h, killer_h]
	_todo("take_deaths")
	return PackedInt32Array()


func take_structure_hits() -> PackedInt32Array:    # triples [building_h, dmg_centi, attacker_h]
	_todo("take_structure_hits")
	return PackedInt32Array()


func take_arrivals() -> PackedInt32Array:          # squad handles whose MOVE completed
	_todo("take_arrivals")
	return PackedInt32Array()


func checksum() -> int:
	_todo("checksum")
	return 0


func save_into(d: Dictionary) -> void:
	_todo("save_into")


func load_from(d: Dictionary) -> void:
	_todo("load_from")


func _todo(what: String) -> void:
	push_error("CombatPort.%s: не реализовано (%s)" % [what, get_script().resource_path])
