// Вспышка выстрела: рисованный язык пламени вдоль ствола, складывается со светом (add).
// Направление и длина — ось X трансформа частицы (её задаёт скрипт при пуске),
// возраст — CUSTOM.y (fx_still.gdshader). Живёт доли секунды.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 grid = vec2(2.0, 2.0);
uniform float intensity = 2.6;

varying float v_age;
varying float v_cell;

void vertex() {
	v_age = clamp(INSTANCE_CUSTOM.y, 0.0, 1.0);
	v_cell = float(INSTANCE_ID % int(grid.x * grid.y));
	vec3 axis = MODEL_MATRIX[0].xyz;
	float len = length(axis);
	vec3 org = MODEL_MATRIX[3].xyz;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 view = normalize(org - cam);
	// ось спрайта — проекция ствола на плоскость экрана
	vec3 right = axis / max(len, 1e-4);
	right = normalize(right - view * dot(right, view) + vec3(1e-5));
	vec3 up = normalize(cross(view, right));
	// спрайт начинается у дула (u = 0.22 в клетке) и уходит вперёд
	float grow = mix(0.7, 1.15, smoothstep(0.0, 0.35, v_age));
	vec2 q = vec2(VERTEX.x + 0.28, VERTEX.y) * len * grow;
	mat4 world = mat4(vec4(right, 0.0), vec4(up, 0.0), vec4(-view, 0.0), vec4(org, 1.0));
	VERTEX = vec3(q, 0.0);
	MODELVIEW_MATRIX = VIEW_MATRIX * world;
}

void fragment() {
	vec2 cxy = vec2(mod(v_cell, grid.x), floor(v_cell / grid.x));
	vec4 t = texture(atlas, (cxy + clamp(UV, vec2(0.004), vec2(0.996))) / grid);
	float fade = 1.0 - smoothstep(0.25, 1.0, v_age);
	ALBEDO = t.rgb * t.a * intensity * fade;
	ALPHA = 1.0;
}
