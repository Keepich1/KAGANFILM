class_name BattleRng
extends RefCounted
## Свой генератор случайностей боя (xorshift32): одинаковое зерно → одинаковый бой
## на любом устройстве (ТЗ 14). Глобальные randf()/randi() в бою не используются.
##
##   var r := BattleRng.new(7)
##   r.next_float()          # 0..1
##   r.range_f(-1.0, 1.0)
##   r.chance(0.45)

const _MASK := 0xFFFFFFFF

var state := 2463534242


func _init(p_seed := 1) -> void:
	reseed(p_seed)


func reseed(p_seed: int) -> void:
	# перемешиваем зерно (splitmix-подобно), чтобы соседние зёрна не давали похожих рядов
	var s := (p_seed * 0x9E3779B1 + 0x7F4A7C15) & _MASK
	s = ((s ^ (s >> 16)) * 0x85EBCA6B) & _MASK
	s = ((s ^ (s >> 13)) * 0xC2B2AE35) & _MASK
	s = s ^ (s >> 16)
	state = s if s != 0 else 2463534242


## Следующее 32-битное число
func next_u32() -> int:
	var x := state
	x ^= (x << 13) & _MASK
	x ^= x >> 17
	x ^= (x << 5) & _MASK
	state = x
	return x


## 0..1 (без единицы)
func next_float() -> float:
	return float(next_u32()) / 4294967296.0


func range_f(a: float, b: float) -> float:
	return a + (b - a) * next_float()


## 0..n-1
func range_i(n: int) -> int:
	return next_u32() % maxi(n, 1)


func chance(p: float) -> bool:
	return next_float() < p


## Стабильное число 0..1 по целому ключу (без состояния): вариант юнита, разброс
static func hash01(key: int) -> float:
	var x := (key * 0x45D9F3B + 0x2545F491) & _MASK
	x = ((x ^ (x >> 16)) * 0x45D9F3B) & _MASK
	x = ((x ^ (x >> 16)) * 0x45D9F3B) & _MASK
	x = x ^ (x >> 16)
	return float(x) / 4294967296.0
