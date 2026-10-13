class_name Victory
extends RefCounted
## Победа и поражение в «Городе» (ARCHITECTURE §3 #16, §7.4; ТЗ 9): ядро в режиме NONE, решает GAME.
## Игрок побеждён (PLAYER_DEFEATED, a: 0 — ставка, 1 — арба с ордо; b — команда), когда:
##   • ставка (PlayerTable.hq_b) разрушена — описатель недействителен или здание в руинах;
##   • ставка свёрнута в арбу (hq_b = 0, здание PACKED), а этой арбы больше нет.
## Когда в игре остались игроки одной команды — VICTORY(a команда), over = true (GameSim.over).
## Таблицы пишет только ECON, поэтому «выбыл» хранится здесь (defeated); Orders и ИИ смотрят сюда.

const REASON_HQ := 0
const REASON_ARBA := 1
const ARBA_GRACE := 30          # тактов ищем арбу после сворачивания, прежде чем считать её потерянной

var defeated := PackedByteArray()       # [игрок] 1 — выбыл
var winner_team := -1
var over := false

var _econ: EconApi
var _port: CombatPort
var _events: SimEvents

var _hq := PackedInt32Array()           # последняя известная ставка игрока
var _arba := PackedInt32Array()         # арба со ставкой (описатель юнита), 0
var _packed_t := PackedInt32Array()     # такт, когда ставку увидели свёрнутой (−1)
var _buf := PackedInt32Array()


func setup(econ: EconApi, port: CombatPort, events: SimEvents) -> void:
	_econ = econ
	_port = port
	_events = events


func is_defeated(p: int) -> bool:
	return p >= 0 and p < defeated.size() and defeated[p] == 1


func check(tick: int) -> void:
	if over:
		return
	var P := _econ.players
	var n := P.count
	if defeated.size() < n:
		_grow(n)
	for p in n:
		if defeated[p] == 1:
			continue
		var r := _lost(p, tick)
		if r >= 0:
			defeated[p] = 1
			_events.push(SimEvents.Ev.PLAYER_DEFEATED, p, r, P.team[p])
	# остались игроки одной команды?
	var teams := PackedInt32Array()
	for p in n:
		if defeated[p] == 0 and P.ctrl[p] != PlayerTable.Ctrl.NONE and not teams.has(P.team[p]):
			teams.append(P.team[p])
	if teams.size() <= 1 and n > 1:
		winner_team = teams[0] if teams.size() == 1 else -1
		over = true
		_events.push(SimEvents.Ev.VICTORY, -1, winner_team)


## Причина поражения игрока p или −1
func _lost(p: int, tick: int) -> int:
	var P := _econ.players
	var B := _econ.buildings
	var h := P.hq_b[p]
	if h != Ids.NULL:
		_hq[p] = h
		_arba[p] = Ids.NULL
		_packed_t[p] = -1
		if not B.valid(h) or B.state[B.slot(h)] == BuildingTable.State.RUIN:
			return REASON_HQ
		return -1
	# hq_b = 0: ставка свёрнута в арбу (или её не было с начала)
	var last := _hq[p]
	if last == Ids.NULL:
		return -1                                   # ставки не было (сценарий теста)
	if not B.valid(last) or B.state[B.slot(last)] == BuildingTable.State.RUIN:
		return REASON_ARBA if _arba[p] != Ids.NULL else REASON_HQ
	if B.state[B.slot(last)] != BuildingTable.State.PACKED:
		return -1                                   # снова стоит (ECON вернёт hq_b)
	if _arba[p] != Ids.NULL:
		if _port.alive(_arba[p]) and _econ.arba_cargo(_arba[p]) == last:
			return -1
		_arba[p] = _find_arba(p, last)
		return -1 if _arba[p] != Ids.NULL else REASON_ARBA
	_arba[p] = _find_arba(p, last)
	if _arba[p] != Ids.NULL:
		return -1
	if _packed_t[p] < 0:
		_packed_t[p] = tick
	return REASON_ARBA if tick - _packed_t[p] > ARBA_GRACE else -1


## Арба игрока p, везущая постройку b_h (перебор арб игрока — только пока ставка в пути)
func _find_arba(p: int, b_h: int) -> int:
	var P := _econ.players
	var port := _port
	port.units_near(P.team[p], Vector2.ZERO, 1.0e6, false, UnitStats.WAGON, _buf)
	for u in _buf:
		if port.owner(u) == p and _econ.arba_cargo(u) == b_h:
			return u
	return Ids.NULL


func _grow(n: int) -> void:
	while defeated.size() < n:
		defeated.append(0)
		_hq.append(Ids.NULL)
		_arba.append(Ids.NULL)
		_packed_t.append(-1)


func checksum() -> int:
	var h := 11
	for i in defeated.size():
		h = (h * 31 + defeated[i] * 3 + (_arba[i] & 0xFFFF)) & 0x7FFFFFFF
	return (h * 31 + winner_team + 1) & 0x7FFFFFFF
