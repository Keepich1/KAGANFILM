class_name SimCmd
## Поток приказов (ARCHITECTURE §8, CONTRACT §10): единственный вход в симуляцию «Города».
## Интерфейс и ИИ делают приказы этими конструкторами; GameDriver.issue → CommandQueue
## (ставит игрока, такт = текущий + input_delay, порядковый номер) → Orders.apply.
##
## Раскладка: PackedInt32Array [op, player, tick, seq, n, id_0 … id_{n−1}, args…]
##   ids  — описатели (Ids) СВОИХ сущностей игрока: Orders проверяет, что каждый жив и принадлежит ему;
##   args — числа; описатели в args (цель атаки, источник добычи, здание) — чужие можно.
## Позиции — целые сантиметры (cm), углы — целые миллирадианы (mrad), NO_ANGLE = «не задан» (NAN).
## Номера определений (юнит, здание, рецепт, ресурс) — индексы Defs; повтор хранит Defs.hash().
##
## Аргументы по приказам (ids: число описателей; дальше args по порядку):
##   MOVE          ids ≥1   x, z, run, facing, queue
##   MOVE_LINE     ids ≥1   ax, az, bx, bz, run
##   ATTACK        ids ≥1   target_h, run              (юнит, отряд или здание)
##   ATTACK_MOVE   ids ≥1   x, z
##   STOP          ids ≥1   —
##   HOLD          ids ≥1   facing
##   STANCE        ids ≥1   stance (BattleSim.Stance 0..3)
##   GAIT          ids ≥1   gait (BattleSim.Gait 0..2)
##   FORMATION     ids ≥1   formation (BattleSim.Formation 0..3)
##   FIRE_MODE     ids ≥1   mode (FIRE_AUTO 0 / FIRE_MELEE 1)
##   KACHYP        ids ≥1   on
##   WAR_CRY       ids =1   — (ids[0] — полководец)
##   FORM_SQUAD    ids ≥1   — (ids[0] — офицер, ids[1..] — бойцы-одиночки)
##   DISBAND       ids =1   — (отряд)
##   GARRISON      ids ≥1   building_h
##   UNGARRISON    ids =1   — (ids[0] — башня/здание)
##   GATHER        ids ≥1   source_h                   (узел, поле, стадо — чужой можно)
##   BUILD         ids ≥0   btype, x, z, rot_q         (ids — работники; пусто — ближайший свободный)
##   BUILD_WALL    ids ≥0   wtype, npts, x0, z0, … x_{npts−1}, z_{npts−1}   (npts 2..MAX_WALL_PTS)
##   ASSIST        ids ≥1   building_h
##   DEMOLISH      ids =1   —
##   TRAIN         ids =1   utype, count
##   CANCEL_TRAIN  ids =1   index
##   RALLY         ids =1   x, z, target_h
##   SET_RECIPE    ids =1   recipe
##   TRADE         ids =1   give, take, amount_milli
##   SET_DAM       ids =1   open
##   PACK          ids =1   —
##   PACK_ALL      ids =1   — (ставка)
##   UNPACK        ids ≥1   x, z (ids — арбы)
##   HERD_MOVE     ids =1   x, z (ids[0] — стадо)
##   SPAWN         ids =0   utype, count, x, z, heading, officer_utype (−1 нет) — только ИИ при rules.ai_free_waves
## Логические аргументы — 0/1.
##
## Только ведущий меняет этот файл.

enum Op { NONE, MOVE, MOVE_LINE, ATTACK, ATTACK_MOVE, STOP, HOLD, STANCE, GAIT, FORMATION, FIRE_MODE, KACHYP,
	WAR_CRY, FORM_SQUAD, DISBAND, GARRISON, UNGARRISON,
	GATHER, BUILD, BUILD_WALL, ASSIST, DEMOLISH, TRAIN, CANCEL_TRAIN, RALLY, SET_RECIPE, TRADE, SET_DAM,
	PACK, PACK_ALL, UNPACK, HERD_MOVE, SPAWN }

const H_OP := 0; const H_PLAYER := 1; const H_TICK := 2; const H_SEQ := 3; const H_N := 4; const H_IDS := 5
const NO_ANGLE := 0x7FFFFFFF

## Режим огня (FIRE_MODE): стрелять, когда можно / только рукопашная
const FIRE_AUTO := 0
const FIRE_MELEE := 1
## Пределы формы приказа
const MAX_IDS := 1000
const MAX_WALL_PTS := 64

## Число описателей [min, max] (−1 — без предела) и число аргументов (−1 — переменное) по Op
const _IDS_MIN := [0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0]
const _IDS_MAX := [0, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 1, -1, 1, -1, 1, -1, -1, -1, -1, 1, 1, 1, 1, 1, 1, 1, 1, 1, -1, 1, 0]
const _ARGS := [0, 5, 5, 2, 2, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 1, 0, 1, 4, -1, 1, 0, 2, 1, 3, 1, 3, 1, 0, 0, 2, 2, 6]

const _MAGIC := 0x4F52444F   # "ORDO"
const _VERSION := 1


# ================================================================= числа

static func cm(v: float) -> int:
	return roundi(v * 100.0)


static func mrad(a: float) -> int:
	if is_nan(a) or is_inf(a):
		return NO_ANGLE
	return roundi(a * 1000.0)


## Описатели приказа (копия)
static func ids(cmd: PackedInt32Array) -> PackedInt32Array:
	return cmd.slice(H_IDS, H_IDS + cmd[H_N])


## i-й аргумент после описателей
static func arg(cmd: PackedInt32Array, i: int) -> int:
	return cmd[H_IDS + cmd[H_N] + i]


## Позиция из аргументов i, i+1 (см → м)
static func arg_pos(cmd: PackedInt32Array, i: int) -> Vector2:
	return Vector2(arg(cmd, i), arg(cmd, i + 1)) * 0.01


## Угол из аргумента i (мрад → рад; NO_ANGLE → NAN)
static func arg_angle(cmd: PackedInt32Array, i: int) -> float:
	var v := arg(cmd, i)
	return NAN if v == NO_ANGLE else v * 0.001


## Точки стены BUILD_WALL (м)
static func wall_points(cmd: PackedInt32Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var k := arg(cmd, 1)
	for j in k:
		out.append(arg_pos(cmd, 2 + j * 2))
	return out


## Имя приказа для журналов и тестов
static func name_of(op: int) -> String:
	var keys := Op.keys()
	return keys[op] if op >= 0 and op < keys.size() else "?"


# ================================================================= конструкторы (игрок, такт и номер ставит CommandQueue)

static func move(p_ids: PackedInt32Array, to: Vector2, run := false, facing := NAN, queue := false) -> PackedInt32Array:
	return _make(Op.MOVE, p_ids, [cm(to.x), cm(to.y), _b(run), mrad(facing), _b(queue)])


static func move_line(p_ids: PackedInt32Array, a: Vector2, b: Vector2, run := false) -> PackedInt32Array:
	return _make(Op.MOVE_LINE, p_ids, [cm(a.x), cm(a.y), cm(b.x), cm(b.y), _b(run)])


static func attack(p_ids: PackedInt32Array, target_h: int, run := true) -> PackedInt32Array:
	return _make(Op.ATTACK, p_ids, [target_h, _b(run)])


static func attack_move(p_ids: PackedInt32Array, to: Vector2) -> PackedInt32Array:
	return _make(Op.ATTACK_MOVE, p_ids, [cm(to.x), cm(to.y)])


static func stop(p_ids: PackedInt32Array) -> PackedInt32Array:
	return _make(Op.STOP, p_ids, [])


static func hold(p_ids: PackedInt32Array, facing := NAN) -> PackedInt32Array:
	return _make(Op.HOLD, p_ids, [mrad(facing)])


static func stance(p_ids: PackedInt32Array, p_stance: int) -> PackedInt32Array:
	return _make(Op.STANCE, p_ids, [p_stance])


static func gait(p_ids: PackedInt32Array, p_gait: int) -> PackedInt32Array:
	return _make(Op.GAIT, p_ids, [p_gait])


static func formation(p_ids: PackedInt32Array, f: int) -> PackedInt32Array:
	return _make(Op.FORMATION, p_ids, [f])


static func fire_mode(p_ids: PackedInt32Array, mode: int) -> PackedInt32Array:
	return _make(Op.FIRE_MODE, p_ids, [mode])


static func kachyp(p_ids: PackedInt32Array, on: bool) -> PackedInt32Array:
	return _make(Op.KACHYP, p_ids, [_b(on)])


static func war_cry(general_h: int) -> PackedInt32Array:
	return _make(Op.WAR_CRY, PackedInt32Array([general_h]), [])


static func form_squad(officer_h: int, p_ids: PackedInt32Array) -> PackedInt32Array:
	var all := PackedInt32Array([officer_h])
	all.append_array(p_ids)
	return _make(Op.FORM_SQUAD, all, [])


static func disband(squad_h: int) -> PackedInt32Array:
	return _make(Op.DISBAND, PackedInt32Array([squad_h]), [])


static func garrison(p_ids: PackedInt32Array, building_h: int) -> PackedInt32Array:
	return _make(Op.GARRISON, p_ids, [building_h])


static func ungarrison(building_h: int) -> PackedInt32Array:
	return _make(Op.UNGARRISON, PackedInt32Array([building_h]), [])


static func gather(p_ids: PackedInt32Array, source_h: int) -> PackedInt32Array:
	return _make(Op.GATHER, p_ids, [source_h])


static func build(p_ids: PackedInt32Array, btype: int, at: Vector2, rot_q: int) -> PackedInt32Array:
	return _make(Op.BUILD, p_ids, [btype, cm(at.x), cm(at.y), rot_q])


static func build_wall(p_ids: PackedInt32Array, wtype: int, pts: PackedVector2Array) -> PackedInt32Array:
	var a := [wtype, pts.size()]
	for p in pts:
		a.append(cm(p.x))
		a.append(cm(p.y))
	return _make(Op.BUILD_WALL, p_ids, a)


static func assist(p_ids: PackedInt32Array, building_h: int) -> PackedInt32Array:
	return _make(Op.ASSIST, p_ids, [building_h])


static func demolish(building_h: int) -> PackedInt32Array:
	return _make(Op.DEMOLISH, PackedInt32Array([building_h]), [])


static func train(building_h: int, utype: int, count := 1) -> PackedInt32Array:
	return _make(Op.TRAIN, PackedInt32Array([building_h]), [utype, count])


static func cancel_train(building_h: int, index: int) -> PackedInt32Array:
	return _make(Op.CANCEL_TRAIN, PackedInt32Array([building_h]), [index])


static func rally(building_h: int, at: Vector2, target_h := 0) -> PackedInt32Array:
	return _make(Op.RALLY, PackedInt32Array([building_h]), [cm(at.x), cm(at.y), target_h])


static func set_recipe(building_h: int, recipe: int) -> PackedInt32Array:
	return _make(Op.SET_RECIPE, PackedInt32Array([building_h]), [recipe])


static func trade(building_h: int, give: int, take: int, amount_milli: int) -> PackedInt32Array:
	return _make(Op.TRADE, PackedInt32Array([building_h]), [give, take, amount_milli])


static func set_dam(building_h: int, open: bool) -> PackedInt32Array:
	return _make(Op.SET_DAM, PackedInt32Array([building_h]), [_b(open)])


static func pack(building_h: int) -> PackedInt32Array:
	return _make(Op.PACK, PackedInt32Array([building_h]), [])


static func pack_all(hq_h: int) -> PackedInt32Array:
	return _make(Op.PACK_ALL, PackedInt32Array([hq_h]), [])


static func unpack(arba_ids: PackedInt32Array, center: Vector2) -> PackedInt32Array:
	return _make(Op.UNPACK, arba_ids, [cm(center.x), cm(center.y)])


static func herd_move(herd_h: int, to: Vector2) -> PackedInt32Array:
	return _make(Op.HERD_MOVE, PackedInt32Array([herd_h]), [cm(to.x), cm(to.y)])


static func spawn(utype: int, count: int, at: Vector2, heading: float, officer_utype := -1) -> PackedInt32Array:
	return _make(Op.SPAWN, PackedInt32Array(), [utype, count, cm(at.x), cm(at.y), mrad(heading), officer_utype])


# ================================================================= проверка формы

## Форма приказа: длина, op, число описателей и аргументов, описатели не 0 и известного вида,
## логические 0/1, перечисления в пределах, номера определений ≥ 0. Правила игры — в Orders.
static func validate_shape(cmd: PackedInt32Array) -> bool:
	if cmd.size() < H_IDS:
		return false
	var op := cmd[H_OP]
	if op <= Op.NONE or op > Op.SPAWN:
		return false
	var n := cmd[H_N]
	if n < 0 or n > MAX_IDS or n < _IDS_MIN[op] or (_IDS_MAX[op] >= 0 and n > _IDS_MAX[op]):
		return false
	if cmd.size() < H_IDS + n:
		return false
	for i in n:
		var h := cmd[H_IDS + i]
		var k := Ids.kind(h)
		if h == Ids.NULL or k < Ids.Kind.UNIT or k > Ids.Kind.HERD:
			return false
	var na := cmd.size() - H_IDS - n
	var want: int = _ARGS[op]
	if want < 0:
		# BUILD_WALL: wtype, npts, затем npts пар
		if na < 2:
			return false
		var k := arg(cmd, 1)
		if k < 2 or k > MAX_WALL_PTS or na != 2 + k * 2 or arg(cmd, 0) < 0:
			return false
		return true
	if na != want:
		return false
	match op:
		Op.MOVE:
			return _is_bool(arg(cmd, 2)) and _is_bool(arg(cmd, 4))
		Op.MOVE_LINE:
			return _is_bool(arg(cmd, 4))
		Op.ATTACK:
			return arg(cmd, 0) != Ids.NULL and _is_bool(arg(cmd, 1))
		Op.STANCE:
			return arg(cmd, 0) >= 0 and arg(cmd, 0) <= 3
		Op.GAIT:
			return arg(cmd, 0) >= 0 and arg(cmd, 0) <= 2
		Op.FORMATION:
			return arg(cmd, 0) >= 0 and arg(cmd, 0) <= 3
		Op.FIRE_MODE:
			return arg(cmd, 0) == FIRE_AUTO or arg(cmd, 0) == FIRE_MELEE
		Op.KACHYP, Op.SET_DAM:
			return _is_bool(arg(cmd, 0))
		Op.GARRISON, Op.GATHER, Op.ASSIST:
			return arg(cmd, 0) != Ids.NULL
		Op.BUILD:
			return arg(cmd, 0) >= 0 and arg(cmd, 3) >= 0 and arg(cmd, 3) <= 3
		Op.TRAIN:
			return arg(cmd, 0) >= 0 and arg(cmd, 1) >= 1
		Op.CANCEL_TRAIN, Op.SET_RECIPE:
			return arg(cmd, 0) >= 0
		Op.TRADE:
			return arg(cmd, 0) >= 0 and arg(cmd, 1) >= 0 and arg(cmd, 0) != arg(cmd, 1) and arg(cmd, 2) > 0
		Op.SPAWN:
			return arg(cmd, 0) >= 0 and arg(cmd, 1) >= 1 and arg(cmd, 5) >= -1
	return true


# ================================================================= запись (повтор, сеть)

## Список приказов → байты: [MAGIC, VERSION, count, (len, cmd…)…] в int32 little-endian
static func encode(cmds: Array[PackedInt32Array]) -> PackedByteArray:
	var flat := PackedInt32Array([_MAGIC, _VERSION, cmds.size()])
	for c in cmds:
		flat.append(c.size())
		flat.append_array(c)
	return flat.to_byte_array()


## Байты → список приказов; испорченные данные → пустой список
static func decode(bytes: PackedByteArray) -> Array[PackedInt32Array]:
	var out: Array[PackedInt32Array] = []
	if bytes.size() < 12 or bytes.size() % 4 != 0:
		return out
	var flat := bytes.to_int32_array()
	if flat[0] != _MAGIC or flat[1] != _VERSION or flat[2] < 0:
		return out
	var i := 3
	for k in flat[2]:
		if i >= flat.size():
			out.clear()
			return out
		var ln := flat[i]
		if ln < 0 or i + 1 + ln > flat.size():
			out.clear()
			return out
		out.append(flat.slice(i + 1, i + 1 + ln))
		i += 1 + ln
	if i != flat.size():
		out.clear()
	return out


# ================================================================= служебное

static func _make(op: int, p_ids: PackedInt32Array, args: Array) -> PackedInt32Array:
	var c := PackedInt32Array([op, 0, 0, 0, p_ids.size()])
	c.append_array(p_ids)
	for a: int in args:
		c.append(a)
	return c


static func _b(v: bool) -> int:
	return 1 if v else 0


static func _is_bool(v: int) -> bool:
	return v == 0 or v == 1
