class_name ScriptedFort
extends RefCounted
## Сценарные укрепления и көч для автобоёв (ARCHITECTURE §15 «автобои»; ТЗ §6, ECONOMY §3.6): у ИИ-игроков
## нет своей экономики (ТЗ §16.2, этап 3), поэтому стены, ворота, башню и көч в автобое ставит этот сценарий —
## приказами SimCmd через GameSim.submit (как интерфейс), так что всё идёт через Orders и попадает в повтор.
## Читает только GameQuery. Детерминирован (без случайности, только номер такта).
##   60-я с  — линия стены (пахса девор / жыгач чеп) поперёк пути врага в 50 (62) м от ставки, трое работников;
##   150-я с — ворота посреди стены (Дарвоза / Дарбаза);
##   210-я с — башня на стене у её конца (Бурж у Коканда — если хватает кирпича; Күзөт мунарасы у кыпчаков);
##   кыпчаки: 300-я с — свернуть весь лагерь (Shift+K), 330-я с — развернуть арбы на старом месте (K).

## м от ставки к врагу: у кыпчаков дальше — за мунарами базы ИИ (MapValley layout, x = −122)
const WALL_AT := {"kokand": 50.0, "kipchak": 62.0}
const WALL_HALF := 24.0            # м: полудлина линии стены
const T_WALL := 60 * 30
const T_GATE := 150 * 30
const T_TOWER := 210 * 30
const T_PACK := 300 * 30
const T_UNPACK := 330 * 30

var player := 0
## Что сделано (для отчёта автобоя): wall, gate, tower, pack, unpack — такт приказа (0 — нет)
var done := {}

var _a := Vector2.ZERO
var _b := Vector2.ZERO
var _camp := Vector2.INF


func _init(p_player := 0) -> void:
	player = p_player


func commands(tick: int, q: GameQuery) -> Array[PackedInt32Array]:
	var out: Array[PackedInt32Array] = []
	var gq := q as GameQueryImpl
	if gq == null or gq.is_defeated(player):
		return out
	var defs := q.defs()
	var P := q.players()
	var fid := defs.f_ids[P.faction[player]]
	var kip := fid == "kipchak"
	if tick == T_WALL:
		var hq := AiController.hq_pos(q, player)
		var e := AiController.enemy_of(q, player)
		var ehq := AiController.hq_pos(q, e) if e >= 0 else Vector2.INF
		if hq == Vector2.INF or ehq == Vector2.INF:
			return out
		# линия поперёк направления на врага (по главной оси)
		var d := ehq - hq
		var fwd := Vector2(signf(d.x), 0) if absf(d.x) >= absf(d.y) else Vector2(0, signf(d.y))
		var side := Vector2(-fwd.y, fwd.x)
		var mid := hq + fwd * float(WALL_AT.get(fid, 50.0))
		_a = mid - side * WALL_HALF
		_b = mid + side * WALL_HALF
		var wt := defs.building(&"chep" if kip else &"devor")
		out.append(SimCmd.build_wall(_workers(gq, 3), wt, PackedVector2Array([_a, _b])))
		done["wall"] = tick
	if tick == T_GATE and done.has("wall"):
		var gt := defs.building(&"darbaza" if kip else &"darvoza")
		out.append(SimCmd.build(_workers(gq, 3), gt, (_a + _b) * 0.5, 0))
		done["gate"] = tick
	if tick == T_TOWER and done.has("wall"):
		var tt := defs.building(&"munara" if kip else &"burj")
		var cost := defs.building_cost(tt)
		for r in cost.size():
			if cost[r] > 0 and P.res[player * defs.R + r] < cost[r]:
				return out           # Бурж — за кирпич; у ИИ без экономики его нет

		var at := _a + (_b - _a) * 0.15
		out.append(SimCmd.build(_workers(gq, 3), tt, q.snap(tt, at, 0), 0))
		done["tower"] = tick
	if kip and tick == T_PACK:
		var hq_h := P.hq_b[player]
		if hq_h != Ids.NULL:
			_camp = AiController.hq_pos(q, player)
			out.append(SimCmd.pack_all(hq_h))
			done["pack"] = tick
	if kip and tick == T_UNPACK and _camp != Vector2.INF:
		var arbas := PackedInt32Array()
		for u in gq.units_of(player):
			if gq.unit_type(u) == &"arba" and gq.unit_alive(u):
				arbas.append(u)
		if not arbas.is_empty():
			out.append(SimCmd.unpack(arbas, _camp))
			done["unpack"] = tick
	return out


## До n работников игрока (по порядку описателей)
func _workers(gq: GameQueryImpl, n: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for u in gq.units_of(player):
		if out.size() >= n:
			break
		if gq.unit_flags(u) & UnitStats.WORKER:
			out.append(u)
	return out
