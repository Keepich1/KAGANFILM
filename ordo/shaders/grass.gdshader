// Степная трава и ковыль (ТЗ 11.1: «пух ковыля», 11.4: трава на ветру).
// Пучки расставляет сам шейдер: номер экземпляра → место в участке (сетка с разбросом),
// высота земли — из текстуры высот, густота/рост/доля ковыля — из карты травы.
// Ости ковыля развёрнуты по ветру (ordo_wind) и светятся серебром в контражуре.
// По полю бегут волны ветра. Свет — общий живописный (painterly.gdshaderinc).
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

#include "res://shaders/include/painterly.gdshaderinc"

global uniform vec4 ordo_wind;           // xy — направление (x, z), z — сила, w — порывистость

uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform sampler2D grass_map : hint_default_black, filter_linear_mipmap, repeat_disable;
uniform sampler2D splat_map : hint_default_black, filter_linear_mipmap, repeat_disable;
uniform vec2 height_origin = vec2(-512.0);
uniform float height_size = 513.0;
uniform float height_spacing = 2.0;
uniform float map_half = 512.0;

uniform float patch_size = 12.0;
uniform int grid_n = 21;
uniform float clump_scale = 1.0;
uniform vec4 fade = vec4(-1.0, 0.0, 60.0, 80.0);   // от камеры: появление (от, до), исчезание (от, до)
uniform float density_comp = 1.0;                  // при прореживании пучки чуть крупнее
uniform vec4 clearings[48];                        // поляны без травы: (x, z, радиус, 1)
uniform int clearing_count = 0;
// «Город» (VIEW, FieldView): маска травы R8 по карте — 0 под постройками и полями, иначе трава 0..1
// (вытоптанные пастбища реже и ниже). Срез её не включает.
uniform bool use_city_mask = false;
uniform sampler2D city_mask : hint_default_white, filter_linear, repeat_disable;

group_uniforms colors;
uniform vec4 base_color : source_color = vec4(0.17, 0.19, 0.11, 1.0);
uniform vec4 mid_color : source_color = vec4(0.33, 0.36, 0.2, 1.0);
uniform vec4 tip_color : source_color = vec4(0.5, 0.5, 0.29, 1.0);
uniform vec4 cool_tip : source_color = vec4(0.4, 0.47, 0.37, 1.0);
uniform vec4 dry_tip : source_color = vec4(0.68, 0.57, 0.34, 1.0);
uniform vec4 plume_color : source_color = vec4(0.84, 0.81, 0.72, 1.0);
uniform vec4 plume_glow : source_color = vec4(1.0, 0.86, 0.64, 1.0);
group_uniforms;

uniform float min_height = 0.14;
uniform float max_height = 0.8;
uniform float wind_bend = 0.4;
uniform float translucency = 0.55;
uniform float plume_glow_strength = 2.6;
uniform float rim_strength = 0.35;
// Насколько нормаль листа загнута вверх (1 — пучок как купол, 0 — как отдельные листья)
uniform float normal_up = 0.4;

varying vec3 v_color;
varying float v_plume;
varying float v_t;

// Четыре независимых случайных числа по целой клетке (без корреляции соседей)
vec4 hash4(vec2 p) {
	vec4 p4 = fract(vec4(p.xyxy) * vec4(0.1031, 0.1030, 0.0973, 0.1099));
	p4 += dot(p4, p4.wzxy + 33.33);
	return fract((p4.xxyz + p4.yzzw) * p4.zywx);
}

void vertex() {
	vec3 origin = NODE_POSITION_WORLD;
	int gx = INSTANCE_ID % grid_n;
	int gz = INSTANCE_ID / grid_n;
	float cell = patch_size / float(grid_n);
	// ключ привязан к миру: пучок не «плывёт», когда участки сдвигаются за камерой
	vec2 key = floor(origin.xz + 0.5) * 3.0 + vec2(float(gx), float(gz));
	vec4 ha = hash4(key);
	vec4 hb = hash4(key + vec2(113.0, 271.0));
	float h1 = ha.x;
	float h2 = ha.y;
	float h3 = ha.z;
	float h4 = ha.w;
	float h5 = hb.x;
	float h6 = hb.y;
	float h7 = hb.z;
	vec2 wxz = origin.xz + (vec2(float(gx), float(gz)) + vec2(h1, h2)) * cell;

	vec2 muv = (wxz + vec2(map_half)) / (2.0 * map_half);
	vec4 gm = textureLod(grass_map, muv, 0.0);
	vec4 sp = textureLod(splat_map, muv, 0.0);
	float inside = step(abs(wxz.x), map_half) * step(abs(wxz.y), map_half);
	vec2 huv = ((wxz - height_origin) / height_spacing + 0.5) / height_size;
	float gy = textureLod(height_tex, huv, 0.0).r;

	float dist = distance(vec3(wxz.x, gy, wxz.y), CAMERA_POSITION_WORLD);
	float vis = smoothstep(fade.x, fade.y, dist) * (1.0 - smoothstep(fade.z, fade.w, dist));
	// редкие одиночные пучки на вытоптанной земле читаются как «рассада» — там травы нет вовсе
	float keep = step(h3, gm.r * inside * 1.05) * step(0.26, gm.r) * (1.0 - smoothstep(0.3, 0.55, sp.g));
	for (int i = 0; i < clearing_count; i++) {
		vec4 c = clearings[i];
		if (distance(wxz, c.xy) < c.z) {
			keep = 0.0;
		}
	}
	float height = mix(min_height, max_height, gm.g) * (0.5 + 1.0 * h4 * h4 + 0.2 * h6) * clump_scale * density_comp;
	if (use_city_mask) {
		float cm = textureLod(city_mask, muv, 0.0).r;
		keep *= step(0.06, cm) * step(h6 * 0.85, cm + 0.08);
		height *= mix(0.45, 1.0, cm);
	}
	float is_plume = COLOR.r;
	float kov = step(h5, gm.b * 1.1);
	// у каждого пучка своё число остей: часть остей прячется
	float plume_keep = step(COLOR.b, 0.25 + 0.75 * h7);
	float scale = keep * vis * mix(1.0, kov * plume_keep, is_plume);

	// поворот пучка; ости — по ветру
	vec2 wdir = normalize(ordo_wind.xy + vec2(1e-4));
	float yaw = h1 * 6.2832 + h2 * 3.0;
	float wyaw = atan(wdir.y, wdir.x) + (h6 - 0.5) * 1.3 + (COLOR.b - 0.5) * 0.6;
	float ang = mix(yaw, wyaw, is_plume);
	float ca = cos(ang);
	float sa = sin(ang);
	vec3 v = VERTEX;
	v.xz = vec2(v.x * ca - v.z * sa, v.x * sa + v.z * ca);
	vec3 n = NORMAL;
	n.xz = vec2(n.x * ca - n.z * sa, n.x * sa + n.z * ca);
	float spread = 0.6 + 0.8 * h2;
	// наклон всего пучка
	v.xz += v.y * (vec2(h3, h7) - 0.5) * 0.5;
	v *= vec3(height * spread, height, height * spread);

	// ветер: изгиб к кончику, бегущие волны порывов, мелкая дрожь
	float t = COLOR.g;
	float bend = t * t;
	float wave = sin(dot(wxz, wdir) * 0.085 - TIME * (1.1 + ordo_wind.w * 1.6) + h1 * 0.6) * 0.5 + 0.5;
	wave *= wave;
	float flutter = sin(TIME * (2.6 + h3) + h1 * 6.28 + t * 2.5) * 0.06;
	float push = ordo_wind.z * wind_bend * (0.3 + 0.9 * wave) + flutter;
	v.xz += wdir * push * bend * height * (1.0 + is_plume * 0.6);
	v.y -= abs(push) * bend * height * 0.3;
	v *= scale;
	VERTEX = vec3(wxz.x, gy, wxz.y) + v - origin;
	// нормаль почти вверх: пучок затеняется как объём, а не как отдельные листья
	NORMAL = normalize(mix(n, vec3(0.0, 1.0, 0.0), normal_up));
	PAINT_VERTEX;

	// цвет: тёмное основание → светлый кончик; сухие места — соломенные кончики
	vec3 c = mix(base_color.rgb, mid_color.rgb, smoothstep(0.0, 0.5, t));
	vec3 tip = mix(tip_color.rgb, cool_tip.rgb, smoothstep(0.4, 1.0, h2));
	tip = mix(tip, dry_tip.rgb, clamp(sp.r * 1.2 + h5 * 0.25 - 0.1, 0.0, 1.0));
	c = mix(c, tip, smoothstep(0.45, 1.0, t));
	c *= 0.7 + 0.45 * h4 * h2;
	// гребень волны ветра чуть светлее — по полю бегут световые волны
	c *= 1.0 + wave * 0.12 * t;
	vec3 pc = plume_color.rgb * (0.9 + 0.2 * h3);
	pc = mix(mid_color.rgb, pc, smoothstep(0.15, 0.5, t));
	// вдали ости ковыля сливаются с травой: светлые метёлки иначе читаются как «сор» по полю
	float cam_d = length(vec3(wxz.x, gy, wxz.y) - CAMERA_POSITION_WORLD);
	float look_down = clamp((CAMERA_POSITION_WORLD.y - gy) / max(cam_d, 0.1), 0.0, 1.0);
	float plume_k = is_plume * (1.0 - 0.8 * smoothstep(18.0, 55.0, cam_d)) * (1.0 - 0.7 * smoothstep(0.35, 0.75, look_down));
	v_color = mix(c, pc, plume_k);
	v_plume = plume_k;
	v_t = t;
}

void fragment() {
	ALBEDO = v_color;
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
	// обе стороны листа затеняются одинаково (нормаль уже согнута вверх)
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	paint_brush_v = paint_brush(v_world_pos, v_world_nrm);
}

void light() {
	DIFFUSE_LIGHT += paint_diffuse(NORMAL, LIGHT, LIGHT_COLOR, PAINT_ATTEN, paint_brush_v, LIGHT_IS_DIRECTIONAL);
	float back = clamp(dot(LIGHT, -VIEW), 0.0, 1.0);
	// просвет листьев против солнца
	DIFFUSE_LIGHT += LIGHT_COLOR * pow(back, 4.0) * translucency * v_t * PAINT_ATTEN / PI;
	// ости ковыля — серебристо-золотое свечение в контражуре
	SPECULAR_LIGHT += plume_glow.rgb * LIGHT_COLOR * pow(back, 3.0) * v_plume * smoothstep(0.2, 0.8, v_t)
		* plume_glow_strength * PAINT_ATTEN / PI;
	SPECULAR_LIGHT += paint_rim(NORMAL, LIGHT, VIEW, LIGHT_COLOR, PAINT_ATTEN, rim_strength) * v_t;
}
