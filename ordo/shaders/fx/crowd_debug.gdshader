// Запасная толпа боя (scripts/battle/debug_layer.gd): простые фигуры из жёстких частей,
// анимация в вершинах по AnimSpec (INSTANCE_CUSTOM: состояние, фаза, доп., вариант).
// Заменяется настоящей толпой (shaders/crowd.gdshader), когда она появится в проекте.
//
// Части меша: UV2.x — номер части, UV — точка вращения части (y, z) в осях модели.
// Цвет вершины: rgb — цвет/тень, a — класс: 1 свой цвет, 0.75 цвет стороны, 0.5 светлый
// цвет стороны, 0.25 масть коня, 0 кожа.
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

#include "res://shaders/include/painterly.gdshaderinc"

uniform int skeleton = 0;             // 0 человек, 1 всадник, 2 овца, 3 конь
uniform vec4 side_main : source_color = vec4(0.69, 0.22, 0.18, 1.0);
uniform vec4 side_light : source_color = vec4(1.0, 0.65, 0.59, 1.0);
uniform float model_height = 1.9;
uniform float rim_strength = 1.4;

varying vec3 v_col;
varying float v_cls;
varying float v_h;
varying float v_var;

const float TAU_ = 6.28318530718;

vec3 rot_x(vec3 p, float a) {
	float c = cos(a), s = sin(a);
	return vec3(p.x, p.y * c - p.z * s, p.y * s + p.z * c);
}

vec3 rot_z(vec3 p, float a) {
	float c = cos(a), s = sin(a);
	return vec3(p.x * c - p.y * s, p.x * s + p.y * c, p.z);
}

// вращение вокруг оси X с точкой опоры (y, z)
void pivot_x(inout vec3 v, inout vec3 n, vec2 piv, float a) {
	vec3 o = vec3(0.0, piv.x, piv.y);
	v = rot_x(v - o, a) + o;
	n = rot_x(n, a);
}

void human(inout vec3 v, inout vec3 n, int part, vec2 piv, int st, float ph, float aux, float var) {
	float cyc = ph * TAU_;
	float swing = 0.0, bob = 0.0, lean = 0.0;
	float weapon = 0.0; // 0 — на плече (вверх), 1.57 — вперёд (прицел)
	float breathe = sin((ph + var) * TAU_) * 0.012;
	if (st == 1) { swing = 0.42; bob = 0.035; weapon = 0.12; }
	else if (st == 2 || st == 8) { swing = 0.75; bob = 0.07; lean = 0.18; weapon = st == 8 ? 0.9 : 0.35; }
	else if (st == 4) {
		// вскидка, выстрел на 0.55, отдача
		float up = smoothstep(0.05, 0.38, ph) * (1.0 - smoothstep(0.82, 1.0, ph));
		float kick = exp(-max(ph - 0.55, 0.0) * 30.0) * step(0.55, ph);
		weapon = 1.5 * up - kick * 0.35;
		lean = -kick * 0.08 + up * 0.04;
	}
	else if (st == 5) { weapon = 0.35 + 0.08 * sin(ph * TAU_ * 9.0); lean = 0.05; }
	else if (st == 3) { weapon = 0.4 + 1.3 * sin(clamp(ph, 0.0, 1.0) * 3.14159); lean = 0.12 * sin(ph * 3.14159); }
	else if (st == 9) { weapon = -0.45 + 0.25 * sin(ph * TAU_ * 3.0); bob = 0.05 * abs(sin(ph * TAU_ * 2.0)); }
	else if (st == 10) { weapon = 0.8 + 0.7 * sin(cyc * 2.0); lean = 0.25; swing = aux > 0.7 ? 0.42 : 0.0; }
	else if (st == 11) { weapon = 1.2; lean = 0.1; }
	if (part == 1) pivot_x(v, n, piv, swing * sin(cyc));
	if (part == 2) pivot_x(v, n, piv, -swing * sin(cyc));
	if (part == 3 || part == 4) pivot_x(v, n, piv, weapon);
	if (part == 4) {
		// знамя на ветру: полотнище волной
		float w = max(v.z + 0.0, 0.0);
		v.x += sin(TIME * 5.0 + v.z * 4.0 + var * 9.0) * 0.12 * w;
	}
	if (part != 1 && part != 2) v.y += breathe;
	v.y += bob * abs(sin(cyc));
	v = rot_x(v, lean);
	n = rot_x(n, lean);
}

void horse_legs(inout vec3 v, inout vec3 n, int part, vec2 piv, int st, float ph) {
	float cyc = ph * TAU_;
	float amp = 0.0;
	vec4 off = vec4(0.0);
	if (st == 1) { amp = 0.35; off = vec4(0.25, 0.75, 0.0, 0.5); }
	else if (st == 2) { amp = 0.55; off = vec4(0.0, 0.5, 0.5, 0.0); }
	else if (st == 3 || st == 4) { amp = 0.85; off = vec4(0.31, 0.43, 0.0, 0.12); }
	if (part >= 1 && part <= 4) {
		float o = part == 1 ? off.x : part == 2 ? off.y : part == 3 ? off.z : off.w;
		pivot_x(v, n, piv, amp * sin(cyc - o * TAU_));
	}
}

void rider(inout vec3 v, inout vec3 n, int part, vec2 piv, int st, float ph, float aux, float var, bool mounted) {
	float cyc = ph * TAU_;
	horse_legs(v, n, part, piv, st, ph);
	float bob = 0.0, pitch = 0.0;
	if (st == 1) bob = 0.03;
	else if (st == 2) bob = 0.07;
	else if (st == 3 || st == 4) { bob = 0.12; pitch = 0.06 * sin(cyc); }
	// копьё: 0 — вверх (покой), 1.48 — наперевес
	float lance = 0.18;
	if (st == 4) lance = 1.5;
	else if (st == 5) lance = 0.9 + 0.6 * sin(clamp(ph, 0.0, 1.0) * 3.14159);
	else if (st == 9) lance = -0.12 + 0.12 * sin(ph * TAU_ * 3.0);
	else if (st == 3) lance = 0.35;
	if (part == 6 || part == 7) pivot_x(v, n, piv, lance);
	if (part == 7) v.x += sin(TIME * 6.0 + v.z * 3.0 + var * 7.0) * 0.1 * max(v.y - 2.5, 0.0);
	if (part == 5 || part == 6 || part == 7) {
		// всадник качается в седле
		v.y += bob * 0.6 * sin(cyc * 2.0 + 0.6);
	}
	if (part != 1 && part != 2 && part != 3 && part != 4) v.y += bob * abs(sin(cyc));
	if (st == 9) {
		// клич: конь поднимается на дыбы
		float r = sin(clamp(ph, 0.0, 1.0) * 3.14159) * 0.35;
		vec3 o = vec3(0.0, 0.0, -0.9);
		v = rot_x(v - o, -r) + o;
		n = rot_x(n, -r);
	}
	vec3 o2 = vec3(0.0, 1.2, 0.0);
	v = rot_x(v - o2, pitch) + o2;
	n = rot_x(n, pitch);
}

void sheep(inout vec3 v, inout vec3 n, int part, vec2 piv, int st, float ph, float var) {
	float cyc = ph * TAU_;
	float amp = st == 1 ? 0.4 : st == 2 ? 0.7 : 0.0;
	if (part >= 1 && part <= 4) {
		float o = (part == 1 || part == 4) ? 0.0 : 0.5;
		pivot_x(v, n, piv, amp * sin(cyc + o * TAU_));
	}
	if (part == 5) {
		// пасётся: голова к земле, жуёт
		float down = st == 0 ? 0.9 + 0.08 * sin(TIME * 3.0 + var * 20.0) : 0.1;
		pivot_x(v, n, piv, down);
	}
	v.y += (st == 2 ? 0.06 : st == 1 ? 0.02 : 0.0) * abs(sin(cyc));
}

void vertex() {
	int st = int(INSTANCE_CUSTOM.x + 0.5);
	float ph = INSTANCE_CUSTOM.y;
	float aux = INSTANCE_CUSTOM.z;
	float var = INSTANCE_CUSTOM.w;
	int part = int(UV2.x + 0.5);
	vec2 piv = UV;
	vec3 v = VERTEX;
	vec3 n = NORMAL;
	v_h = clamp(VERTEX.y / model_height, 0.0, 1.0);
	// рост ±4 %
	float sc = 0.96 + 0.08 * fract(var * 7.31);
	bool dying = false;
	float fall = 0.0;
	if (skeleton == 0) {
		dying = st == 6 || st == 7;
		if (!dying) human(v, n, part, piv, st, ph, aux, var);
		fall = st == 7 ? 1.0 : st == 6 ? ph : 0.0;
	} else if (skeleton == 1 || skeleton == 3) {
		dying = st == 6 || st == 7;
		if (!dying) rider(v, n, part, piv, st, ph, aux, var, skeleton == 1);
		fall = st == 7 ? 1.0 : st == 6 ? ph : 0.0;
	} else {
		dying = st == 3 || st == 4;
		if (!dying) sheep(v, n, part, piv, st, ph, var);
		fall = st == 4 ? 1.0 : st == 3 ? ph : 0.0;
	}
	if (dying) {
		// ноги подкашиваются, тело валится на бок
		float p = smoothstep(0.0, 1.0, fall);
		float sgn = aux > 0.5 ? 1.0 : -1.0;
		float lie = p * p * 1.45 * sgn;
		float knees = smoothstep(0.0, 0.5, fall);
		v.y *= mix(1.0, 0.82, knees);
		v = rot_z(v, lie);
		n = rot_z(n, lie);
		v.y -= p * 0.12;
		if (skeleton == 0) {
			v = rot_x(v, -p * 0.25);
			n = rot_x(n, -p * 0.25);
		}
	}
	VERTEX = v * sc;
	NORMAL = n;
	v_col = COLOR.rgb;
	v_cls = COLOR.a;
	v_var = var;
	PAINT_VERTEX;
}

void fragment() {
	vec3 c = v_col;
	if (v_cls > 0.62 && v_cls < 0.9) {
		c = side_main.rgb * c * (0.9 + 0.2 * fract(v_var * 3.7));
	} else if (v_cls > 0.37 && v_cls <= 0.62) {
		c = side_light.rgb * c;
	} else if (v_cls > 0.12 && v_cls <= 0.37) {
		// масть: гнедая, рыжая, серая, вороная
		float k = fract(v_var * 5.13);
		vec3 coat = k < 0.35 ? vec3(0.42, 0.25, 0.15) : k < 0.6 ? vec3(0.55, 0.3, 0.15)
			: k < 0.82 ? vec3(0.65, 0.62, 0.57) : vec3(0.2, 0.16, 0.14);
		c = pow(coat, vec3(2.2)) * c;
	} else if (v_cls <= 0.12) {
		c = pow(mix(vec3(0.72, 0.52, 0.4), vec3(0.55, 0.36, 0.26), fract(v_var * 9.7)), vec3(2.2)) * c;
	}
	// нарисованная тень: низ темнее и холоднее, верх светлее
	c *= mix(vec3(0.62, 0.66, 0.78), vec3(1.06, 1.02, 0.97), smoothstep(0.0, 0.85, v_h));
	ALBEDO = c;
	ROUGHNESS = 0.85;
	// мазок мягче, чем на зданиях: мелкие фигуры не должны рябить
	paint_brush_v = mix(0.5, paint_brush(v_world_pos, v_world_nrm), 0.45);
}

void light() {
	PAINT_LIGHT(rim_strength);
}
