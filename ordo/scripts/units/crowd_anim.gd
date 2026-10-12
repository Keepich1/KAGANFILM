class_name CrowdAnim
extends RefCounted
## Подсказки для симуляции и эффектов: как вести фазу анимации толпы и когда случаются события.
## Договор данных экземпляра — AnimSpec (x состояние, y фаза, z доп., w вариант).
##
##   # цикл шага: фаза растёт на пройденный путь / длину цикла — ноги не скользят
##   u.phase = CrowdAnim.advance(u.phase, moved_m, CrowdAnim.stride_for(unit_id, state))
##   var st := CrowdAnim.gait("rider", speed_mps)          # WALK / TROT / GALLOP по скорости
##   # разовое состояние: фаза 0→1 за CrowdAnim.duration(...)
##   u.phase = minf(u.phase + delta / CrowdAnim.duration("human", AnimSpec.Human.SHOOT), 1.0)
##
## Доп. значение z:
##   WALK/RUN/TROT/GALLOP/CHARGE — 1.0 (зарезервировано: сила хода);
##   DYING/DEAD — сторона падения: 0 на левый бок, 1 на правый;
##   WORK (человек) — 0 рубит, 0.25 копает, 0.5 строит (на колене), 0.75 несёт мешок
##   (при «несёт» ноги идут шагом: фазу вести как у WALK по пройденному пути, на месте — не менять).
## Вариант w (0..1, постоянный для юнита): оттенок одежды, рост ±4 %, шапка, масть коня, шерсть овцы.
## Ветер знамён — глобальный ordo_wind (x, z — куда дует; z — сила) плюс встречный ветер от хода.

const H := AnimSpec.Human
const R := AnimSpec.Horse
const S := AnimSpec.Sheep

## Момент выстрела в SHOOT (фаза): вспышка и дым у дула, отдача
const SHOOT_FIRE_PHASE := 0.55
## Дуло ружья в осях модели (юнит смотрит в +Z) в момент выстрела, м
const SHOOT_MUZZLE := Vector3(-0.15, 1.38, 1.45)
## Момент удара в MELEE (фаза): звон клинка, урон
const MELEE_HIT_PHASE := 0.46
## Острие копья при атаке (CHARGE), оси модели, м
const LANCE_TIP_CHARGE := Vector3(0.15, 1.7, 2.65)
## Касание земли копытами (фаза цикла): передние левое/правое, задние левое/правое
const HOOF_CONTACT := {
	R.WALK: Vector4(0.25, 0.75, 0.0, 0.5),
	R.TROT: Vector4(0.0, 0.5, 0.5, 0.0),
	R.GALLOP: Vector4(0.31, 0.43, 0.0, 0.12),
	R.CHARGE: Vector4(0.31, 0.43, 0.0, 0.12),
}
## Касание стоп (фаза цикла): левая, правая
const FOOT_CONTACT := Vector2(0.0, 0.5)

## Скорости смены аллюра, м/с (выше — следующий)
const HUMAN_RUN_FROM := 2.4
const HORSE_TROT_FROM := 2.6
const HORSE_GALLOP_FROM := 5.5
const SHEEP_RUN_FROM := 1.2


## Новая фаза цикла после пути moved (м) при длине цикла stride_m
static func advance(phase: float, moved: float, stride_m: float) -> float:
	return fposmod(phase + moved / maxf(stride_m, 0.01), 1.0)


## Состояние хода по скорости (для skeleton из UnitRegistry). 0 скорость — покой.
static func gait(skeleton: String, speed: float, charging := false) -> int:
	match skeleton:
		"human":
			if speed < 0.05:
				return H.IDLE
			return H.WALK if speed < HUMAN_RUN_FROM else H.RUN
		"sheep":
			if speed < 0.05:
				return S.GRAZE
			return S.WALK if speed < SHEEP_RUN_FROM else S.RUN
		_:
			if speed < 0.05:
				return R.IDLE
			if speed < HORSE_TROT_FROM:
				return R.WALK
			if speed < HORSE_GALLOP_FROM:
				return R.TROT
			return R.CHARGE if charging else R.GALLOP


## Длина полного цикла шага, м (AnimSpec.STRIDE_*); для не-циклов — 1
static func stride(skeleton: String, state: int) -> float:
	match skeleton:
		"human":
			if state == H.WORK:
				return AnimSpec.STRIDE_HUMAN[H.WALK]
			return AnimSpec.STRIDE_HUMAN.get(state, 1.0)
		"sheep":
			return AnimSpec.STRIDE_SHEEP.get(state, 1.0)
		_:
			return AnimSpec.STRIDE_HORSE.get(state, 1.0)


## Длина цикла с учётом масштаба вида (UnitRegistry «scale»: крупный полководец шагает шире)
static func stride_for(unit_id: String, state: int) -> float:
	var u := UnitRegistry.info(unit_id)
	return stride(u.get("skeleton", "human"), state) * float(u.get("scale", 1.0))


## Длительность разового состояния, с (AnimSpec.DURATION_*); для циклов покоя — IDLE_PERIOD
static func duration(skeleton: String, state: int) -> float:
	match skeleton:
		"human":
			return AnimSpec.DURATION_HUMAN.get(state, AnimSpec.IDLE_PERIOD)
		"sheep":
			return AnimSpec.DURATION_SHEEP.get(state, AnimSpec.IDLE_PERIOD)
		_:
			return AnimSpec.DURATION_HORSE.get(state, AnimSpec.IDLE_PERIOD)


## Циклы, у которых фаза идёт по пути (а не по времени)
static func is_locomotion(skeleton: String, state: int) -> bool:
	match skeleton:
		"human":
			return state in [H.WALK, H.RUN, H.FLEE]
		"sheep":
			return state in [S.WALK, S.RUN]
		_:
			return state in [R.WALK, R.TROT, R.GALLOP, R.CHARGE]


## Положение точки модели в мире (например, дула): xform экземпляра × точка
static func world_point(xform: Transform3D, model_point: Vector3) -> Vector3:
	return xform * model_point
