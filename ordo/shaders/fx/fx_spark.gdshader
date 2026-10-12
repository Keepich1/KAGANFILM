// Искры в рукопашной: короткие раскалённые чёрточки вдоль скорости, гаснут на лету (add).
// Ось X трансформа частицы — скорость × длина следа (её пишет fx_spark_move.gdshader).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 hot : source_color = vec4(1.0, 0.86, 0.5, 1.0);
uniform vec4 cool : source_color = vec4(1.0, 0.36, 0.1, 1.0);
uniform float intensity = 3.0;
uniform float width = 0.03;

varying float v_age;

void vertex() {
	v_age = clamp(INSTANCE_CUSTOM.y, 0.0, 1.0);
	vec3 axis = MODEL_MATRIX[0].xyz;
	float len = max(length(axis), 0.04);
	vec3 org = MODEL_MATRIX[3].xyz;
	vec3 view = normalize(org - INV_VIEW_MATRIX[3].xyz);
	vec3 dir = axis / len;
	vec3 right = normalize(dir - view * dot(dir, view) + vec3(1e-5));
	vec3 up = normalize(cross(view, right));
	vec2 q = vec2((VERTEX.x - 0.5) * len, VERTEX.y * width * 2.0);
	mat4 world = mat4(vec4(right, 0.0), vec4(up, 0.0), vec4(-view, 0.0), vec4(org, 1.0));
	VERTEX = vec3(q, 0.0);
	MODELVIEW_MATRIX = VIEW_MATRIX * world;
}

void fragment() {
	float core = 1.0 - smoothstep(0.15, 0.5, abs(UV.y - 0.5));
	float tail = smoothstep(0.0, 0.8, UV.x);
	vec3 c = mix(cool.rgb, hot.rgb, (1.0 - v_age) * tail);
	ALBEDO = c * core * tail * intensity * (1.0 - v_age * v_age);
	ALPHA = 1.0;
}
