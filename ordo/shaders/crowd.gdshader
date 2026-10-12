// Толпа Ордо: все юниты среза одним шейдером (CONTRACT §7, ТЗ 11.4–11.5).
//
// Юнит — экземпляр MultiMesh, меш из жёстких частей (UV2.x — номер кости, UV2.y — вес
// вторичного движения). Вся анимация — здесь, в vertex(), по INSTANCE_CUSTOM (AnimSpec):
//   x состояние, y фаза 0..1, z доп. значение, w вариант юнита.
// Тени считаются по тем же анимированным вершинам (VERTEX меняется в vertex()).
// Свет общий, живописный (painterly.gdshaderinc) + подъём яркости юнитов над землёй (ТЗ 11.2).
//
// Маски в цвете вершин: r — нарисованная тень, g — цвет стороны, b — вариант по атласу, a — металл.
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

// Скелет и оружие слоя (задаёт CrowdLayer по UnitRegistry)
uniform int skeleton = 0;          // 0 человек, 1 конь со всадником, 2 овца, 3 конь
uniform int weapon_kind = 0;       // 0 ружьё, 1 сабля, 2 копьё, 3 меч, 4 булава, 5 посох, 6 нет
uniform int item_kind = 0;         // 0 нет, 1 щит, 2 шомпол, 3 мешок
uniform bool has_banner = false;   // в правой руке древко знамени

uniform sampler2D atlas : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float variant_du = 0.25;   // шаг вариантов по атласу (масть, шапки, шерсть)
uniform int variant_count = 4;
uniform float jitter = 1.0;        // разброс оттенков одежды по w
uniform float height_jitter = 0.04;
uniform float unit_lift = 0.14;    // юниты светлее земли (ТЗ 11.2)
uniform float unit_sat = 0.22;     // и насыщеннее
uniform float rim_strength = 1.7;  // контровой свет сильнее, чем у зданий
uniform float brush_scale = 2.6;   // мазки на теле юнита (в осях модели — не «плывут»)

global uniform vec4 ordo_wind;     // xy — направление ветра (x, z), z — сила, w — порывистость

#include "res://shaders/include/painterly.gdshaderinc"
#include "res://shaders/include/crowd_common.gdshaderinc"
#include "res://shaders/include/crowd_skeletons.gdshaderinc"
#include "res://shaders/include/crowd_human.gdshaderinc"
#include "res://shaders/include/crowd_horse.gdshaderinc"
#include "res://shaders/include/crowd_sheep.gdshaderinc"

varying vec3 v_tint;
varying float v_side;
varying float v_metal;
varying vec3 v_body_pos;
varying vec3 v_body_nrm;
varying float v_metal_f;

void vertex() {
	vec4 ic = INSTANCE_CUSTOM;
	int st = int(ic.x + 0.5);
	float ph = ic.y;
	float aux = ic.z;
	float var = ic.w;
	int part = int(UV2.x + 0.5);
	float wgt = UV2.y;
	float t = TIME + var * 97.0;
	vec3 rest = VERTEX;

	// ветер в осях модели (экземпляр повёрнут по ходу юнита)
	mat3 inst = mat3(MODEL_MATRIX);
	float sc2 = max(dot(inst[0], inst[0]), 1e-6);
	float gust = 0.55 + 0.45 * noise1(TIME * 0.4 + var * 3.0);
	vec3 wind_w = vec3(ordo_wind.x, 0.0, ordo_wind.y) * ordo_wind.z * 6.0 * mix(1.0, gust, ordo_wind.w);
	vec3 wind_m = transpose(inst) * wind_w / sc2;

	vec3 v = VERTEX;
	Xf X;
	if (skeleton == 0) {
		HPose p = human_pose(st, ph, aux, var, t);
		X = human_bone(part, p, v, wgt, wind_m - vec3(0.0, 0.0, p.speed), t, var);
	} else if (skeleton == 2) {
		SPose p = sheep_pose(st, ph, aux, var, t);
		X = sheep_bone(part, p, v, wgt, t, var);
	} else {
		RPose p = rider_pose(st, ph, aux, var, t);
		X = rider_bone(part, p, v, wgt, wind_m - vec3(0.0, 0.0, p.speed), t, var);
	}
	VERTEX = xf_pt(X, v);
	vec3 n = X.b * NORMAL;
	NORMAL = dot(n, n) > 1e-10 ? normalize(n) : NORMAL;

	// рост ±4% (по варианту)
	VERTEX *= 1.0 + height_jitter * (hash11(var * 7.31) * 2.0 - 1.0);

	// вариант по атласу: b = 1 — масть/шерсть, b = 0.5 — шапка (разные выборки)
	if (COLOR.b > 0.25) {
		float h = hash11(var * (COLOR.b > 0.75 ? 3.71 : 8.29));
		UV.x += floor(h * float(variant_count) * 0.9999) * variant_du;
	}
	// разброс оттенков одежды (не трогает цвет стороны)
	float h1 = hash11(var * 5.13);
	float h2 = hash11(var * 9.71);
	float h3 = hash11(var * 2.39);
	v_tint = vec3(1.0) + jitter * (vec3(h1, h2, h3) - 0.5) * 0.12 + jitter * (hash11(var * 1.7) - 0.5) * 0.16;
	v_side = COLOR.g;
	v_metal = COLOR.a;
	v_body_pos = rest * brush_scale + vec3(var * 13.0, var * 7.0, 0.0);
	v_body_nrm = NORMAL;
	PAINT_VERTEX;
}

void fragment() {
	vec3 a = texture(atlas, UV).rgb;
	a *= COLOR.r;
	a = mix(a * v_tint, a, v_side);
	float l = dot(a, vec3(0.299, 0.587, 0.114));
	a = mix(vec3(l), a, 1.0 + unit_sat);
	a *= 1.0 + unit_lift;
	ALBEDO = clamp(a, vec3(0.0), vec3(1.0));
	ROUGHNESS = mix(0.9, 0.45, v_metal);
	paint_brush_v = paint_brush(v_body_pos, v_body_nrm);
	v_metal_f = v_metal;
}

void light() {
	PAINT_LIGHT(rim_strength);
	if (v_metal_f > 0.01) {
		// узкий тёплый блик на золоте и стали
		vec3 h = normalize(LIGHT + VIEW);
		SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * pow(max(dot(NORMAL, h), 0.0), 18.0) * v_metal_f * 0.45;
	}
}
