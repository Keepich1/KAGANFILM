class_name Replay
extends RefCounted
## Повтор «Города» (ARCHITECTURE §3 #24, §7.4; CONTRACT §10.4): зерно + карта + Defs.hash() + правила +
## игроки + журнал внешних приказов (SimCmd.encode). ИИ в повторе думает сам заново — он в симуляции и
## детерминирован, поэтому его приказы не пишутся. Контрольные суммы раз в 30 тактов — для сверки.
##
##   var rec := game.replay_record()
##   Replay.save("user://last.ordorep", rec)
##   var g := Replay.make_game(Replay.load_file(path)); Replay.run(g, rec)   # или Replay.verify(rec)
##
## Файл — var_to_bytes записи с магией «ORDOREP1» (чтение и запись — только из инструментов и узлов,
## не из шага симуляции).

const VERSION := 1
const MAGIC := "ORDOREP1"

static var last_error := ""


## Игра из записи (setup и приказы журнала в очереди), ещё не прогнана; null — запись не подходит
static func make_game(d: Dictionary, impl := {}) -> GameSim:
	last_error = ""
	if int(d.get("version", 0)) != VERSION:
		last_error = "другая версия повтора: %s" % str(d.get("version", "?"))
		return null
	var defs: Defs = impl.get("defs", null) if impl.get("defs", null) is Defs else Defs.shared()
	if int(d.get("defs_hash", 0)) != defs.hash():
		last_error = "другие данные (Defs.hash %d, в повторе %d)" % [defs.hash(), int(d.get("defs_hash", 0))]
		return null
	var map_id := String(d.get("map_id", "valley"))
	var map: Dictionary = defs.maps.get(map_id, {})
	if map.is_empty():
		last_error = "нет карты %s" % map_id
		return null
	var g := GameSim.new()
	g.impl = impl
	g.setup(map, d.get("players", []), int(d.get("seed", 1)), StringName(str(d.get("rules_id", "GOROD"))))
	g.queue.preload_cmds(SimCmd.decode(d.get("log", PackedByteArray())))
	return g


## Прогнать игру до конца записи (end_tick)
static func run(g: GameSim, d: Dictionary) -> void:
	var end := int(d.get("end_tick", 0))
	while g.tick < end:
		g.step()


## Повтор совпал с записью: те же контрольные суммы (и их столько же)
static func verify(d: Dictionary, impl := {}) -> bool:
	var g := make_game(d, impl)
	if g == null:
		return false
	run(g, d)
	var want: PackedInt64Array = d.get("checksums", PackedInt64Array())
	if g.checksums != want:
		last_error = "контрольные суммы разошлись на %d-й" % _first_diff(g.checksums, want)
		return false
	return true


static func save(path: String, d: Dictionary) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		last_error = "не открыть %s" % path
		return false
	f.store_buffer(MAGIC.to_ascii_buffer())
	f.store_buffer(var_to_bytes(d))
	return true


static func load_file(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		last_error = "не открыть %s" % path
		return {}
	var all := f.get_buffer(f.get_length())
	if all.size() < MAGIC.length() or all.slice(0, MAGIC.length()).get_string_from_ascii() != MAGIC:
		last_error = "не файл повтора: %s" % path
		return {}
	var v: Variant = bytes_to_var(all.slice(MAGIC.length()))
	return v if v is Dictionary else {}


static func _first_diff(a: PackedInt64Array, b: PackedInt64Array) -> int:
	for i in mini(a.size(), b.size()):
		if a[i] != b[i]:
			return i
	return mini(a.size(), b.size())
