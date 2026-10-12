class_name PathResult
extends RefCounted
## Ответ навигации на запрос пути (ARCHITECTURE §7.2, §9). Только ведущий меняет этот файл.

var pts := PackedVector2Array()       # smoothed waypoints; last = goal snapped to passable
var breach_b := 0                     # building handle to break, 0 = none
var breach_wp := -1                   # index of the waypoint just before the breach
var no_route := false                 # own units cannot reach: pts end at the nearest reachable point
var cost := 0.0
var sectors := PackedInt32Array()     # traversed sectors (staleness)
var issued_ver := 0
