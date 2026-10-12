// Река (ТЗ 11.1): рисованная вода. Отражает закатное небо (отражения движка от неба
// с френелем), сквозь мелкую воду видно дно, в глубине — тёмная бирюза. Рябь — вытянутые
// по течению мазки, у берегов и на перекате брода — пена штрихами. Солнечная дорожка
// ломается мазком. Течение и скорость — из цвета вершин (scripts/world/river_water.gd).
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_always, specular_schlick_ggx;

#include "res://shaders/include/painterly.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
// кисть с мип-картами (как ordo_brush): assets/textures/world/brush_world.png
uniform sampler2D brush_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;

uniform float water_level = -4.0;
uniform vec4 scatter_color : source_color = vec4(0.07, 0.17, 0.18, 1.0);   // цвет толщи воды
uniform vec3 absorb = vec3(0.55, 0.2, 0.16);                              // поглощение, 1/м
uniform vec4 foam_color : source_color = vec4(0.93, 0.9, 0.84, 1.0);
uniform float ripple = 0.05;              // сила ряби в нормали
uniform float ripple_scale = 0.05;        // плотность мазков ряби, 1/м
uniform float flow_speed = 0.7;           // м/с на стремнине
uniform float refraction = 0.035;
uniform float roughness = 0.07;
uniform float shore_foam = 0.32;          // глубина, до которой у берега пена, м
uniform float ford_foam = 1.0;
uniform float glint_power = 350.0;
uniform float glint = 6.0;

varying vec2 v_flow;
varying float v_speed;
varying float v_ford;

void vertex() {
	PAINT_VERTEX;
	v_flow = normalize(COLOR.rg * 2.0 - 1.0 + vec2(1e-4));
	v_speed = COLOR.b;
	v_ford = COLOR.a;
}

// Мазки ряби, вытянутые по течению; две фазы, чтобы текстура «текла» без рывка
float flow_strokes(vec2 p, vec2 f, vec2 perp, float t, float stretch) {
	vec2 q = vec2(dot(p, f), dot(p, perp));
	float ph = t * flow_speed * ripple_scale;
	float a = fract(ph);
	float b = fract(ph + 0.5);
	vec2 s = vec2(ripple_scale / stretch, ripple_scale);
	float h1 = texture(brush_tex, q * s - vec2(a, 0.0) + vec2(0.0, 0.31)).r;
	float h2 = texture(brush_tex, q * s - vec2(b, 0.0) + vec2(0.47, 0.0)).r;
	float w = abs(1.0 - 2.0 * a);
	return mix(h1, h2, 1.0 - w);
}

void fragment() {
	vec3 wp = v_world_pos;
	vec2 f = v_flow;
	vec2 perp = vec2(-f.y, f.x);
	float t = TIME * (0.4 + v_speed);

	// рябь: высота из мазков, нормаль из разностей
	float e = 0.6;
	float h0 = flow_strokes(wp.xz, f, perp, t, 6.0);
	float hx = flow_strokes(wp.xz + vec2(e, 0.0), f, perp, t, 6.0);
	float hz = flow_strokes(wp.xz + vec2(0.0, e), f, perp, t, 6.0);
	vec3 nw = normalize(vec3(-(hx - h0) * ripple / e * 3.0, 1.0, -(hz - h0) * ripple / e * 3.0));
	// мелкая рябь на перекате
	float h_fine = flow_strokes(wp.xz * 3.1, f, perp, t * 2.0, 2.5);
	nw = normalize(nw + vec3(perp.x, 0.0, perp.y) * (h_fine - 0.5) * 0.08 * (0.2 + v_ford));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);

	// глубина: толщина воды вдоль луча и по вертикали
	float d_raw = texture(depth_tex, SCREEN_UV).r;
	vec4 vp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d_raw, 1.0);
	vec3 scene_view = vp.xyz / vp.w;
	float thick = max(-scene_view.z - (-VERTEX.z), 0.0);
	vec3 scene_world = (INV_VIEW_MATRIX * vec4(scene_view, 1.0)).xyz;
	float vdepth = max(wp.y - scene_world.y, 0.0);

	// преломление: сдвиг по ряби, но не на предметы перед водой
	vec2 ruv = SCREEN_UV + nw.xz * refraction * clamp(vdepth, 0.0, 1.0);
	float d2 = texture(depth_tex, ruv).r;
	vec4 vp2 = INV_PROJECTION_MATRIX * vec4(ruv * 2.0 - 1.0, d2, 1.0);
	if (-vp2.z / vp2.w < -VERTEX.z) {
		ruv = SCREEN_UV;
	}
	vec3 bed = textureLod(screen_tex, ruv, 0.0).rgb;
	vec3 T = exp(-absorb * thick);
	vec3 water = bed * T + scatter_color.rgb * (1.0 - T);

	// пена: у берега — тонкая кромка мазками, на перекате брода — штрихи по течению
	float st = flow_strokes(wp.xz * 1.7, f, perp, t * 1.5, 5.0);
	float st2 = texture(brush_tex, wp.xz * 0.45 + vec2(0.2, 0.6)).r;
	float shore = smoothstep(shore_foam, 0.02, vdepth) * smoothstep(0.42, 0.62, st + st2 * 0.3);
	float riffle = v_ford * v_speed * smoothstep(0.62, 0.78, st) * smoothstep(0.9, 0.2, vdepth) * ford_foam;
	float foam = clamp(shore * 0.85 + riffle, 0.0, 1.0);

	ALBEDO = foam_color.rgb * foam;
	EMISSION = water * (1.0 - foam);
	ROUGHNESS = mix(roughness, 0.95, foam);
	SPECULAR = mix(0.36, 0.1, foam);
	METALLIC = 0.0;
	// мягкая кромка у самого берега
	ALPHA = smoothstep(0.0, 0.06, thick);
	paint_brush_v = st2;
}

void light() {
	// пена освещается как живописная поверхность
	DIFFUSE_LIGHT += paint_diffuse(NORMAL, LIGHT, LIGHT_COLOR, ATTENUATION, paint_brush_v, LIGHT_IS_DIRECTIONAL);
	// солнечная дорожка: блики, разбитые мазком
	vec3 H = normalize(LIGHT + VIEW);
	float sp = pow(max(dot(NORMAL, H), 0.0), glint_power);
	float br = smoothstep(0.45, 0.75, paint_brush_v);
	SPECULAR_LIGHT += LIGHT_COLOR * sp * glint * (0.35 + br) * ATTENUATION;
}
