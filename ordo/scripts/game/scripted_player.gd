class_name ScriptedPlayer
extends RefCounted
## Сценарный «игрок» для тестов и автобоев (ARCHITECTURE §15 «AI-vs-scripted»): детерминированный набор
## приказов от имени игрока-человека, которые тест подаёт через GameSim.submit (как интерфейс) — поэтому
## они попадают в журнал повтора. Читает только GameQuery.
##   каждые 5 с  — свободных работников на ближайшие дерево / жилу / своё поле;
##   каждые 20 с — нанять работника в ставке;
##   на 10-й с и дальше каждые 60 с — поставить жильё рядом со ставкой (может получить отказ — это тоже проверка);
##   каждые 45 с — одного работника отвести и вернуть (приказ MOVE снимает его с работы);
##   каждые 90 с — заведомо устаревший приказ (отказ STALE).

const DIRS := [Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2(-1, 1), Vector2(-1, 0), Vector2(-1, -1),
	Vector2(0, -1), Vector2(1, -1)]

var player := 0
var _sent := 0
var _house_k := 0
var _moved := Ids.NULL


func _init(p_player := 0) -> void:
	player = p_player


## Приказы на этом такте (тест подаёт их через game.submit(player, cmd))
func commands(tick: int, q: GameQuery) -> Array[PackedInt32Array]:
	var out: Array[PackedInt32Array] = []
	var gq := q as GameQueryImpl
	if gq == null or gq.is_defeated(player):
		return out
	var defs := q.defs()
	var P := q.players()
	var f := P.faction[player]
	var hq := AiController.hq_pos(q, player)
	if tick % 150 == 30:
		var idle := q.idle_workers(player)
		if idle.is_empty():
			idle = _workers(gq)
		var k := 0
		for w in idle:
			if k >= 6:
				break
			var src := _source(gq, gq.unit_pos(w), k)
			if src != Ids.NULL:
				out.append(SimCmd.gather(PackedInt32Array([w]), src))
				k += 1
	if tick % 600 == 45 and hq != Vector2.INF:
		out.append(SimCmd.train(P.hq_b[player], defs.f_worker[f], 1))
	if tick == 300 or (tick > 300 and tick % 1800 == 300):
		var house := defs.building(&"uy" if defs.f_ids[f] == "kokand" else &"boz")
		if house >= 0 and hq != Vector2.INF:
			var off: Vector2 = DIRS[_house_k % 8] * (28.0 + 6.0 * (_house_k / 8))
			_house_k += 1
			var at := q.snap(house, hq + off, 0)
			var ws := _workers(gq)
			out.append(SimCmd.build(ws.slice(0, 1), house, at, 0))
	if tick % 1350 == 600:
		var ws := _workers(gq)
		if not ws.is_empty():
			_moved = ws[ws.size() - 1]
			out.append(SimCmd.move(PackedInt32Array([_moved]), gq.unit_pos(_moved) + Vector2(12, 6)))
	if tick % 1350 == 1050 and _moved != Ids.NULL and gq.unit_alive(_moved):
		out.append(SimCmd.move(PackedInt32Array([_moved]), gq.unit_pos(_moved) - Vector2(12, 6), true))
	if tick % 2700 == 900:
		# устаревший описатель: поколение, которого у слота ещё не было
		out.append(SimCmd.stop(PackedInt32Array([Ids.make(Ids.Kind.UNIT, 0, 4000)])))
	_sent += out.size()
	return out


func sent() -> int:
	return _sent


## Работники игрока (по порядку описателей)
func _workers(gq: GameQueryImpl) -> PackedInt32Array:
	var out := PackedInt32Array()
	for u in gq.units_of(player):
		if gq.unit_flags(u) & UnitStats.WORKER:
			out.append(u)
	return out


## Источник добычи: чётные — ближайшее дерево, нечётные — ближайшая жила (в 200 м)
func _source(gq: GameQueryImpl, from: Vector2, k: int) -> int:
	var N := gq.nodes()
	var defs := gq.defs()
	var want_tree := k % 2 == 0
	var best := Ids.NULL
	var bd := 200.0 * 200.0
	for n in N.hw:
		var nt := N.ntype[n]
		if nt < 0 or N.amount_milli[n] == 0:
			continue
		if (defs.n_scatter_kind[nt] >= 0) != want_tree:
			continue
		var d := Vector2(N.x[n], N.z[n]).distance_squared_to(from)
		if d < bd:
			bd = d
			best = N.handle(n)
	return best
