// Толпа: человек (skeleton 0). Состояния — AnimSpec.Human, данные экземпляра:
// x состояние, y фаза 0..1, z доп. значение, w вариант (scripts/units/anim_spec.gd).
//
// Поза собирается из целей: стопы (ИК ног), кисти (ИК рук), положение оружия.
// Оружие — отдельная часть: точка хвата HP_HAND_R, ось оружия +Y, «низ» приклада/лезвие +Z.
// Нужны uniform: weapon_kind, item_kind, has_banner (crowd.gdshader).

const int HS_IDLE = 0;
const int HS_WALK = 1;
const int HS_RUN = 2;
const int HS_MELEE = 3;
const int HS_SHOOT = 4;
const int HS_RELOAD = 5;
const int HS_DYING = 6;
const int HS_DEAD = 7;
const int HS_FLEE = 8;
const int HS_CHEER = 9;
const int HS_WORK = 10;
const int HS_BRACE = 11;

const int WK_MUSKET = 0;
const int WK_SABER = 1;
const int WK_LANCE = 2;
const int WK_SWORD = 3;
const int WK_MACE = 4;
const int WK_STAFF = 5;
const int WK_NONE = 6;

const int WK_TOOL = 7;              // работник с инструментами (UnitRegistry weapon "tool")

const int IK_NONE = 0;
const int IK_SHIELD = 1;
const int IK_RAMROD = 2;
const int IK_SACK = 3;

// Шаг (AnimSpec.STRIDE_HUMAN): цикл из двух шагов, метров
const float H_STRIDE_WALK = 1.5;
const float H_STRIDE_RUN = 2.6;
// Мешок на плече (точка в позе покоя, см. gen_units.sack)
const vec3 H_SACK_PT = vec3(-0.17, 1.58, -0.05);
// Инструменты работников — отдельные части (tools/gen_units_work.py), видна та, что нужна работе.
// Хват в правой кисти (HP_HAND_R) в позе покоя, ось инструмента +Y, лезвие/боёк в +Z.
// Бревно на плече держится за точку H_LOAD_PT. Невидимые сжимаются в точку (как оружие при бегстве).
// Номера частей — в crowd_skeletons.gdshaderinc (HUMAN_PARTS в gen_units_kit.py):
//   H_TOOL_AXE 17 топор: рубит (WORK, z = 0); H_TOOL_HOE 18 кетмень: копает (z = 0.25);
//   H_TOOL_HAMMER 19 молот / колотушка: строит (z = 0.5);
//   H_TOOL_LOAD 20 бревно на плече: несёт дерево (z = 0.875); мешок (z = 0.75) — часть ITEM
const vec3 H_LOAD_PT = vec3(-0.2, 1.565, -0.06);

struct HPose {
	vec3 root_rot;
	vec3 root_piv;
	vec3 root_off;
	vec3 pel_rot;
	vec3 pel_off;
	vec3 chest_rot;
	vec3 head_rot;
	vec3 foot_l;
	vec3 foot_r;
	vec3 knee_l;
	vec3 knee_r;
	vec3 hand_l;
	vec3 hand_r;
	vec3 elbow_l;
	vec3 elbow_r;
	mat3 w_rot;
	vec3 w_pos;
	float w_vis;
	mat3 i_rot;
	vec3 i_pos;
	float i_vis;
	float skirt;
	float flare;
	float speed;
	int t_part;      // видимый инструмент (H_TOOL_*), -1 — никакой
	mat3 t_rot;
	vec3 t_pos;
};

HPose hp_rest() {
	HPose p;
	p.root_rot = vec3(0.0);
	p.root_piv = vec3(0.0);
	p.root_off = vec3(0.0);
	p.pel_rot = vec3(0.0);
	p.pel_off = vec3(0.0);
	p.chest_rot = vec3(0.0);
	p.head_rot = vec3(0.0);
	p.foot_l = HP_ANKLE_L;
	p.foot_r = HP_ANKLE_R;
	p.knee_l = vec3(0.15, 0.0, 1.0);
	p.knee_r = vec3(-0.15, 0.0, 1.0);
	p.hand_l = HP_HAND_L;
	p.hand_r = HP_HAND_R;
	p.elbow_l = vec3(0.5, -0.2, -1.0);
	p.elbow_r = vec3(-0.5, -0.2, -1.0);
	p.w_rot = mat3(1.0);
	p.w_pos = HP_HAND_R;
	p.w_vis = 1.0;
	p.i_rot = mat3(1.0);
	p.i_pos = HP_HAND_R;
	p.i_vis = 0.0;
	p.skirt = 0.85;
	p.flare = 0.0;
	p.speed = 0.0;
	p.t_part = -1;
	p.t_rot = mat3(1.0);
	p.t_pos = HP_HAND_R;
	return p;
}

Xf hp_pel(HPose p) {
	return xf_piv(eul(p.pel_rot), HP_PELVIS, p.pel_off);
}

Xf hp_chest(HPose p) {
	return xf_mul(hp_pel(p), xf_piv(eul(p.chest_rot), HP_CHEST, vec3(0.0)));
}

Xf hp_root(HPose p) {
	return xf_piv(eul(p.root_rot), p.root_piv, p.root_off);
}

// Кисть при махе рукой (оси торса в покое): sw — вперёд, bend — сгиб локтя, outw — в сторону
vec3 h_arm(vec3 S, vec3 H, float sw, float bend, float outw) {
	vec3 d = (H - S) * (1.0 - 0.5 * bend);
	d = rot_x(-sw) * d;
	d.x += outw;
	d.z += 0.12 * bend;
	return S + d;
}

// Оружие по осям торса (следует за телом)
void hp_weapon_t(inout HPose p, Xf C, vec3 pos, vec3 dir, vec3 zref) {
	p.w_pos = xf_pt(C, pos);
	p.w_rot = basis_yz(C.b * dir, C.b * zref);
}

void hp_weapon_m(inout HPose p, vec3 pos, vec3 dir, vec3 zref) {
	p.w_pos = pos;
	p.w_rot = basis_yz(dir, zref);
}

// Точка на оружии на расстоянии along от хвата
vec3 hp_wp(HPose p, float along) {
	return p.w_pos + p.w_rot[1] * along;
}

// Смешивание двух положений оружия (по осям: позиция, ось, «низ»)
void hp_weapon_mix(inout HPose p, vec3 pos2, mat3 rot2, float k) {
	p.w_pos = mix(p.w_pos, pos2, k);
	p.w_rot = basis_yz(mix(p.w_rot[1], rot2[1], k), mix(p.w_rot[2], rot2[2], k));
}

// ---------------------------------------------------------------- ноги

// Цикл шага: левая стопа касается при ph = 0, правая при 0.5. run = 1 — бег (полёт, наклон).
void hp_gait(inout HPose p, float ph, float stride, float duty, float lift, float run) {
	vec2 fl = gait_foot(fract(ph), duty, stride, lift);
	vec2 fr = gait_foot(fract(ph + 0.5), duty, stride, lift);
	float zc = 0.03 + 0.06 * run;
	p.foot_l = vec3(0.09, HP_ANKLE_L.y + fl.y, zc + fl.x);
	p.foot_r = vec3(-0.09, HP_ANKLE_R.y + fr.y, zc + fr.x);
	// пятка отрывается в конце опоры — ступня перекатывается на носок
	float sl = fract(ph) / duty;
	float sr = fract(ph + 0.5) / duty;
	p.foot_l.y += 0.07 * smoothstep(0.6, 1.0, sl) * step(sl, 1.0);
	p.foot_r.y += 0.07 * smoothstep(0.6, 1.0, sr) * step(sr, 1.0);
	float a = TAU * ph;
	float mid = TAU * duty * 0.5;
	// таз: шаг — выше всего на середине опоры; бег — ниже всего (амортизация)
	float bob = cos(2.0 * (a - mid));
	p.pel_off.y = mix(-0.05 + 0.022 * bob, -0.1 - 0.035 * bob, run);
	p.pel_off.x = 0.022 * (1.0 - 0.5 * run) * cos(a - mid);
	p.pel_off.z = 0.03 * run;
	p.pel_rot.y = -0.11 * cos(a);
	p.pel_rot.z = 0.045 * cos(a - mid);
	p.pel_rot.x = 0.04 + 0.1 * run;
	// торс закручивается навстречу тазу, голова держит взгляд
	p.chest_rot.y = 0.17 * cos(a);
	p.chest_rot.x = 0.03 + 0.12 * run + 0.02 * bob;
	p.chest_rot.z = -0.03 * cos(a - mid);
	p.head_rot.y = -0.05 * cos(a);
	p.head_rot.x = -0.04 - 0.1 * run;
	p.skirt = 0.78;
	p.flare = 0.03 + 0.08 * run;
}

// Колени и голени в стойке: ступни на земле, таз ниже
void hp_stance(inout HPose p, vec3 fl, vec3 fr) {
	p.foot_l = vec3(fl.x, HP_ANKLE_L.y + fl.y, fl.z);
	p.foot_r = vec3(fr.x, HP_ANKLE_R.y + fr.y, fr.z);
}

// ---------------------------------------------------------------- руки при ходьбе

void hp_swing_arms(inout HPose p, Xf C, float ph, float amp, float bend, bool left, bool right) {
	float a = TAU * ph;
	if (left) {
		p.hand_l = xf_pt(C, h_arm(HP_SHOULDER_L, HP_HAND_L, -amp * cos(a), bend + 0.15 * max(-cos(a), 0.0), 0.03));
		p.elbow_l = C.b * vec3(0.4, -0.3, -1.0);
	}
	if (right) {
		p.hand_r = xf_pt(C, h_arm(HP_SHOULDER_R, HP_HAND_R, amp * cos(a), bend + 0.15 * max(cos(a), 0.0), -0.03));
		p.elbow_r = C.b * vec3(-0.4, -0.3, -1.0);
	}
}

// ---------------------------------------------------------------- ружьё

// Ружьё у плеча (марш): дуло вверх-назад над правым плечом
void musket_shoulder(inout HPose p, Xf C) {
	hp_weapon_t(p, C, vec3(-0.25, 1.0, 0.17), vec3(0.0, 0.955, -0.296), vec3(0.0, 0.3, 1.0));
	p.hand_r = hp_wp(p, 0.0);
	p.elbow_r = C.b * vec3(-0.6, -0.6, -0.4);
}

// «Порт»: наискось перед грудью, обе руки (готовность, после выстрела)
void musket_port(inout HPose p, Xf C) {
	hp_weapon_t(p, C, vec3(-0.13, 1.05, 0.28), vec3(0.5, 0.84, 0.16), vec3(0.0, 0.0, 1.0));
	p.hand_r = hp_wp(p, 0.0);
	p.hand_l = hp_wp(p, 0.44);
	p.elbow_r = C.b * vec3(-1.0, -0.6, -0.3);
	p.elbow_l = C.b * vec3(1.0, -0.8, 0.0);
}

// Прицел: приклад в плечо, ствол вперёд; kick — отдача 0..1
void musket_aim(inout HPose p, Xf C, float elev, float kick) {
	vec3 sh = xf_pt(C, HP_SHOULDER_R);
	vec3 dir = normalize(vec3(0.0, elev + 0.22 * kick, 1.0));
	vec3 butt = sh + C.b * vec3(0.075, -0.045, 0.06) - dir * 0.06 * kick;
	hp_weapon_m(p, butt + dir * 0.34, dir, vec3(0.0, -1.0, 0.0));
	p.hand_r = hp_wp(p, 0.0);
	p.hand_l = hp_wp(p, 0.36);
	p.elbow_r = vec3(-1.0, -0.45, -0.1);
	p.elbow_l = vec3(0.2, -1.0, 0.1);
}

// Приклад на земле у правой ноги (стойка «к ноге»)
void musket_order(inout HPose p, vec3 butt, vec3 dir) {
	vec3 d = normalize(dir);
	hp_weapon_m(p, butt + d * 0.34, d, vec3(0.0, 0.0, 1.0));
	p.hand_r = hp_wp(p, 0.62);
	p.elbow_r = vec3(-0.6, -0.4, -0.7);
}

// ---------------------------------------------------------------- состояния

void hp_idle(inout HPose p, float ph, float var, float t) {
	float br = sin(TAU * ph);
	// контрапост: вес на одной ноге (у каждого своей), медленно переносится
	float bias = hash11(var * 29.0) > 0.5 ? 1.0 : -1.0;
	float sh = clamp(0.65 * bias + 0.6 * (noise1(t * 0.12 + var * 37.0) * 2.0 - 1.0), -1.0, 1.0);
	float look = noise1(t * 0.11 + var * 91.0) - 0.5;
	float fwd = (hash11(var * 13.0) - 0.5) * 0.14;
	hp_stance(p, vec3(0.13, 0.0, 0.05 + fwd), vec3(-0.13, 0.0, -0.02 - fwd));
	p.pel_off = vec3(0.045 * sh, -0.03 - 0.012 * abs(sh), 0.0);
	p.pel_rot = vec3(0.02, 0.07 * sh, 0.075 * sh);
	p.chest_rot = vec3(0.02 - 0.025 * br, -0.05 * sh, -0.11 * sh);
	p.head_rot = vec3(-0.03 + 0.04 * (noise1(t * 0.07 + var * 5.0) - 0.5), 0.9 * look, 0.03 * sh);
	p.skirt = 0.6;
}

void hp_kneel(inout HPose p) {
	// правое колено на земле, левая стопа впереди
	hp_stance(p, vec3(0.13, 0.0, 0.36), vec3(-0.12, 0.03, -0.4));
	p.pel_off = vec3(0.0, -0.42, -0.04);
	p.knee_r = vec3(-0.1, -1.0, 0.6);
	p.skirt = 0.6;
}

// ---------------------------------------------------------------- инструменты работников

// Инструмент part: хват pos (оси торса C), ось dir (к бойку), zref — куда смотрит лезвие/боёк
void hp_tool_t(inout HPose p, int part, Xf C, vec3 pos, vec3 dir, vec3 zref) {
	p.t_part = part;
	p.t_pos = xf_pt(C, pos);
	p.t_rot = basis_yz(C.b * dir, C.b * zref);
}

// То же в осях модели
void hp_tool_m(inout HPose p, int part, vec3 pos, vec3 dir, vec3 zref) {
	p.t_part = part;
	p.t_pos = pos;
	p.t_rot = basis_yz(dir, zref);
}

// Точка на рукояти на расстоянии along от хвата
vec3 hp_tp(HPose p, float along) {
	return p.t_pos + p.t_rot[1] * along;
}

// Мах в вертикальной плоскости (кетмень, молот): лезвие поворачивается вместе с рукоятью
vec3 hp_swing_z(vec3 dir) {
	return vec3(0.0, -dir.z, dir.y);
}

vec3 mix3(vec3 a, vec3 b, vec3 c, vec3 d, float k1, float k2, float k3) {
	return mix(mix(mix(a, b, k1), c, k2), d, k3);
}

// Работа с инструментом (у кого он есть: деҳқон, малчы). aux — вид работы (AnimSpec WORK).
// Тело уже поставлено (стойка / колено / шаг) — здесь торс, руки и инструмент.
void hp_work_tool(inout HPose p, int wk, float ph, float aux, float var) {
	float cyc = fract(ph);
	p.w_vis = 0.0;  // посох малчы на время работы убран
	p.i_vis = 0.0;
	if (aux < 0.125) {
		// рубит дерево: наискось из-за правого плеча в ствол впереди слева, топор застревает, рывок назад
		float wind = seg01(cyc, 0.04, 0.44);
		float hitk = snap(cyc, 0.46, 0.57);
		float back = seg01(cyc, 0.68, 0.98);
		float tw = -0.5 * wind * (1.0 - hitk) + 0.28 * hitk * (1.0 - back);
		p.chest_rot = vec3(0.06 - 0.1 * wind * (1.0 - hitk) + 0.16 * hitk * (1.0 - back), tw, 0.05 * wind * (1.0 - hitk));
		p.pel_rot.y = 0.35 * tw;
		p.head_rot = vec3(0.12 + 0.15 * hitk * (1.0 - back), -0.6 * tw, 0.0);
		hp_stance(p, vec3(0.16, 0.0, 0.22), vec3(-0.2, 0.0, -0.1));
		p.pel_off = vec3(0.0, -0.07 - 0.04 * hitk * (1.0 - back), 0.0);
		Xf C = hp_chest(p);
		vec3 r_pos = vec3(-0.1, 1.02, 0.3);
		vec3 r_dir = vec3(0.3, 0.5, 0.81);
		vec3 w_pos = vec3(-0.26, 1.56, 0.02);
		vec3 w_dir = vec3(-0.32, 0.62, -0.72);
		vec3 h_pos = vec3(0.02, 1.2, 0.42);
		vec3 h_dir = vec3(0.55, 0.04, 0.83);
		vec3 pos = mix3(r_pos, w_pos, h_pos, r_pos, wind, hitk, back);
		vec3 dir = normalize(mix3(r_dir, w_dir, h_dir, r_dir, wind, hitk, back));
		vec3 n = normalize(cross(normalize(w_dir), normalize(h_dir)));
		hp_tool_t(p, H_TOOL_AXE, C, pos, dir, cross(n, dir));
		p.hand_r = hp_tp(p, 0.0);
		p.hand_l = hp_tp(p, -0.11);
		p.elbow_r = C.b * vec3(-0.9, -0.5, -0.3);
		p.elbow_l = C.b * vec3(0.7, -0.7, -0.2);
	} else if (aux < 0.375) {
		// копает кетменём: взмах над головой, удар в землю перед собой, подтягивает землю к ногам
		float raise = seg01(cyc, 0.02, 0.38);
		float hitk = snap(cyc, 0.4, 0.5);
		float pull = seg01(cyc, 0.6, 0.9);
		p.chest_rot = vec3(mix(mix(mix(0.62, 0.12, raise), 0.74, hitk), 0.62, pull), 0.0, 0.0);
		p.head_rot = vec3(mix(0.1, -0.25, raise * (1.0 - hitk)) + 0.2 * hitk, 0.0, 0.0);
		hp_stance(p, vec3(0.17, 0.0, 0.16), vec3(-0.18, 0.0, -0.13));
		p.pel_off = vec3(0.0, -0.09, -0.04);
		vec3 g_pull = vec3(-0.03, 0.9, 0.3);
		vec3 d_pull = vec3(-0.02, -0.82, 0.56);
		vec3 g_raise = vec3(-0.07, 1.62, 0.22);
		vec3 d_raise = vec3(0.0, 0.75, -0.66);
		vec3 g_hit = vec3(-0.02, 0.86, 0.38);
		vec3 d_hit = vec3(0.0, -0.75, 0.66);
		vec3 pos = mix3(g_pull, g_raise, g_hit, g_pull, raise, hitk, pull);
		vec3 dir = normalize(mix3(d_pull, d_raise, d_hit, d_pull, raise, hitk, pull));
		hp_tool_m(p, H_TOOL_HOE, pos, dir, hp_swing_z(dir));
		p.hand_r = hp_tp(p, 0.0);
		p.hand_l = hp_tp(p, 0.15);
		Xf C = hp_chest(p);
		p.elbow_r = C.b * vec3(-1.0, -0.6, -0.2);
		p.elbow_l = C.b * vec3(1.0, -0.6, -0.2);
	} else if (aux < 0.625) {
		// строит: на колене, два удара молотом за цикл по колу; левая рука держит кол
		float hm = fract(cyc * 2.0);
		float up = seg01(hm, 0.0, 0.52) * (1.0 - snap(hm, 0.58, 0.7));
		p.chest_rot = vec3(0.55 - 0.12 * up, -0.08 * up, 0.0);
		p.head_rot = vec3(0.25, 0.0, 0.0);
		vec3 tgt = vec3(-0.02, 0.3, 0.44);
		vec3 d_hit = normalize(vec3(0.05, -0.3, 0.95));
		vec3 g_hit = tgt - d_hit * 0.4;
		vec3 g_up = vec3(-0.16, 1.18, 0.18);
		vec3 d_up = normalize(vec3(0.0, 0.85, -0.52));
		vec3 pos = mix(g_hit, g_up, up);
		vec3 dir = normalize(mix(d_hit, d_up, up));
		hp_tool_m(p, H_TOOL_HAMMER, pos, dir, hp_swing_z(dir));
		p.hand_r = hp_tp(p, 0.0);
		p.hand_l = vec3(0.1, 0.42, 0.44);
		Xf C = hp_chest(p);
		p.elbow_r = C.b * vec3(-1.0, -0.2, -0.3);
		p.elbow_l = C.b * vec3(1.0, -0.4, 0.0);
	} else {
		Xf C = hp_chest(p);
		hp_swing_arms(p, C, ph, 0.32, 0.1, true, false);
		if (aux >= 0.8125 && wk == WK_TOOL) {
			// несёт бревно на правом плече, придерживает спереди
			p.t_part = H_TOOL_LOAD;
			p.t_rot = C.b;
			p.t_pos = xf_pt(C, H_LOAD_PT);
			p.hand_r = xf_pt(C, vec3(-0.17, 1.6, 0.24));
			p.elbow_r = C.b * vec3(-0.7, -1.0, 0.2);
			p.chest_rot.z += 0.04;
		} else {
			// несёт мешок на правом плече
			p.hand_r = xf_pt(C, vec3(-0.18, 1.58, 0.12));
			p.elbow_r = C.b * vec3(-0.6, -1.0, 0.0);
			p.i_vis = 1.0;
			p.i_rot = C.b;
			p.i_pos = xf_pt(C, H_SACK_PT);
		}
	}
}

HPose human_pose(int st, float ph, float aux, float var, float t) {
	HPose p = hp_rest();
	int wk = weapon_kind;
	bool banner = has_banner;
	bool two_hand = (wk == WK_MUSKET || wk == WK_STAFF || wk == WK_LANCE) && !banner;

	// ---- тело и ноги
	if (st == HS_WALK || (st == HS_WORK && aux >= 0.625)) {
		hp_gait(p, ph, H_STRIDE_WALK, 0.62, 0.11, 0.0);
		p.speed = 1.4;
	} else if (st == HS_RUN || st == HS_FLEE) {
		hp_gait(p, ph, H_STRIDE_RUN, 0.36, 0.2, 1.0);
		p.speed = 3.6;
		if (st == HS_FLEE) {
			p.chest_rot.x += 0.12;
			float back = noise1(t * 0.5 + var * 17.0);
			p.head_rot.y = (back > 0.5 ? 1.0 : -1.0) * smoothstep(0.1, 0.4, abs(back - 0.5)) * 1.1;
			p.head_rot.x = -0.15;
			p.w_vis = 0.0;
		}
	} else if (st == HS_DYING || st == HS_DEAD) {
		float k = st == HS_DEAD ? 1.0 : ph;
		float sd = aux < 0.5 ? 1.0 : -1.0;  // 1 — падает на левый бок
		float hit = win(k, 0.0, 0.32, 0.1);
		float buck = seg01(k, 0.1, 0.48);
		float tt = clamp((k - 0.32) / 0.5, 0.0, 1.0);
		float tip = tt * tt;  // падение ускоряется
		float bounce = 0.06 * sin(clamp((k - 0.82) / 0.18, 0.0, 1.0) * PI);
		hp_stance(p, vec3(0.12, 0.0, 0.04), vec3(-0.12, 0.0, -0.04));
		p.pel_off = vec3(0.0, -0.4 * buck, -0.08 * buck);
		p.pel_rot = vec3(0.35 * buck, 0.2 * sd * buck, 0.0);
		p.chest_rot = vec3(-0.4 * hit + 0.35 * buck, 0.25 * sd * buck, -0.15 * sd * buck);
		p.head_rot = vec3(-0.5 * hit + 0.45 * buck - 0.5 * tip, 0.5 * sd * tip, 0.0);
		p.knee_l = vec3(0.4 * sd + 0.1, 0.0, 1.0);
		p.knee_r = vec3(0.4 * sd - 0.1, 0.0, 1.0);
		float ang = 1.42 * tip + bounce * (1.0 - tip * 0.0);
		p.root_piv = vec3(0.2 * sd, 0.0, -0.05);
		p.root_rot = vec3(-0.25 * tip, 0.3 * sd * tip, -sd * ang);
		p.root_off = vec3(0.0, -0.1 * tip, 0.0);
		p.skirt = 0.7;
	} else if (st == HS_BRACE) {
		if (wk == WK_MUSKET || wk == WK_LANCE || wk == WK_STAFF) {
			hp_kneel(p);
		} else {
			hp_stance(p, vec3(0.15, 0.0, 0.26), vec3(-0.15, 0.0, -0.2));
			p.pel_off = vec3(0.0, -0.14, 0.0);
			p.pel_rot = vec3(0.15, -0.15, 0.0);
			p.chest_rot = vec3(0.12, -0.1, 0.0);
		}
	} else if (st == HS_WORK && aux >= 0.375) {
		// стройка: на колене, удары молотом
		hp_kneel(p);
		p.chest_rot = vec3(0.45, 0.0, 0.0);
		p.head_rot = vec3(0.3, 0.0, 0.0);
	} else if (st == HS_WORK) {
		// рубит или копает: ноги шире, колени согнуты
		hp_stance(p, vec3(0.17, 0.0, 0.16), vec3(-0.17, 0.0, -0.14));
		p.pel_off = vec3(0.0, -0.08, -0.03);
	} else if (st == HS_SHOOT || st == HS_MELEE) {
		hp_stance(p, vec3(0.14, 0.0, 0.22), vec3(-0.13, 0.0, -0.13));
		p.pel_off = vec3(0.0, -0.045, 0.0);
	} else if (st == HS_RELOAD) {
		hp_stance(p, vec3(0.15, 0.0, 0.08), vec3(-0.14, 0.0, -0.06));
		p.pel_off = vec3(0.0, -0.03, 0.0);
	} else if (st == HS_CHEER) {
		hp_stance(p, vec3(0.14, 0.0, 0.06), vec3(-0.14, 0.0, -0.03));
		float hop = abs(sin(3.0 * PI * ph));
		p.pel_off = vec3(0.0, -0.06 + 0.05 * hop, 0.0);
		p.chest_rot = vec3(-0.12, 0.0, 0.0);
		p.head_rot = vec3(-0.35 - 0.1 * hop, 0.0, 0.0);
	} else {
		hp_idle(p, ph, var, t);
	}

	// ---- руки и оружие
	Xf C = hp_chest(p);
	float wsw = 0.32;  // мах свободной руки при шаге

	if (st == HS_DYING || st == HS_DEAD) {
		float k = st == HS_DEAD ? 1.0 : ph;
		float hit = win(k, 0.0, 0.35, 0.1);
		float tip = seg01(k, 0.35, 0.85);
		float vr = hash11(var * 7.0);
		vec3 hl = mix(HP_HAND_L, vec3(0.45, 1.15 + 0.3 * vr, 0.25), tip);
		vec3 hr = mix(HP_HAND_R, vec3(-0.48, 1.3 - 0.25 * vr, 0.15), tip);
		hl += vec3(0.1, 0.35, 0.1) * hit;
		hr += vec3(-0.1, 0.35, 0.1) * hit;
		p.hand_l = xf_pt(C, hl);
		p.hand_r = xf_pt(C, hr);
		p.elbow_l = C.b * vec3(0.3, -1.0, -0.5);
		p.elbow_r = C.b * vec3(-0.3, -1.0, -0.5);
		hp_weapon_t(p, C, hr, vec3(-0.3, -0.2, 1.0), vec3(0.0, -1.0, 0.0));
		p.w_pos = p.hand_r;
		if (banner) {
			// знамя не исчезает: древко падает вместе с телом и ложится на землю вперёд
			hp_weapon_t(p, C, hr, vec3(-0.3, 0.08, 1.0), vec3(0.0, -1.0, 0.0));
			p.w_pos = p.hand_r;
		}
	} else if (st == HS_FLEE) {
		float a = TAU * ph;
		p.hand_l = xf_pt(C, h_arm(HP_SHOULDER_L, HP_HAND_L, -1.1 * cos(a) + 0.4, 0.65, 0.12));
		p.hand_r = xf_pt(C, h_arm(HP_SHOULDER_R, HP_HAND_R, 1.1 * cos(a) + 0.4, 0.65, -0.12));
		p.elbow_l = C.b * vec3(1.0, -0.2, -0.6);
		p.elbow_r = C.b * vec3(-1.0, -0.2, -0.6);
		p.w_vis = 0.0;
	} else if (banner) {
		// знаменосец: древко в правой руке, левая помогает
		float wave = 0.0;
		if (st == HS_IDLE || st == HS_RELOAD || st == HS_BRACE) {
			hp_weapon_m(p, vec3(-0.27, 0.02, 0.13) + vec3(0.0, 0.85, 0.0), vec3(0.02, 1.0, 0.03), vec3(0.0, 0.0, 1.0));
			p.hand_r = hp_wp(p, 0.06);
			p.hand_l = xf_pt(C, HP_HAND_L + vec3(-0.02, 0.0, 0.05));
		} else if (st == HS_CHEER || st == HS_SHOOT || st == HS_MELEE) {
			wave = sin(TAU * ph * (st == HS_CHEER ? 2.0 : 1.0));
			hp_weapon_t(p, C, vec3(-0.12, 1.5, 0.2), vec3(0.45 * wave, 1.0, 0.12), vec3(0.0, 0.0, 1.0));
			p.hand_r = hp_wp(p, 0.0);
			p.hand_l = hp_wp(p, -0.38);
			p.elbow_l = C.b * vec3(0.8, -0.5, -0.2);
		} else {
			hp_weapon_t(p, C, vec3(-0.16, 1.12, 0.22), vec3(0.0, 1.0, -0.07), vec3(0.0, 0.0, 1.0));
			p.hand_r = hp_wp(p, 0.0);
			p.hand_l = hp_wp(p, 0.3);
			p.elbow_l = C.b * vec3(0.9, -0.6, -0.2);
		}
		p.elbow_r = C.b * vec3(-0.8, -0.6, -0.3);
	} else if (st == HS_SHOOT && wk == WK_MUSKET) {
		float up = seg01(ph, 0.0, 0.25);
		float down = seg01(ph, 0.76, 1.0);
		float aim = up * (1.0 - down);
		float kick = ph >= 0.55 ? exp(-(ph - 0.55) * 26.0) : 0.0;
		p.pel_rot.y = -0.3 * aim;
		p.chest_rot = vec3(0.07 - 0.14 * kick, -0.38 * aim, 0.0);
		p.head_rot = vec3(0.16 * aim, 0.62 * aim, -0.2 * aim);
		C = hp_chest(p);
		musket_port(p, C);
		vec3 pp = p.w_pos;
		mat3 pr = p.w_rot;
		vec3 hl = p.hand_l;
		musket_aim(p, C, 0.03, kick);
		vec3 ap = p.w_pos;
		mat3 ar = p.w_rot;
		p.w_pos = pp;
		p.w_rot = pr;
		hp_weapon_mix(p, ap, ar, aim);
		p.hand_r = hp_wp(p, 0.0);
		p.hand_l = hp_wp(p, mix(0.44, 0.36, aim));
		p.elbow_r = mix(C.b * vec3(-1.0, -0.6, -0.3), vec3(-1.0, -0.45, -0.1), aim);
		p.elbow_l = mix(C.b * vec3(1.0, -0.8, 0.0), vec3(0.2, -1.0, 0.1), aim);
	} else if (st == HS_RELOAD && wk == WK_MUSKET) {
		// фитильное ружьё: порох, пуля, шомпол (4 удара), полка, в «порт»
		vec3 dir = normalize(vec3(0.0, 1.0, -0.12));
		vec3 butt = vec3(-0.05, 0.0, 0.36);
		float vert = seg01(ph, 0.0, 0.06) * (1.0 - seg01(ph, 0.8, 0.88));
		musket_port(p, C);
		vec3 pp = p.w_pos;
		mat3 pr = p.w_rot;
		hp_weapon_m(p, butt + dir * 0.34, dir, vec3(0.0, 0.0, 1.0));
		vec3 vp = p.w_pos;
		mat3 vrot = p.w_rot;
		p.w_pos = pp;
		p.w_rot = pr;
		hp_weapon_mix(p, vp, vrot, vert);
		vec3 muzzle = hp_wp(p, 1.16);
		vec3 flask = vec3(-0.19, 0.93, 0.1);
		vec3 hr = hp_wp(p, 0.0);
		hr = mix(hr, flask, seg01(ph, 0.06, 0.1));
		hr = mix(hr, muzzle + vec3(0.0, 0.07, 0.03), seg01(ph, 0.1, 0.14));
		hr += vec3(0.0, 0.02 * sin(ph * 300.0), 0.0) * win(ph, 0.14, 0.21, 0.01);
		hr = mix(hr, flask + vec3(0.02, 0.05, 0.0), seg01(ph, 0.21, 0.25));
		hr = mix(hr, muzzle + vec3(0.0, 0.05, 0.02), seg01(ph, 0.25, 0.29));
		hr = mix(hr, hp_wp(p, 0.45) + vec3(-0.05, 0.0, 0.03), seg01(ph, 0.29, 0.33));
		// шомпол: вынуть, 4 удара, вернуть
		float rod = win(ph, 0.33, 0.79, 0.02);
		float strokes = clamp((ph - 0.38) / 0.34, 0.0, 1.0);
		float depth = mix(0.15, 0.55 + 0.27 * (0.5 - 0.5 * cos(strokes * 4.0 * TAU)), seg01(ph, 0.35, 0.4));
		depth *= 1.0 - seg01(ph, 0.72, 0.77);
		vec3 rod_top = muzzle + dir * (0.88 - depth);
		hr = mix(hr, rod_top, seg01(ph, 0.33, 0.36));
		hr = mix(hr, hp_wp(p, 0.5) + vec3(-0.04, 0.0, 0.03), seg01(ph, 0.77, 0.8));
		// полка: ружьё в «порт», рука у замка
		hr = mix(hr, hp_wp(p, 0.1) + vec3(-0.02, 0.06, 0.06), seg01(ph, 0.82, 0.86));
		hr += vec3(0.015 * sin(ph * 200.0), 0.0, 0.0) * win(ph, 0.86, 0.92, 0.01);
		hr = mix(hr, hp_wp(p, 0.0), seg01(ph, 0.92, 0.98));
		p.hand_r = hr;
		p.hand_l = hp_wp(p, mix(0.44, 0.78, vert));
		p.elbow_r = C.b * vec3(-1.0, -0.5, -0.4);
		p.elbow_l = C.b * vec3(1.0, -0.6, 0.0);
		p.i_vis = rod;
		p.i_pos = hr;
		p.i_rot = basis_yz(-dir, vec3(0.0, 0.0, 1.0));
		p.head_rot = vec3(0.35 * vert, -0.15 * vert, 0.0);
		p.chest_rot.x = 0.1 * vert;
	} else if (st == HS_MELEE) {
		// удар: замах, быстрый удар, возврат в защиту
		float wind = seg01(ph, 0.0, 0.36);
		float hitk = snap(ph, 0.38, 0.52);
		float back = seg01(ph, 0.62, 1.0);
		if (two_hand) {
			// укол стволом/древком: от бедра вперёд
			p.chest_rot = vec3(0.05 - 0.12 * wind * (1.0 - hitk) + 0.22 * hitk * (1.0 - back), -0.25 * wind * (1.0 - hitk) + 0.2 * hitk * (1.0 - back), 0.0);
			p.pel_off.z += 0.12 * hitk * (1.0 - back);
			p.pel_off.y -= 0.04 * hitk * (1.0 - back);
			C = hp_chest(p);
			vec3 pos = mix(vec3(-0.13, 1.05, 0.28), vec3(-0.12, 1.02, -0.02), wind);
			vec3 dir = normalize(mix(vec3(0.5, 0.84, 0.16), vec3(0.05, 0.42, 0.9), wind));
			pos = mix(pos, vec3(-0.06, 1.2, 0.58), hitk);
			dir = normalize(mix(dir, vec3(0.02, 0.12, 1.0), hitk));
			pos = mix(pos, vec3(-0.13, 1.05, 0.28), back);
			dir = normalize(mix(dir, vec3(0.5, 0.84, 0.16), back));
			hp_weapon_t(p, C, pos, dir, vec3(0.0, -0.4, 1.0));
			p.hand_r = hp_wp(p, 0.0);
			p.hand_l = hp_wp(p, 0.42);
			p.elbow_r = C.b * vec3(-1.0, -0.6, -0.4);
			p.elbow_l = C.b * vec3(0.8, -0.8, 0.0);
		} else {
			// рубящий удар саблей/мечом/булавой сверху справа вниз налево
			float wk_up = (wk == WK_MACE || wk == WK_STAFF) ? 1.0 : 0.0;
			p.chest_rot = vec3(-0.1 * wind * (1.0 - hitk) + 0.32 * hitk * (1.0 - back),
				-0.5 * wind * (1.0 - hitk) + 0.45 * hitk * (1.0 - back), 0.08 * wind * (1.0 - hitk));
			p.pel_off.z += 0.1 * hitk * (1.0 - back);
			p.pel_off.y -= 0.05 * hitk * (1.0 - back);
			p.head_rot = vec3(0.1 * hitk, 0.25 * wind * (1.0 - hitk), 0.0);
			C = hp_chest(p);
			vec3 g_pos = vec3(-0.2, 1.08, 0.3);
			vec3 g_dir = vec3(0.12, 0.7, 0.72);
			vec3 pos = mix(g_pos, vec3(-0.25, 1.66, -0.04 + 0.1 * wk_up), wind);
			vec3 dir = normalize(mix(g_dir, vec3(-0.15, 0.55 + 0.4 * wk_up, -0.8 + 0.5 * wk_up), wind));
			pos = mix(pos, vec3(0.08, 0.98, 0.46), hitk);
			dir = normalize(mix(dir, vec3(0.42 - 0.3 * wk_up, -0.55, 0.72), hitk));
			pos = mix(pos, g_pos, back);
			dir = normalize(mix(dir, g_dir, back));
			hp_weapon_t(p, C, pos, dir, vec3(0.0, 0.3, 1.0));
			p.hand_r = hp_wp(p, 0.0);
			p.elbow_r = C.b * vec3(-1.0, -0.3, -0.5);
			if (item_kind == IK_SHIELD) {
				p.hand_l = xf_pt(C, mix(vec3(-0.04, 1.2, 0.3), vec3(0.2, 1.12, 0.2), hitk * (1.0 - back)));
				p.elbow_l = C.b * vec3(1.0, -0.2, -0.35);
			} else {
				p.hand_l = xf_pt(C, h_arm(HP_SHOULDER_L, HP_HAND_L, 0.4 - 0.6 * hitk, 0.4, 0.08));
			}
		}
	} else if (st == HS_CHEER) {
		float pump = sin(3.0 * TAU * ph);
		vec3 hr = vec3(-0.2, 1.97 + 0.07 * pump, 0.12);
		hp_weapon_t(p, C, hr, vec3(0.12, 1.0, 0.18 + 0.15 * pump), vec3(0.0, 0.0, 1.0));
		p.hand_r = hp_wp(p, 0.0);
		p.elbow_r = C.b * vec3(-1.0, 0.0, -0.3);
		if (item_kind == IK_SHIELD) {
			p.hand_l = xf_pt(C, vec3(0.2, 1.4 + 0.05 * pump, 0.3));
			p.elbow_l = C.b * vec3(1.0, -0.3, 0.0);
		} else {
			p.hand_l = xf_pt(C, vec3(0.24, 1.86 - 0.07 * pump, 0.14));
			p.elbow_l = C.b * vec3(1.0, 0.0, -0.3);
		}
	} else if (st == HS_WORK && (wk == WK_STAFF || wk == WK_TOOL)) {
		hp_work_tool(p, wk, ph, aux, var);
	} else if (st == HS_WORK) {
		float cyc = fract(ph);
		if (aux < 0.125) {
			// рубит: замах над головой, удар вниз
			float up = seg01(cyc, 0.0, 0.48);
			float hitk = snap(cyc, 0.5, 0.62);
			float back = seg01(cyc, 0.75, 1.0);
			p.chest_rot = vec3(0.2 - 0.25 * up * (1.0 - hitk) + 0.45 * hitk * (1.0 - back), 0.0, 0.0);
			p.head_rot = vec3(0.25 * hitk, 0.0, 0.0);
			C = hp_chest(p);
			vec3 pos = mix(vec3(-0.06, 1.0, 0.36), vec3(-0.05, 1.82, -0.06), up);
			vec3 dir = normalize(mix(vec3(0.0, 0.2, 1.0), vec3(0.0, 0.25, -1.0), up));
			pos = mix(pos, vec3(-0.02, 0.98, 0.42), hitk);
			dir = normalize(mix(dir, vec3(0.0, -0.75, 0.66), hitk));
			pos = mix(pos, vec3(-0.06, 1.0, 0.36), back);
			dir = normalize(mix(dir, vec3(0.0, 0.2, 1.0), back));
			hp_weapon_t(p, C, pos, dir, vec3(0.0, 1.0, 0.0));
			p.hand_r = hp_wp(p, 0.0);
			p.hand_l = hp_wp(p, -0.22);
		} else if (aux < 0.375) {
			// копает: вонзить вниз, поддеть назад
			float push = snap(cyc, 0.2, 0.42);
			float lever = seg01(cyc, 0.45, 0.7);
			float back = seg01(cyc, 0.75, 1.0);
			p.chest_rot = vec3(0.35 + 0.15 * push - 0.2 * lever * (1.0 - back), 0.0, 0.0);
			C = hp_chest(p);
			vec3 pos = mix(vec3(-0.05, 1.12, 0.36), vec3(-0.04, 0.82, 0.4), push);
			vec3 dir = normalize(mix(vec3(0.0, -0.9, 0.35), vec3(0.0, -0.75, 0.62), lever));
			pos = mix(pos, vec3(-0.04, 1.0, 0.24), lever);
			pos = mix(pos, vec3(-0.05, 1.12, 0.36), back);
			dir = normalize(mix(dir, vec3(0.0, -0.9, 0.35), back));
			hp_weapon_t(p, C, pos, dir, vec3(0.0, 0.0, 1.0));
			p.hand_r = hp_wp(p, -0.25);
			p.hand_l = hp_wp(p, 0.1);
		} else if (aux < 0.625) {
			// строит: удары молотом (два за цикл)
			float hm = fract(cyc * 2.0);
			float up = seg01(hm, 0.0, 0.55) * (1.0 - snap(hm, 0.6, 0.72));
			C = hp_chest(p);
			hp_weapon_t(p, C, mix(vec3(-0.1, 0.92, 0.42), vec3(-0.18, 1.45, 0.3), up),
				normalize(mix(vec3(0.0, 0.3, 1.0), vec3(0.0, 1.0, -0.2), up)), vec3(0.0, 1.0, 0.0));
			p.hand_r = hp_wp(p, 0.0);
			p.hand_l = xf_pt(C, vec3(0.12, 0.85, 0.45));
			p.elbow_l = C.b * vec3(1.0, 0.0, 0.0);
		} else {
			// несёт мешок на правом плече
			hp_swing_arms(p, C, ph, wsw, 0.1, true, false);
			p.hand_r = xf_pt(C, vec3(-0.18, 1.58, 0.12));
			p.elbow_r = C.b * vec3(-0.6, -1.0, 0.0);
			p.w_vis = 0.0;
			p.i_vis = 1.0;
			p.i_rot = C.b;
			p.i_pos = xf_pt(C, H_SACK_PT);
		}
		p.elbow_r = C.b * vec3(-0.8, -0.6, -0.3);
	} else if (st == HS_BRACE) {
		if (wk == WK_MUSKET) {
			p.chest_rot = vec3(0.05, -0.35, 0.0);
			p.head_rot = vec3(0.1, 0.45, -0.15);
			C = hp_chest(p);
			musket_aim(p, C, 0.25, 0.0);
		} else if (two_hand) {
			// копьё упёрто в землю, остриём вперёд-вверх
			C = hp_chest(p);
			hp_weapon_m(p, vec3(-0.12, 0.55, 0.15), vec3(0.0, 0.5, 0.87), vec3(0.0, -1.0, 0.0));
			p.hand_r = hp_wp(p, 0.0);
			p.hand_l = hp_wp(p, 0.4);
		} else {
			hp_weapon_t(p, C, vec3(-0.2, 1.42, 0.22), vec3(0.15, 0.3, 1.0), vec3(0.0, 1.0, 0.0));
			p.hand_r = hp_wp(p, 0.0);
			p.elbow_r = C.b * vec3(-1.0, 0.3, -0.4);
			p.hand_l = xf_pt(C, vec3(-0.05, 1.27, 0.3));
			p.elbow_l = C.b * vec3(1.0, -0.2, -0.3);
		}
	} else {
		// IDLE, WALK, RUN; SHOOT/RELOAD без ружья — как покой
		bool moving = (st == HS_WALK || st == HS_RUN);
		float run = st == HS_RUN ? 1.0 : 0.0;
		if (moving) {
			hp_swing_arms(p, C, ph, mix(wsw, 0.55, run), mix(0.12, 0.7, run), true, true);
		} else {
			float br = sin(TAU * ph);
			p.hand_l = xf_pt(C, HP_HAND_L + vec3(-0.01, 0.01 * br, 0.04));
			p.hand_r = xf_pt(C, HP_HAND_R + vec3(0.01, 0.01 * br, 0.04));
			if (st == HS_IDLE && hash11(var * 3.3) > 0.35) {
				// левая рука на кушаке, локоть в сторону — поза, а не «манекен»
				p.hand_l = xf_pt(C, vec3(0.175, 1.0 + 0.01 * br, 0.07));
				p.elbow_l = C.b * vec3(1.0, -0.1, -0.35);
			}
		}
		if (wk == WK_MUSKET) {
			if (st == HS_RUN) {
				musket_port(p, C);
			} else if (moving) {
				musket_shoulder(p, C);
			} else {
				vec3 fr = p.foot_r;
				musket_order(p, vec3(fr.x - 0.13, 0.0, fr.z + 0.16), vec3(-0.04, 1.0, 0.05));
			}
		} else if (wk == WK_STAFF) {
			// посох: опирается при покое, качается при ходьбе
			float a = TAU * ph;
			vec3 tip = moving ? vec3(-0.34, 0.0, 0.3 + 0.25 * cos(a)) : vec3(-0.36, 0.0, 0.2);
			vec3 hr = moving ? p.hand_r + vec3(-0.02, 0.18, 0.08) : xf_pt(C, vec3(-0.3, 1.02, 0.14));
			hp_weapon_m(p, hr, hr - tip, vec3(0.0, 0.0, 1.0));
			p.hand_r = hr;
		} else if (wk == WK_TOOL) {
			// деҳқон: кетмень на правом плече (идёт), опирается на кетмень (стоит)
			if (moving) {
				hp_tool_t(p, H_TOOL_HOE, C, vec3(-0.19, 1.22, 0.24), normalize(vec3(-0.02, 0.45, -0.89)),
					vec3(0.0, -1.0, 0.0));
				p.hand_r = hp_tp(p, 0.0);
				p.elbow_r = C.b * vec3(-0.6, -1.0, 0.1);
			} else {
				vec3 g = xf_pt(C, vec3(-0.27, 1.02, 0.2));
				hp_tool_m(p, H_TOOL_HOE, g, normalize(vec3(-0.04, -1.0, 0.1)), vec3(0.0, -0.2, 1.0));
				p.hand_r = g;
				p.elbow_r = C.b * vec3(-0.8, -0.4, -0.3);
			}
			p.w_vis = 0.0;
		} else if (wk == WK_MACE) {
			// булава на плече
			hp_weapon_t(p, C, vec3(-0.22, 1.12, 0.2), vec3(0.0, 0.85, -0.5), vec3(0.0, 0.5, 1.0));
			p.hand_r = hp_wp(p, 0.0);
			p.elbow_r = C.b * vec3(-0.7, -0.7, -0.2);
		} else if (wk != WK_NONE) {
			// клинок опущен вниз-вперёд
			hp_weapon_m(p, p.hand_r, normalize(C.b * vec3(0.05, -0.35, 1.0)), C.b * vec3(0.0, 1.0, 0.0));
			if (moving) {
				p.w_rot = basis_yz(normalize(C.b * vec3(0.1, -0.6, 0.8)), C.b * vec3(0.0, 1.0, 0.0));
			}
		}
		if (item_kind == IK_SHIELD) {
			// щит у груди: предплечье поперёк тела (тогда щит смотрит вперёд)
			p.hand_l = xf_pt(C, vec3(-0.03, 1.1 + 0.03 * run, 0.24));
			p.elbow_l = C.b * vec3(1.0, -0.3, -0.35);
		}
	}
	if (item_kind == IK_SHIELD && (st == HS_FLEE)) {
		p.i_vis = 0.0;
	} else if (item_kind == IK_SHIELD) {
		p.i_vis = 1.0;
	}
	if (st == HS_FLEE && item_kind != IK_SHIELD) {
		p.i_vis = 0.0;
	}
	if (wk == WK_TOOL && st != HS_WORK && p.t_part < 0 && st != HS_FLEE) {
		// бой, клич, смерть: в руке топор (бой) или кетмень — по положению «оружия»
		p.t_part = (st == HS_MELEE || st == HS_BRACE) ? H_TOOL_AXE : H_TOOL_HOE;
		p.t_pos = p.w_pos;
		p.t_rot = p.w_rot;
		p.w_vis = 0.0;
	}
	return p;
}

// Сгиб у сустава: вершины верхней кости у корня (плечо, бедро) смешиваются с родителем
// (грудь, таз), у среднего сустава (локоть, колено) — с нижней костью; нижняя кость у сустава —
// с верхней. Вес — UV2.y (gen_units_kit.joint_weight), 0 — жёсткая часть (кулак, обшлаг, сапог).
Xf hp_joint_blend(bool upper, Xf X, Xf parent, Xf up, Xf lo, vec3 v, vec3 root, vec3 mid, float wgt) {
	if (wgt <= 0.001) {
		return X;
	}
	if (upper) {
		return xf_mix(up, distance(v, root) < distance(v, mid) ? parent : lo, wgt);
	}
	return xf_mix(lo, up, wgt);
}

// Преобразование части part (вершина v в позе покоя; ткань деформируется здесь же)
Xf human_bone(int part, HPose p, inout vec3 v, float wgt, vec3 wind_m, float t, float var) {
	Xf X = xf_id();
	if (part == H_CHEST) {
		X = hp_chest(p);
	} else if (part == H_HEAD) {
		X = xf_mul(hp_chest(p), xf_piv(eul(p.head_rot), HP_HEAD, vec3(0.0)));
		// перо/кисть на шапке чуть отстаёт
		v.z -= wgt * wgt * (0.04 + 0.02 * sin(t * 3.0 + var * 20.0));
	} else if (part == H_UARM_L || part == H_FARM_L || (part == H_ITEM && item_kind == IK_SHIELD)) {
		Xf up;
		Xf lo;
		Xf C = hp_chest(p);
		ik_chain(HP_SHOULDER_L, HP_ELBOW_L, HP_HAND_L, C, p.hand_l, p.elbow_l, 1.04, up, lo);
		X = part == H_UARM_L ? up : lo;
		if (part != H_ITEM) {
			X = hp_joint_blend(part == H_UARM_L, X, C, up, lo, v, HP_SHOULDER_L, HP_ELBOW_L, wgt);
		}
		if (part == H_ITEM) {
			X.b *= p.i_vis;
			X.o = mix(xf_pt(lo, HP_HAND_L), X.o, p.i_vis);
		}
	} else if (part == H_UARM_R || part == H_FARM_R) {
		Xf up;
		Xf lo;
		Xf C = hp_chest(p);
		ik_chain(HP_SHOULDER_R, HP_ELBOW_R, HP_HAND_R, C, p.hand_r, p.elbow_r, 1.04, up, lo);
		X = hp_joint_blend(part == H_UARM_R, part == H_UARM_R ? up : lo, C, up, lo, v, HP_SHOULDER_R, HP_ELBOW_R, wgt);
	} else if (part == H_THIGH_L || part == H_SHIN_L || part == H_SKIRT_L) {
		Xf P = hp_pel(p);
		Xf up;
		Xf lo;
		ik_chain(HP_HIP_L, HP_KNEE_L, HP_ANKLE_L, P, p.foot_l, P.b * p.knee_l, 1.05, up, lo);
		if (part == H_SKIRT_L) {
			vec3 d = transpose(P.b) * (up.b * (HP_KNEE_L - HP_HIP_L));
			float pitch = atan(d.z, -d.y);
			float roll = atan(d.x, -d.y);
			v.xz += normalize(v.xz + vec2(0.0001)) * p.flare * wgt;
			X = xf_mul(P, xf_piv(rot_z(roll * 0.2) * rot_x(-pitch * p.skirt), HP_SKIRT_L, vec3(0.0)));
		} else {
			X = hp_joint_blend(part == H_THIGH_L, part == H_THIGH_L ? up : lo, P, up, lo, v, HP_HIP_L, HP_KNEE_L, wgt);
		}
	} else if (part == H_THIGH_R || part == H_SHIN_R || part == H_SKIRT_R) {
		Xf P = hp_pel(p);
		Xf up;
		Xf lo;
		ik_chain(HP_HIP_R, HP_KNEE_R, HP_ANKLE_R, P, p.foot_r, P.b * p.knee_r, 1.05, up, lo);
		if (part == H_SKIRT_R) {
			vec3 d = transpose(P.b) * (up.b * (HP_KNEE_R - HP_HIP_R));
			float pitch = atan(d.z, -d.y);
			float roll = atan(d.x, -d.y);
			v.xz += normalize(v.xz + vec2(0.0001)) * p.flare * wgt;
			X = xf_mul(P, xf_piv(rot_z(roll * 0.2) * rot_x(-pitch * p.skirt), HP_SKIRT_R, vec3(0.0)));
		} else {
			X = hp_joint_blend(part == H_THIGH_R, part == H_THIGH_R ? up : lo, P, up, lo, v, HP_HIP_R, HP_KNEE_R, wgt);
		}
	} else if (part == H_WEAPON || part == H_CLOTH) {
		X = xf_grip(p.w_rot, p.w_pos, HP_HAND_R, p.w_vis);
		if (part == H_CLOTH) {
			vec3 wl = transpose(p.w_rot) * wind_m;
			v = cloth_flutter(v, vec3(HP_HAND_R.x, v.y, HP_HAND_R.z - 0.02), wgt, wl, t, var * 31.0);
		}
	} else if (part >= H_TOOL_AXE && part <= H_TOOL_LOAD) {
		float vis = part == p.t_part ? 1.0 : 0.0;
		X = xf_grip(p.t_rot, p.t_pos, part == H_TOOL_LOAD ? H_LOAD_PT : HP_HAND_R, vis);
	} else if (part == H_ITEM) {
		if (item_kind == IK_SACK) {
			X = xf_grip(p.i_rot, p.i_pos, H_SACK_PT, p.i_vis);
		} else {
			X = xf_grip(p.i_rot, p.i_pos, HP_HAND_R, p.i_vis);
		}
	} else {
		X = hp_pel(p);
		// концы кушака качаются
		v.z += wgt * wgt * 0.05 * sin(t * 4.0 + var * 9.0);
	}
	return xf_mul(hp_root(p), X);
}
