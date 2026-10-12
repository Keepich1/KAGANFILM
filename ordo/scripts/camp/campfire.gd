extends Node3D
## Костёр лагеря: кострище (campfire.glb), пламя, тёплый свет с мерцанием, дым.
## Мерцание детерминировано (зависит только от времени сцены и позиции) — кадры повторяемы.

@export var light_energy := 2.6
@export var light_range := 9.0
@export var flicker := 0.22
@export var show_model := true

@onready var _light: OmniLight3D = $Light
var _phase := 0.0
var _t := 0.0


func _ready() -> void:
	var model := get_node_or_null("Model")
	if model:
		model.visible = show_model
		KipchakModels.apply(model)
	_light.omni_range = light_range
	if KipchakCamp.is_low_quality(self):
		# телефоны (ТЗ 11.7): меньше частиц
		($Sparks as GPUParticles3D).amount = 4
		($Smoke as GPUParticles3D).amount = 7
	_phase = fposmod(global_position.x * 0.731 + global_position.z * 0.417, TAU)


func _process(delta: float) -> void:
	_t += delta
	var t := _t * 9.0 + _phase
	var n := sin(t) * 0.5 + sin(t * 2.37 + 1.3) * 0.3 + sin(t * 5.1 + 0.7) * 0.2
	_light.light_energy = light_energy * (1.0 + flicker * n)
	_light.position.y = 0.9 + 0.05 * sin(t * 1.7)
