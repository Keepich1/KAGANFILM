// Заместители построек «Города» (VIEW): пока у здания нет своей модели, BuildingLook собирает его
// из простых частей — один меш, один материал на все заместители (мало вызовов отрисовки).
// Тот же живописный свет, что у зданий (painterly.gdshaderinc), тот же атлас лагеря кыпчаков.
//
// Вершины:
//   UV       — координаты внутри области атласа в повторах (могут быть > 1: область повторяется)
//   CUSTOM0  — область атласа (x0, y0, w, h) в долях; w = 0 — узор изразца (кокандская кашин-плитка)
//   COLOR    — rgb: оттенок; a: 1 — обычная часть, 0 — часть лесов/разметки стройки (видна только у стройки)
//
// Стройка и руина (экземпляр): clip_h — выше этой высоты над основанием ничего нет (стройка растёт
// снизу); scorch 0..1 — копоть и выгорание (руина, пожар).
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

#include "res://shaders/include/painterly.gdshaderinc"

uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float rim_strength = 1.0;
uniform float roughness = 0.9;
uniform vec3 tile_a : source_color = vec3(0.12, 0.62, 0.62);   // бирюза
uniform vec3 tile_b : source_color = vec3(0.93, 0.9, 0.8);     // белый ганч
uniform vec3 tile_c : source_color = vec3(0.12, 0.2, 0.52);    // кобальт
uniform float tile_size = 0.9;                                  // м на звезду
uniform vec3 cut_col : source_color = vec3(0.86, 0.7, 0.52);   // срез стройки: свежая глина / сруб

instance uniform float clip_h = 100000.0;
instance uniform float scorch = 0.0;
instance uniform float site = 0.0;
instance uniform float wet = -1.0;        // поле: 1 — полив (сочная зелень), 0 — «лалми» (сухо), −1 — не поле

varying vec4 v_region;
varying float v_kind;
varying float v_local_y;
varying float v_veg;

void vertex() {
	v_region = CUSTOM0;
	v_kind = COLOR.a;
	v_local_y = VERTEX.y;
	v_veg = step(COLOR.r + 0.15, COLOR.g);
	PAINT_VERTEX;
}

// Восьмиконечная звезда (гирих) в клетке: 1 — звезда, 0 — фон
float star8(vec2 p) {
	vec2 q = abs(fract(p) - 0.5);
	float sq = max(q.x, q.y);
	float dia = (q.x + q.y) * 0.7071;
	return 1.0 - smoothstep(0.27, 0.3, max(sq, dia) * 0.92);
}

void fragment() {
	if (v_local_y > clip_h || (v_kind < 0.5 && site < 0.5)) {
		discard;
	}
	if (!FRONT_FACING) {
		// изнанка видна только сквозь срез стройки или руины: рисуем её как плоский срез стены
		if (clip_h > 1000.0) {
			discard;
		}
		ALBEDO = cut_col * (0.9 + 0.2 * paint_vnoise(v_world_pos.xz * 1.7)) * mix(1.0, 0.35, scorch);
		NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
		ROUGHNESS = 1.0;
		paint_brush_v = paint_brush(v_world_pos, vec3(0.0, 1.0, 0.0));
	} else {
	vec3 a;
	if (v_region.z > 0.0) {
		vec2 uv = v_region.xy + fract(UV) * v_region.zw;
		// без шва на границе повтора: производные от непрерывных UV
		vec2 g = UV * v_region.zw;
		a = textureGrad(albedo_tex, uv, dFdx(g), dFdy(g)).rgb;
	} else {
		vec2 p = UV / tile_size;
		float s = star8(p);
		float cross = star8(p + 0.5);
		a = mix(tile_c, tile_a, s);
		a = mix(a, tile_b, cross * (1.0 - s) * 0.85);
		// швы между плитками
		vec2 gq = abs(fract(p * 2.0) - 0.5);
		a *= 0.82 + 0.18 * smoothstep(0.46, 0.43, max(gq.x, gq.y));
	}
	a *= COLOR.rgb;
	if (wet >= 0.0) {
		// всходы: полив — сочнее и темнее, сухое поле — жёлтое, редкое
		vec3 lush = a * vec3(0.62, 1.08, 0.52);
		vec3 dry = a * vec3(1.32, 1.08, 0.6);
		a = mix(a, mix(dry, lush, wet), v_veg);
	}
	// копоть: темнее и холоднее сверху вниз пятнами
	float n = paint_vnoise(v_world_pos.xz * 0.9 + v_world_pos.y * 0.6);
	a = mix(a, a * vec3(0.32, 0.29, 0.27), clamp(scorch * (0.6 + 0.6 * n), 0.0, 1.0));
	// свежая кромка стройки чуть светлее (сырая глина / свежий срез)
	if (clip_h < 1000.0) {
		a *= 1.0 + 0.25 * smoothstep(clip_h - 0.35, clip_h, v_local_y);
	}
	ALBEDO = a;
	ROUGHNESS = roughness;
	paint_brush_v = paint_brush(v_world_pos, v_world_nrm);
	}
}

void light() {
	PAINT_LIGHT(rim_strength);
}
