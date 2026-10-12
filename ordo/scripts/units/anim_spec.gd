class_name AnimSpec
extends RefCounted
## Договор между симуляцией боя и шейдером толпы (shaders/crowd.gdshader).
##
## Каждый юнит — экземпляр MultiMesh. Данные экземпляра (INSTANCE_CUSTOM, vec4):
##   x — состояние (числа из перечислений ниже, как float)
##   y — фаза 0..1: для циклов (шаг, бег, галоп) — доля цикла;
##       для разовых (удар, выстрел, смерть) — прогресс 0..1
##   z — доп. значение: сила/скорость (0..1) для циклов; для смерти — сторона падения (0 или 1);
##       для WORK — вид работы (0 рубит, 0.25 копает, 0.5 строит, 0.75 несёт)
##   w — вариант 0..1: оттенок одежды, рост, шапка, конская масть (стабилен для юнита)
## Цикл шага продвигается на пройденное расстояние / STRIDE, чтобы ноги не скользили.

enum Human { IDLE, WALK, RUN, MELEE, SHOOT, RELOAD, DYING, DEAD, FLEE, CHEER, WORK, BRACE }
enum Horse { IDLE, WALK, TROT, GALLOP, CHARGE, MELEE, DYING, DEAD, REAR, CHEER }
enum Sheep { GRAZE, WALK, RUN, DYING, DEAD }

## Длина полного цикла (два шага), метров
const STRIDE_HUMAN := { Human.WALK: 1.5, Human.RUN: 2.6, Human.FLEE: 2.6 }
const STRIDE_HORSE := { Horse.WALK: 1.9, Horse.TROT: 3.0, Horse.GALLOP: 6.0, Horse.CHARGE: 6.4 }
const STRIDE_SHEEP := { Sheep.WALK: 0.7, Sheep.RUN: 1.6 }

## Длительность разовых состояний, секунд (фаза идёт 0→1 за это время)
const DURATION_HUMAN := { Human.MELEE: 0.9, Human.SHOOT: 1.4, Human.RELOAD: 11.0, Human.DYING: 1.3, Human.CHEER: 2.0 }
const DURATION_HORSE := { Horse.MELEE: 0.9, Horse.DYING: 1.8, Horse.REAR: 1.6, Horse.CHEER: 2.0 }
const DURATION_SHEEP := { Sheep.DYING: 1.0 }

## Скорость шага/бега, м/с, при которой фаза анимации выглядит естественно
const IDLE_PERIOD := 3.2  # период дыхания и смены веса, с


## Упаковка данных экземпляра для MultiMesh.set_instance_custom_data().
## Фазу циклов передавайте уже в 0..1 (fposmod), разовых — прогресс 0..1.
static func custom(state: int, phase: float, aux: float, variant: float) -> Color:
	return Color(float(state), phase, aux, variant)
