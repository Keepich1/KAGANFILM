class_name EconCalendar
extends RefCounted
## Сезоны (ECONOMY §3.6) — Сб. 2: по умолчанию выключены (GameRules.seasons = false, SEASONS enabled false),
## PlayerTable.season = −1. Когда включат: лето/зима по кругу ModifierDefs.SEASONS для всех сторон,
## SEASON(a — сезон, b — тактов до смены) и пересборка множителей. Зоны жайлоо/кыштоо — TODO(Сб. 2).

var cur := -1
var until := 0


func slow_step(e: EconomySim) -> void:
	if not bool(e.rules.get("seasons", false)):
		return
	var D := e.defs
	var n := D.s_ids.size()
	if n == 0:
		return
	if cur < 0 or e.tick >= until:
		cur = (cur + 1) % n
		if D.s_enabled[cur] == 0:
			return
		var dur := D.s_first_ticks[cur] if e.tick < D.s_first_ticks[0] + 30 and cur == 0 else D.s_ticks[cur]
		until = e.tick + maxi(dur, 30)
		for p in e.players.count:
			e.players.season[p] = cur
			e.mods.mark(e, p)
			e.events.push(SimEvents.Ev.SEASON, p, cur, until - e.tick)
