class_name EconNomad
extends RefCounted
## Көч кыпчаков (ARCHITECTURE §11 «Köч»; ECONOMY §3.6; ТЗ 5.4).
##   • pack(b): постройка с флагом packable сворачивается pack_s (15 с) — сразу не даёт населения и работы;
##     потом — PACKED: снимается с сетки и из ядра, у неё появляются арбы (arbas: юрта — 1, ставка и
##     Курултай — 2), arba_cargo(арба) → здание; стада загона едут с первой арбой; PACKED(a здание, b арба);
##   • pack_all(ставка): всё сворачиваемое своё в pack_r (170 м); ставка в арбе — players.hq_b = 0;
##   • unpack(арбы, центр): ставка — в центр, прочие — на кольцо NavApi.ring_slots; арбы едут, на месте
##     исчезают, постройка — SITE и встаёт сама за unpack_s (работники ускоряют); готово — UNPACKED;
##   • арба убита — если у здания арб не осталось, здание и его стада пропали (ставка — поражение, Victory).

const ARRIVE_R := 4.0
const ARBA_GAP := 3.0


func pack(e: EconomySim, p: int, b_h: int) -> int:
	var b := e._own(p, b_h)
	if b < 0:
		return b
	var B := e.buildings
	if B.flags[b] & Defs.BF_PACKABLE == 0 or not e.faction_has(p, "koch"):
		return -EconApi.Err.NOT_ALLOWED
	if B.state[b] != BuildingTable.State.ACTIVE or e.b_mode[b] != EconomySim.Mode.NONE:
		return -EconApi.Err.BUSY
	e.b_mode[b] = EconomySim.Mode.PACKING
	e.b_timer[b] = e.tick + int(e.rules.get("pack_ticks", 450))
	e.prod.clear_queue(e, b)
	e._pop_dirty = true
	e._drops_dirty = true
	return EconApi.Err.OK


func pack_all(e: EconomySim, p: int, hq_h: int) -> int:
	var hq := e._own(p, hq_h)
	if hq < 0:
		return hq
	var B := e.buildings
	if B.flags[hq] & Defs.BF_HQ == 0:
		return -EconApi.Err.INVALID
	var r := float(e.rules.get("pack_r", 170.0))
	var c := Vector2(B.x[hq], B.z[hq])
	var n := 0
	for b in B.hw:
		if B.owner[b] == p and B.state[b] == BuildingTable.State.ACTIVE and B.flags[b] & Defs.BF_PACKABLE \
				and Vector2(B.x[b], B.z[b]).distance_squared_to(c) <= r * r:
			if pack(e, p, B.handle(b)) == EconApi.Err.OK:
				n += 1
	return EconApi.Err.OK if n > 0 else -EconApi.Err.NOT_ALLOWED


func unpack(e: EconomySim, p: int, arbas: PackedInt32Array, center: Vector2) -> int:
	var B := e.buildings
	var list := PackedInt32Array()        # здания по порядку арб
	for a in arbas:
		if not e.is_ours(a) or e.un_owner[Ids.slot(a)] != p:
			continue
		var c := e.un_cargo[Ids.slot(a)]
		if c > 0 and not list.has(c - 1) and B.state[c - 1] == BuildingTable.State.PACKED:
			list.append(c - 1)
	if list.is_empty():
		return -EconApi.Err.INVALID
	var ring := PackedInt32Array()
	var hq := -1
	for b in list:
		if B.flags[b] & Defs.BF_HQ:
			hq = b
		else:
			ring.append(B.btype[b])
	var slots := e.nav.ring_slots(p, center, ring) if e.nav and not ring.is_empty() else PackedVector2Array()
	var k := 0
	for b in list:
		var dest := center
		if b != hq:
			dest = slots[k] if k < slots.size() else center + Vector2(k * 10.0, 0.0)
			k += 1
		if e.nav:
			dest = e.nav.snap(B.btype[b], dest, B.rot_q[b])
		e.b_dest[b] = dest
		e.b_mode[b] = EconomySim.Mode.UNPACK
		var mine := arbas_of(e, b)
		e.port.move(mine, dest, false)
	return EconApi.Err.OK


func arbas_of(e: EconomySim, b: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for s in e.un_cargo.size():
		if e.un_cargo[s] == b + 1 and e.un_gen[s] != 0:
			out.append(Ids.make(Ids.Kind.UNIT, s, e.un_gen[s]))
	return out


func slow_step(e: EconomySim) -> void:
	var B := e.buildings
	for b in B.hw:
		var mode := e.b_mode[b]
		if mode == EconomySim.Mode.PACKING and B.state[b] == BuildingTable.State.ACTIVE and e.tick >= e.b_timer[b]:
			_finish_pack(e, b)
		elif B.state[b] == BuildingTable.State.PACKED:
			var arbas := arbas_of(e, b)
			if arbas.is_empty():
				continue
			_carry_herds(e, b, e.port.pos(arbas[0]))
			if mode == EconomySim.Mode.UNPACK:
				var all_in := true
				for a in arbas:
					if not e.port.is_idle(a) and e.port.pos(a).distance_squared_to(e.b_dest[b]) > ARRIVE_R * ARRIVE_R:
						all_in = false
						break
				if all_in:
					_erect(e, b, arbas)


func _finish_pack(e: EconomySim, b: int) -> void:
	var B := e.buildings
	var p := B.owner[b]
	var bt := B.btype[b]
	var c := Vector2(B.x[b], B.z[b])
	e._unplace_world(b)
	B.state[b] = BuildingTable.State.PACKED
	e.b_mode[b] = EconomySim.Mode.NONE
	B.workers_n[b] = 0
	if B.flags[b] & Defs.BF_HQ and e.players.hq_b[p] == B.handle(b):
		e.players.hq_b[p] = 0
	var au := e.defs.unit(&"arba")
	var first := 0
	for i in maxi(e.defs.b_arbas[bt], 1):
		var pos := c + Vector2((i - (e.defs.b_arbas[bt] - 1) * 0.5) * ARBA_GAP, 0.0)
		if e.nav:
			pos = e.nav.nearest_passable(B.team[b], pos)
		var h := e.port.spawn(p, B.team[b], &"arba", pos, B.rot[b])
		if h == 0:
			continue
		e.register_unit(h, p, au)
		e.un_cargo[Ids.slot(h)] = b + 1
		if first == 0:
			first = h
		e.events.push(SimEvents.Ev.UNIT_SPAWNED, p, h, B.handle(b), au, pos)
	var H := e.herds
	var bh := B.handle(b)
	for h in H.hw:
		if H.pen_b[h] == bh and H.state[h] == HerdTable.State.PEN:
			H.state[h] = HerdTable.State.DRIVEN
			H.captor_u[h] = 0
			H.capture_t[h] = 0
	e._pop_dirty = true
	e._drops_dirty = true
	e.events.push(SimEvents.Ev.PACKED, p, bh, first, bt, c)


func _carry_herds(e: EconomySim, b: int, pos: Vector2) -> void:
	var H := e.herds
	var bh := e.buildings.handle(b)
	for h in H.hw:
		if H.pen_b[h] == bh and H.state[h] == HerdTable.State.DRIVEN:
			H.x[h] = pos.x
			H.z[h] = pos.y


## Арбы на месте: исчезают, постройка — SITE, встаёт сама за unpack_s
func _erect(e: EconomySim, b: int, arbas: PackedInt32Array) -> void:
	var B := e.buildings
	var bt := B.btype[b]
	var dest := e.b_dest[b]
	if e.nav and e.nav.check_place(B.owner[b], bt, dest, B.rot_q[b]) != NavApi.Why.OK:
		dest = _free_spot(e, b, dest)
	for a in arbas:
		e.unregister_unit(a)
		e.port.remove(a)
	B.x[b] = dest.x
	B.z[b] = dest.y
	var rect := NavApi.footprint(e.defs, bt, dest, B.rot_q[b], e.origin)
	B.c0[b] = rect.position.x
	B.r0[b] = rect.position.y
	B.cw[b] = rect.size.x
	B.ch[b] = rect.size.y
	B.state[b] = BuildingTable.State.SITE
	e._place_world(b)
	e._start_site(b, maxi(e.defs.b_unpack_ticks[bt], 30))
	e.b_mode[b] = EconomySim.Mode.ERECT
	B.hp_c[b] = B.hp_max_c[b] / 2
	e.events.push(SimEvents.Ev.SITE_PLACED, B.owner[b], B.handle(b), bt, 0, dest)


func _free_spot(e: EconomySim, b: int, at: Vector2) -> Vector2:
	var B := e.buildings
	for rr in [8.0, 16.0, 24.0]:
		for d: Vector2 in EconWorkers.DIR8:
			var p := e.nav.snap(B.btype[b], at + d * rr, B.rot_q[b])
			if e.nav.check_place(B.owner[b], B.btype[b], p, B.rot_q[b]) == NavApi.Why.OK:
				return p
	return at


## Арба убита: здание пропало, если арб у него не осталось
func arba_died(e: EconomySim, u_h: int, b: int) -> void:
	var left := 0
	for s in e.un_cargo.size():
		if e.un_cargo[s] == b + 1 and e.un_gen[s] != 0 and s != Ids.slot(u_h):
			left += 1
	if left == 0 and e.buildings.state[b] == BuildingTable.State.PACKED:
		e.destroy_building(b, -1)
