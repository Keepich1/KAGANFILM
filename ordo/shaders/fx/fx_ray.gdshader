// Лучи сквозь дым (ТЗ 11.1): рисованные полосы света вдоль солнечного луча, складываются (add).
// Каждая частица — длинная лента по направлению света (sun_dir), повёрнутая к камере вокруг
// своей оси; длина — масштаб X, ширина — масштаб Y трансформа частицы. Видны, когда камера
// смотрит в сторону солнца; рождаются в дыму залпа, живут, пока дым висит (CUSTOM.y — возраст).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 sun_dir = vec3(-0.9, 0.17, 0.38);
uniform vec3 sun_color = vec3(1.0, 0.74, 0.52);
uniform vec4 tint : source_color = vec4(1.0, 0.78, 0.48, 1.0);
uniform float intensity = 0.28;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

varying float v_age;
varying float v_seed;
varying float v_back;

void vertex() {
	v_age = clamp(INSTANCE_CUSTOM.y, 0.0, 1.0);
	v_seed = INSTANCE_CUSTOM.x;
	float len = length(MODEL_MATRIX[0].xyz);
	float wid = length(MODEL_MATRIX[1].xyz);
	vec3 org = MODEL_MATRIX[3].xyz;
	vec3 axis = -normalize(sun_dir);
	vec3 view = normalize(org - INV_VIEW_MATRIX[3].xyz);
	vec3 side = normalize(cross(axis, view) + vec3(1e-5));
	vec3 nrm = cross(side, axis);
	mat4 world = mat4(vec4(axis * len, 0.0), vec4(side * wid, 0.0), vec4(nrm, 0.0), vec4(org, 1.0));
	// клин: у камеры шире (луч расходится из дыма)
	VERTEX = vec3(VERTEX.x, VERTEX.y * mix(0.35, 1.7, VERTEX.x + 0.5), 0.0);
	MODELVIEW_MATRIX = VIEW_MATRIX * world;
	// сильнее всего — когда камера смотрит на солнце
	vec3 cam_fwd = -normalize(INV_VIEW_MATRIX[2].xyz);
	v_back = smoothstep(0.1, 0.85, dot(cam_fwd, normalize(sun_dir)));
}

float stripes(float v, float s) {
	// несколько неровных полос поперёк ленты — как мазки кистью
	float a = sin(v * 9.0 + s * 13.0) * 0.5 + 0.5;
	float b = sin(v * 23.0 + s * 7.0) * 0.5 + 0.5;
	return smoothstep(0.35, 0.8, a * 0.65 + b * 0.35);
}

void fragment() {
	float u = UV.x;
	float v = UV.y;
	float along = smoothstep(0.0, 0.35, u) * (1.0 - smoothstep(0.55, 1.0, u));
	float across = smoothstep(0.0, 0.3, v) * (1.0 - smoothstep(0.7, 1.0, v));
	float life = smoothstep(0.0, 0.25, v_age) * (1.0 - smoothstep(0.55, 1.0, v_age));
	// не светить сквозь стоящих впереди (мягко по глубине)
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 vp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float soft = clamp(((-vp.z / vp.w) + VERTEX.z) / 3.0, 0.0, 1.0);
	float k = along * across * stripes(v, v_seed) * life * v_back * soft;
	ALBEDO = tint.rgb * sun_color * intensity * k;
	ALPHA = 1.0;
}
