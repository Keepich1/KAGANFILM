class_name NetBot
extends RefCounted
## Сценарный игрок для проверок игры по сети (tests/test_net.gd, tests/net_peer.gd): ScriptedPlayer (добыча,
## найм, жильё, ход работника) и ещё ход, найм и стройка пораньше — чтобы за 900 тактов у каждого игрока были
## приказы всех видов, и вокруг обрыва связи (такт ~300) тоже. Приказы отдаёт через GameDriver.issue — как
## интерфейс, поэтому они идут пакетами такта (NetMatch).

var player := 0
var _sp: ScriptedPlayer


func _init(p_player := 0) -> void:
	player = p_player
	_sp = ScriptedPlayer.new(p_player)


func commands(tick: int, q: GameQuery) -> Array[PackedInt32Array]:
	var out := _sp.commands(tick, q)
	var gq := q as GameQueryImpl
	if gq == null or gq.is_defeated(player):
		return out
	var ws := _workers(gq)
	if ws.is_empty():
		return out
	match tick:
		90, 280, 320, 520:
			# работник туда-сюда (MOVE), в том числе вокруг обрыва связи
			var w := ws[(tick / 10) % ws.size()]
			var off := Vector2(10, 4) if tick % 20 == 10 else Vector2(-8, 6)
			out.append(SimCmd.move(PackedInt32Array([w]), gq.unit_pos(w) + off))
		150, 410:
			var P := q.players()
			var defs := q.defs()
			out.append(SimCmd.train(P.hq_b[player], defs.f_worker[P.faction[player]], 1))
		240:
			# ещё одно жильё — в другую сторону, чем у ScriptedPlayer
			var defs := q.defs()
			var f := q.players().faction[player]
			var house := defs.building(&"uy" if defs.f_ids[f] == "kokand" else &"boz")
			var hq := AiController.hq_pos(q, player)
			if house >= 0 and hq != Vector2.INF:
				out.append(SimCmd.build(ws.slice(0, 1), house, q.snap(house, hq + Vector2(-34, 30), 0), 0))
	return out


func _workers(gq: GameQueryImpl) -> PackedInt32Array:
	var out := PackedInt32Array()
	for u in gq.units_of(player):
		if gq.unit_flags(u) & UnitStats.WORKER:
			out.append(u)
	return out
