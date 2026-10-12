// Пылинка-спрайт (пух ковыля, пепел): маленький билборд из атласа 2×2, вырез по альфе.
// Против солнца пух вспыхивает тёплым (контровой свет), в тени — холодный и тусклый.
shader_type spatial;
render_mode unshaded, depth_draw_opaque, cull_disabled, shadows_disabled;

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 grid = vec2(2.0, 2.0);
uniform vec3 sun_dir = vec3(-0.9, 0.17, 0.38);
uniform vec3 sun_color = vec3(1.0, 0.74, 0.52);
uniform vec4 tint_lit : source_color = vec4(1.0, 0.92, 0.78, 1.0);
uniform vec4 tint_shade : source_color = vec4(0.45, 0.52, 0.62, 1.0);
uniform float glow = 2.2;            // вспышка против солнца
uniform float fade_dist = 70.0;      // дальше — растворяется
uniform float alpha_cut = 0.45;

varying float v_age;
varying float v_cell;
varying float v_dist;

void vertex() {
	float s = length(MODEL_MATRIX[0].xyz);
	v_age = clamp(INSTANCE_CUSTOM.y, 0.0, 1.0);
	v_cell = float(INSTANCE_ID % 4);
	float r = INSTANCE_CUSTOM.x;
	vec2 q = vec2(VERTEX.x * cos(r) - VERTEX.y * sin(r), VERTEX.x * sin(r) + VERTEX.y * cos(r)) * s;
	vec3 right = normalize(INV_VIEW_MATRIX[0].xyz);
	vec3 up = normalize(INV_VIEW_MATRIX[1].xyz);
	vec3 back = normalize(INV_VIEW_MATRIX[2].xyz);
	mat4 world = mat4(vec4(right, 0.0), vec4(up, 0.0), vec4(back, 0.0), MODEL_MATRIX[3]);
	VERTEX = vec3(q, 0.0);
	MODELVIEW_MATRIX = VIEW_MATRIX * world;
	v_dist = length(MODEL_MATRIX[3].xyz - INV_VIEW_MATRIX[3].xyz);
}

void fragment() {
	vec2 cxy = vec2(mod(v_cell, grid.x), floor(v_cell / grid.x));
	vec4 t = texture(atlas, (cxy + clamp(UV, vec2(0.004), vec2(0.996))) / grid);
	vec3 cam_fwd = -normalize(INV_VIEW_MATRIX[2].xyz);
	float back = pow(clamp(dot(cam_fwd, normalize(sun_dir)), 0.0, 1.0), 3.0);
	vec3 c = t.rgb * mix(tint_shade.rgb, tint_lit.rgb * sun_color, 0.55 + 0.45 * back);
	c += t.rgb * sun_color * back * glow;
	float life = smoothstep(0.0, 0.08, v_age) * (1.0 - smoothstep(0.85, 1.0, v_age));
	float far = 1.0 - smoothstep(fade_dist * 0.6, fade_dist, v_dist);
	ALBEDO = c;
	ALPHA = t.a * life * far;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
}
