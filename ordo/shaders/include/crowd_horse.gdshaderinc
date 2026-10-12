// Толпа: конь со всадником (skeleton 1) и конь без всадника (skeleton 3).
// Состояния — AnimSpec.Horse. Копыта ставятся ИК по циклу аллюра (AnimSpec.STRIDE_HORSE):
// шаг — четырёхтактный, рысь — диагональные пары, галоп — с наклоном корпуса и фазой полёта.
// Всадник — дочерние части корпуса: таз в седле, торс, голова, руки (ИК), оружие, щит, знамя.
// Нужны uniform: weapon_kind, has_banner, skeleton (crowd.gdshader).

const int RS_IDLE = 0;
const int RS_WALK = 1;
const int RS_TROT = 2;
const int RS_GALLOP = 3;
const int RS_CHARGE = 4;
const int RS_MELEE = 5;
const int RS_DYING = 6;
const int RS_DEAD = 7;
const int RS_REAR = 8;
const int RS_CHEER = 9;

const float R_STRIDE_WALK = 1.9;
const float R_STRIDE_TROT = 3.0;
const float R_STRIDE_GALLOP = 6.0;
const float R_STRIDE_CHARGE = 6.4;

// Сдвиг человека в седло (gen_units_kit.RIDER_OFF)
const vec3 R_OFF = vec3(0.0, 0.64, 0.02);

struct RPose {
	vec3 root_rot;
	vec3 root_piv;
	vec3 root_off;
	vec3 body_rot;
	vec3 body_piv;
	vec3 body_off;
	vec3 neck_rot;
	vec3 head_rot;
	vec3 tail_rot;
	vec3 hoof_fl;
	vec3 hoof_fr;
	vec3 hoof_hl;
	vec3 hoof_hr;
	vec3 seat_rot;
	vec3 seat_off;
	vec3 torso_rot;
	vec3 rhead_rot;
	vec3 hand_l;
	vec3 hand_r;
	vec3 elbow_l;
	vec3 elbow_r;
	mat3 w_rot;
	vec3 w_pos;
	float w_vis;
	float speed;
	float leg_fold;
};

RPose rp_rest() {
	RPose p;
	p.root_rot = vec3(0.0);
	p.root_piv = vec3(0.0);
	p.root_off = vec3(0.0);
	p.body_rot = vec3(0.0);
	p.body_piv = RP_BODY;
	p.body_off = vec3(0.0);
	p.neck_rot = vec3(0.0);
	p.head_rot = vec3(0.0);
	p.tail_rot = vec3(0.0);
	p.hoof_fl = RP_F_HOOF_L;
	p.hoof_fr = RP_F_HOOF_R;
	p.hoof_hl = RP_H_HOOF_L;
	p.hoof_hr = RP_H_HOOF_R;
	p.seat_rot = vec3(0.0);
	p.seat_off = vec3(0.0);
	p.torso_rot = vec3(0.0);
	p.rhead_rot = vec3(0.0);
	p.hand_l = RP_R_HAND_L;
	p.hand_r = RP_R_HAND_R;
	p.elbow_l = vec3(0.5, -0.3, -1.0);
	p.elbow_r = vec3(-0.5, -0.3, -1.0);
	p.w_rot = mat3(1.0);
	p.w_pos = RP_R_HAND_R;
	p.w_vis = 1.0;
	p.speed = 0.0;
	p.leg_fold = 0.0;
	return p;
}

Xf rp_body(RPose p) {
	return xf_piv(eul(p.body_rot), p.body_piv, p.body_off);
}

Xf rp_root(RPose p) {
	return xf_piv(eul(p.root_rot), p.root_piv, p.root_off);
}

Xf rp_seat(RPose p) {
	return xf_mul(rp_body(p), xf_piv(eul(p.seat_rot), RP_R_PELVIS, p.seat_off));
}

Xf rp_torso(RPose p) {
	return xf_mul(rp_seat(p), xf_piv(eul(p.torso_rot), RP_R_CHEST, vec3(0.0)));
}

vec3 rp_wp(RPose p, float along) {
	return p.w_pos + p.w_rot[1] * along;
}

void rp_weapon_t(inout RPose p, Xf T, vec3 pos, vec3 dir, vec3 zref) {
	p.w_pos = xf_pt(T, pos + R_OFF);
	p.w_rot = basis_yz(T.b * dir, T.b * zref);
}

// Аллюр: фазы касания ног (LF, RF, LH, RH), доля опоры, подъём копыт (перед, зад)
void rp_gait(inout RPose p, float ph, float stride, float duty, vec4 off, float lf, float lh) {
	vec2 a = gait_foot(fract(ph - off.x), duty, stride, lf);
	vec2 b = gait_foot(fract(ph - off.y), duty, stride, lf);
	vec2 c = gait_foot(fract(ph - off.z), duty, stride, lh);
	vec2 d = gait_foot(fract(ph - off.w), duty, stride, lh);
	p.hoof_fl = RP_F_HOOF_L + vec3(0.0, a.y, a.x + 0.02);
	p.hoof_fr = RP_F_HOOF_R + vec3(0.0, b.y, b.x + 0.02);
	p.hoof_hl = RP_H_HOOF_L + vec3(0.0, c.y, c.x + 0.04);
	p.hoof_hr = RP_H_HOOF_R + vec3(0.0, d.y, d.x + 0.04);
}

// Копыто в осях корпуса (для поз: дыбы, падение, поджатые ноги)
vec3 rp_local_hoof(RPose p, vec3 rest, vec3 d) {
	return xf_pt(rp_body(p), rest + d);
}

// ---------------------------------------------------------------- позы всадника

// Левая рука держит повод перед лукой седла
void rp_reins(inout RPose p, Xf T, float sway) {
	p.hand_l = xf_pt(T, vec3(0.07, 1.02 + 0.015 * sway, 0.34) + R_OFF);
	p.elbow_l = T.b * vec3(0.9, -0.6, -0.4);
}

// Оружие в покое, на шагу и рысью
void rp_carry(inout RPose p, Xf T, int wk, bool banner) {
	if (banner || wk == WK_LANCE) {
		rp_weapon_t(p, T, vec3(-0.22, 1.0, 0.2), vec3(0.0, 1.0, 0.08), vec3(0.0, 0.0, 1.0));
	} else if (wk == WK_MACE) {
		rp_weapon_t(p, T, vec3(-0.23, 1.1, 0.2), vec3(0.0, 0.85, -0.52), vec3(0.0, 0.5, 1.0));
	} else if (wk == WK_NONE) {
		rp_weapon_t(p, T, vec3(-0.25, 0.95, 0.22), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0));
	} else {
		// сабля на плече, лезвием вверх
		rp_weapon_t(p, T, vec3(-0.24, 1.02, 0.18), vec3(0.0, 0.8, -0.6), vec3(0.0, 0.6, 0.8));
	}
	p.hand_r = rp_wp(p, 0.0);
	p.elbow_r = T.b * vec3(-0.8, -0.6, -0.3);
}

// Атака: копьё наперевес, сабля вперёд, булава поднята
void rp_charge_weapon(inout RPose p, Xf T, int wk, bool banner) {
	if (banner) {
		rp_weapon_t(p, T, vec3(-0.2, 1.05, 0.26), vec3(0.0, 1.0, 0.55), vec3(0.0, 0.0, 1.0));
	} else if (wk == WK_LANCE) {
		// копьё наперевес: ось поднята на наклон торса — в мире почти горизонтально
		rp_weapon_t(p, T, vec3(-0.17, 1.08, 0.0), vec3(0.13, 0.4, 1.0), vec3(0.0, 1.0, 0.0));
		p.elbow_r = T.b * vec3(-1.0, -0.3, -0.2);
	} else if (wk == WK_MACE) {
		rp_weapon_t(p, T, vec3(-0.26, 1.5, 0.12), vec3(0.0, 0.9, 0.4), vec3(0.0, 0.0, 1.0));
	} else {
		rp_weapon_t(p, T, vec3(-0.22, 1.32, 0.36), vec3(0.04, 0.12, 1.0), vec3(0.0, 1.0, 0.0));
	}
	p.hand_r = rp_wp(p, 0.0);
	p.elbow_r = T.b * vec3(-1.0, -0.4, -0.3);
}

// ---------------------------------------------------------------- позы коня

RPose rider_pose(int st, float ph, float aux, float var, float t) {
	RPose p = rp_rest();
	int wk = weapon_kind;
	bool banner = has_banner;
	bool riderless = skeleton == 3;
	float ride_sway = 0.0;

	if (st == RS_WALK) {
		rp_gait(p, ph, R_STRIDE_WALK, 0.6, vec4(0.25, 0.75, 0.0, 0.5), 0.13, 0.1);
		float a = TAU * ph;
		p.body_off = vec3(0.012 * sin(a), -0.03 + 0.014 * cos(2.0 * a), 0.0);
		p.body_rot = vec3(0.01 * cos(2.0 * a), 0.015 * sin(a), 0.02 * sin(a));
		p.neck_rot = vec3(0.08 + 0.07 * cos(2.0 * a + 1.2), 0.03 * sin(a), 0.0);
		p.head_rot = vec3(0.04 * cos(2.0 * a + 2.0), 0.0, 0.0);
		p.tail_rot = vec3(0.05, 0.12 * sin(a + 0.5), 0.0);
		p.seat_rot = vec3(-0.01 * cos(2.0 * a), -0.02 * sin(a), -0.03 * sin(a));
		p.torso_rot = vec3(0.04, 0.03 * sin(a), 0.02 * sin(a));
		ride_sway = sin(2.0 * a);
		p.speed = 1.6;
	} else if (st == RS_TROT) {
		rp_gait(p, ph, R_STRIDE_TROT, 0.44, vec4(0.0, 0.5, 0.5, 0.0), 0.24, 0.17);
		float a = TAU * ph;
		float bounce = cos(2.0 * (a - TAU * 0.22));
		p.body_off = vec3(0.0, -0.04 - 0.035 * bounce, 0.0);
		p.body_rot = vec3(0.015 * bounce, 0.0, 0.015 * sin(a));
		p.neck_rot = vec3(0.12 - 0.03 * bounce, 0.0, 0.0);
		p.tail_rot = vec3(0.3, 0.05 * sin(a), 0.0);
		// облегчённая рысь: всадник поднимается на каждый второй такт
		float post = smoothstep(-0.3, 0.7, sin(a - 0.6));
		p.seat_off = vec3(0.0, 0.025 + 0.07 * post, 0.04 * post);
		p.seat_rot = vec3(0.12 * post, 0.0, 0.0);
		p.torso_rot = vec3(0.12 + 0.05 * post, 0.0, 0.0);
		ride_sway = bounce;
		p.speed = 4.0;
	} else if (st == RS_GALLOP || st == RS_CHARGE) {
		bool ch = st == RS_CHARGE;
		rp_gait(p, ph, ch ? R_STRIDE_CHARGE : R_STRIDE_GALLOP, ch ? 0.25 : 0.27,
			vec4(0.31, 0.43, 0.0, 0.12), ch ? 0.34 : 0.3, 0.26);
		float a = TAU * ph;
		float pitch = 0.085 * cos(a - TAU * 0.27);   // нос вверх при толчке задом
		p.body_rot = vec3(-pitch, 0.0, 0.015 * sin(a));
		p.body_off = vec3(0.0, -0.035 + 0.06 * cos(a - TAU * 0.85), 0.0);
		p.neck_rot = vec3((ch ? 0.42 : 0.3) + 0.16 * cos(a - TAU * 0.55), 0.0, 0.0);
		p.head_rot = vec3(-0.08 * cos(a - TAU * 0.55), 0.0, 0.0);
		p.tail_rot = vec3(0.75 + 0.15 * sin(a), 0.06 * sin(a * 2.0), 0.0);
		// всадник в стременах, наклон вперёд, гасит качание корпуса
		p.seat_off = vec3(0.0, 0.08, 0.06);
		p.seat_rot = vec3(pitch * 0.7, 0.0, 0.0);
		p.torso_rot = vec3((ch ? 0.42 : 0.3) + 0.04 * cos(a - TAU * 0.5), 0.0, 0.0);
		p.rhead_rot = vec3(-0.3, 0.0, 0.0);
		ride_sway = cos(a);
		p.speed = ch ? 9.0 : 8.0;
	} else if (st == RS_REAR) {
		float up = seg01(ph, 0.05, 0.32) * (1.0 - seg01(ph, 0.7, 0.98));
		p.body_piv = vec3(0.0, 0.95, -0.62);
		p.body_rot = vec3(-0.82 * up, 0.0, 0.0);
		p.neck_rot = vec3(-0.25 * up, 0.0, 0.0);
		p.head_rot = vec3(-0.2 * up + 0.15 * sin(ph * 20.0) * up, 0.0, 0.0);
		p.tail_rot = vec3(-0.1 * up, 0.0, 0.0);
		// передние ноги бьют воздух
		float paw = sin(ph * 26.0);
		vec3 fl = rp_local_hoof(p, RP_F_HOOF_L, vec3(0.0, 0.42 + 0.12 * paw, -0.12));
		vec3 fr = rp_local_hoof(p, RP_F_HOOF_R, vec3(0.0, 0.42 - 0.12 * paw, -0.12));
		p.hoof_fl = mix(RP_F_HOOF_L, fl, up);
		p.hoof_fr = mix(RP_F_HOOF_R, fr, up);
		p.hoof_hl = RP_H_HOOF_L + vec3(0.0, 0.0, 0.1 * up);
		p.hoof_hr = RP_H_HOOF_R + vec3(0.0, 0.0, 0.1 * up);
		p.seat_rot = vec3(0.35 * up, 0.0, 0.0);
		p.torso_rot = vec3(0.35 * up, 0.0, 0.0);
	} else if (st == RS_DYING || st == RS_DEAD) {
		float k = st == RS_DEAD ? 1.0 : ph;
		float sd = aux < 0.5 ? 1.0 : -1.0;  // 1 — падает на левый бок
		float fore = seg01(k, 0.0, 0.3);
		float hind = seg01(k, 0.2, 0.55);
		float tt = clamp((k - 0.45) / 0.45, 0.0, 1.0);
		float roll = tt * tt;
		float bounce = 0.05 * sin(clamp((k - 0.88) / 0.12, 0.0, 1.0) * PI);
		p.body_rot = vec3(0.35 * fore * (1.0 - hind) + 0.06 * hind, 0.0, 0.0);
		p.body_off = vec3(0.0, -0.32 * fore - 0.3 * hind, 0.1 * fore);
		p.neck_rot = vec3(0.3 * fore + 0.5 * roll, 0.25 * sd * roll, 0.0);
		p.head_rot = vec3(0.3 * roll, 0.0, 0.0);
		p.tail_rot = vec3(-0.1, 0.0, 0.0);
		// ноги подламываются, затем лежат вдоль земли
		vec3 fold_f = vec3(0.0, 0.42, -0.25);
		vec3 fold_h = vec3(0.0, 0.3, 0.32);
		p.hoof_fl = mix(RP_F_HOOF_L, rp_local_hoof(p, RP_F_HOOF_L, fold_f), fore);
		p.hoof_fr = mix(RP_F_HOOF_R, rp_local_hoof(p, RP_F_HOOF_R, fold_f), fore);
		p.hoof_hl = mix(RP_H_HOOF_L, rp_local_hoof(p, RP_H_HOOF_L, fold_h), hind);
		p.hoof_hr = mix(RP_H_HOOF_R, rp_local_hoof(p, RP_H_HOOF_R, fold_h), hind);
		vec3 out_f = vec3(0.0, 0.12, 0.3);
		vec3 out_h = vec3(0.0, 0.12, -0.2);
		p.hoof_fl = mix(p.hoof_fl, rp_local_hoof(p, RP_F_HOOF_L, out_f + vec3(0.1, 0.0, 0.1)), roll);
		p.hoof_fr = mix(p.hoof_fr, rp_local_hoof(p, RP_F_HOOF_R, out_f), roll);
		p.hoof_hl = mix(p.hoof_hl, rp_local_hoof(p, RP_H_HOOF_L, out_h + vec3(0.1, 0.0, -0.1)), roll);
		p.hoof_hr = mix(p.hoof_hr, rp_local_hoof(p, RP_H_HOOF_R, out_h), roll);
		p.root_piv = vec3(0.28 * sd, 0.0, 0.0);
		p.root_rot = vec3(0.0, 0.0, -sd * (1.5 * roll - bounce));
		p.root_off = vec3(0.0, -0.06 * roll, 0.0);
		// всадник обмякает и валится вперёд-набок
		float slump = seg01(k, 0.05, 0.5);
		p.seat_rot = vec3(0.2 * slump, 0.0, 0.25 * sd * slump);
		p.seat_off = vec3(0.0, -0.05 * slump, 0.05 * slump);
		p.torso_rot = vec3(0.75 * slump, 0.2 * sd * slump, 0.2 * sd * slump);
		p.rhead_rot = vec3(0.5 * slump, 0.0, 0.0);
		p.leg_fold = 1.0;
	} else {
		// IDLE, MELEE, CHEER: стоит; переминается, бьёт копытом, машет хвостом
		float sw = noise1(t * 0.13 + var * 21.0) * 2.0 - 1.0;
		p.body_off = vec3(0.02 * sw, -0.015, 0.0);
		p.body_rot = vec3(0.0, 0.02 * sw, 0.015 * sw);
		float bob = sin(TAU * ph);
		float look = noise1(t * 0.09 + var * 53.0) - 0.5;
		p.neck_rot = vec3(0.1 + 0.035 * bob, 0.45 * look, 0.05 * look);
		p.head_rot = vec3(0.04 * bob, 0.15 * look, 0.0);
		// удар копытом раз в несколько секунд
		float sc = fract(t / (6.5 + 3.0 * hash11(var * 3.0)) + var);
		float stamp = win(sc, 0.0, 0.1, 0.03);
		p.hoof_fr += vec3(0.0, 0.13 * stamp, 0.06 * stamp);
		// хвост отгоняет мух
		float sw_t = smoothstep(0.55, 0.85, noise1(t * 0.4 + var * 11.0));
		p.tail_rot = vec3(0.08 + 0.1 * sw_t, (0.12 + 0.45 * sw_t) * sin(t * 4.5 + var * 30.0), 0.0);
		if (riderless) {
			// пасётся: голова к траве, жуёт, изредка переступает
			float g = fract(t / 21.0 + var);
			float graze = smoothstep(0.08, 0.22, g) * (1.0 - smoothstep(0.82, 0.95, g));
			// шея круто вниз, голова отвесно к траве (поворот головы складывается с шеей)
			p.neck_rot = mix(p.neck_rot, vec3(1.72, 0.12 * look, 0.0), graze);
			p.head_rot = mix(p.head_rot, vec3(-0.92 + 0.05 * sin(t * 7.0 + var * 9.0), 0.0, 0.0), graze);
			p.body_rot.x += 0.05 * graze;
			p.hoof_fl.z += 0.12 * graze;
			float stp = win(fract(t / 4.7 + var * 3.0), 0.0, 0.14, 0.04) * graze;
			p.hoof_fl += vec3(0.0, 0.1 * stp, 0.12 * stp * (1.0 - 2.0 * step(0.5, fract(t / 9.4 + var))));
		}
		if (st == RS_CHEER) {
			float c = sin(TAU * ph * 2.0);
			p.neck_rot = vec3(-0.15 + 0.15 * c, 0.1 * c, 0.0);
			p.head_rot = vec3(-0.2 + 0.1 * c, 0.0, 0.0);
			float paw = win(fract(ph * 2.0), 0.1, 0.6, 0.12);
			p.hoof_fl += vec3(0.0, 0.3 * paw, 0.1 * paw);
		}
		if (st == RS_MELEE) {
			p.body_rot.y = -0.12 * win(ph, 0.2, 0.8, 0.2);
		}
		p.seat_rot = vec3(0.0, 0.03 * sw, 0.0);
		p.torso_rot = vec3(0.02 * bob, 0.15 * look, 0.0);
		p.rhead_rot = vec3(0.0, 0.5 * (noise1(t * 0.12 + var * 7.0) - 0.5), 0.0);
	}

	if (riderless) {
		return p;
	}

	// ---- всадник: руки и оружие
	Xf T = rp_torso(p);
	rp_reins(p, T, ride_sway);
	if (st == RS_DYING || st == RS_DEAD) {
		p.hand_l = xf_pt(T, vec3(0.32, 0.95, 0.3) + R_OFF);
		p.hand_r = xf_pt(T, vec3(-0.34, 0.95, 0.35) + R_OFF);
		rp_weapon_t(p, T, vec3(-0.34, 0.95, 0.35), vec3(-0.6, -0.3, 0.7), vec3(0.0, 1.0, 0.0));
		p.hand_r = rp_wp(p, 0.0);
		p.elbow_l = T.b * vec3(0.5, -1.0, -0.2);
		p.elbow_r = T.b * vec3(-0.5, -1.0, -0.2);
		if (banner) {
			// знамя падает вместе со всадником (в сторону падения), а не исчезает
			rp_weapon_t(p, T, vec3(-0.34, 0.95, 0.35), vec3(-0.85, 0.15, 0.5), vec3(0.0, 1.0, 0.0));
			p.hand_r = rp_wp(p, 0.0);
		}
	} else if (st == RS_CHARGE || (st == RS_GALLOP && wk == WK_SABER && !banner)) {
		rp_charge_weapon(p, T, wk, banner);
		if (st == RS_GALLOP) {
			// сабля поднята, готова к удару
			rp_weapon_t(p, T, vec3(-0.26, 1.42, 0.22), vec3(0.03, 0.62, 0.78), vec3(0.0, 0.3, 1.0));
			p.hand_r = rp_wp(p, 0.0);
		}
	} else if (st == RS_MELEE) {
		float wind = seg01(ph, 0.0, 0.36);
		float hitk = snap(ph, 0.38, 0.52);
		float back = seg01(ph, 0.62, 1.0);
		p.torso_rot = vec3(-0.1 * wind * (1.0 - hitk) + 0.35 * hitk * (1.0 - back),
			-0.45 * wind * (1.0 - hitk) + 0.25 * hitk * (1.0 - back), 0.25 * hitk * (1.0 - back));
		T = rp_torso(p);
		rp_reins(p, T, 0.0);
		if (wk == WK_LANCE && !banner) {
			vec3 pos = mix(vec3(-0.17, 1.08, 0.0), vec3(-0.17, 1.1, -0.25), wind);
			pos = mix(pos, vec3(-0.12, 1.12, 0.5), hitk);
			pos = mix(pos, vec3(-0.17, 1.08, 0.0), back);
			rp_weapon_t(p, T, pos, vec3(0.13, -0.08 - 0.08 * hitk, 1.0), vec3(0.0, 1.0, 0.0));
			p.elbow_r = T.b * vec3(-1.0, -0.3, -0.2);
		} else {
			// рубит справа сверху вниз, вперёд-вправо
			vec3 g_pos = vec3(-0.24, 1.1, 0.25);
			vec3 g_dir = vec3(0.0, 0.8, 0.6);
			vec3 pos = mix(g_pos, vec3(-0.28, 1.72, -0.05), wind);
			vec3 dir = normalize(mix(g_dir, vec3(-0.15, 0.6, -0.78), wind));
			pos = mix(pos, vec3(-0.42, 0.95, 0.45), hitk);
			dir = normalize(mix(dir, vec3(-0.35, -0.6, 0.7), hitk));
			pos = mix(pos, g_pos, back);
			dir = normalize(mix(dir, g_dir, back));
			rp_weapon_t(p, T, pos, dir, vec3(0.0, 0.3, 1.0));
			p.elbow_r = T.b * vec3(-1.0, -0.2, -0.4);
		}
		p.hand_r = rp_wp(p, 0.0);
	} else if (st == RS_CHEER || st == RS_REAR) {
		float pump = sin(3.0 * TAU * ph);
		rp_weapon_t(p, T, vec3(-0.22, 1.98 + 0.06 * pump, 0.14), vec3(0.1, 1.0, 0.2 + 0.15 * pump), vec3(0.0, 0.0, 1.0));
		if (banner) {
			rp_weapon_t(p, T, vec3(-0.18, 1.5, 0.2), vec3(0.4 * pump, 1.0, 0.1), vec3(0.0, 0.0, 1.0));
		}
		p.hand_r = rp_wp(p, 0.0);
		p.elbow_r = T.b * vec3(-1.0, 0.0, -0.3);
		p.rhead_rot = vec3(-0.3, 0.0, 0.0);
	} else {
		rp_carry(p, T, wk, banner);
		if (st == RS_GALLOP && wk == WK_LANCE && !banner) {
			rp_weapon_t(p, T, vec3(-0.21, 1.02, 0.18), vec3(0.0, 1.0, 0.35), vec3(0.0, 0.0, 1.0));
			p.hand_r = rp_wp(p, 0.0);
		}
	}
	return p;
}

Xf rider_bone(int part, RPose p, inout vec3 v, float wgt, vec3 wind_m, float t, float var) {
	Xf X = xf_id();
	Xf B = rp_body(p);
	vec3 fwd = B.b * vec3(0.0, 0.0, 1.0);
	if (part == R_NECK) {
		// шея гнётся: поворот растёт от основания (вес 0) к затылку (вес 1)
		X = xf_mul(B, xf_piv(eul(p.neck_rot * smoothstep(0.0, 1.0, wgt)), RP_NECK, vec3(0.0)));
	} else if (part == R_HEAD) {
		X = xf_mul(xf_mul(B, xf_piv(eul(p.neck_rot), RP_NECK, vec3(0.0))), xf_piv(eul(p.head_rot), RP_HEAD, vec3(0.0)));
		// уши шевелятся
		v.z += wgt * 0.02 * sin(t * 2.0 + var * 40.0);
	} else if (part == R_FU_L || part == R_FL_L) {
		Xf up;
		Xf lo;
		ik_chain(RP_F_TOP_L, RP_F_KNEE_L, RP_F_HOOF_L, B, p.hoof_fl, fwd, 1.12, up, lo);
		X = part == R_FU_L ? up : lo;
	} else if (part == R_FU_R || part == R_FL_R) {
		Xf up;
		Xf lo;
		ik_chain(RP_F_TOP_R, RP_F_KNEE_R, RP_F_HOOF_R, B, p.hoof_fr, fwd, 1.12, up, lo);
		X = part == R_FU_R ? up : lo;
	} else if (part == R_HU_L || part == R_HL_L) {
		Xf up;
		Xf lo;
		ik_chain(RP_H_TOP_L, RP_H_HOCK_L, RP_H_HOOF_L, B, p.hoof_hl, -fwd, 1.12, up, lo);
		X = part == R_HU_L ? up : lo;
	} else if (part == R_HU_R || part == R_HL_R) {
		Xf up;
		Xf lo;
		ik_chain(RP_H_TOP_R, RP_H_HOCK_R, RP_H_HOOF_R, B, p.hoof_hr, -fwd, 1.12, up, lo);
		X = part == R_HU_R ? up : lo;
	} else if (part == R_TAIL) {
		// хвост гнётся по длине: поворот растёт к концу, по нему бежит волна
		vec3 tr = p.tail_rot * (0.45 + 0.9 * wgt);
		tr.y += 0.12 * wgt * sin(t * 3.0 - wgt * 3.0 + var * 17.0) * (1.0 + p.speed * 0.1);
		X = xf_mul(B, xf_piv(eul(tr), RP_TAIL, vec3(0.0)));
	} else if (part == R_R_PELVIS) {
		X = rp_seat(p);
		// полы кафтана отстают при скачке
		v.z -= wgt * wgt * 0.05 * min(p.speed, 9.0) / 9.0;
	} else if (part == R_R_TORSO) {
		X = rp_torso(p);
		// плащ полководца относит назад
		v.z -= wgt * wgt * (0.04 + 0.05 * min(p.speed, 9.0) / 9.0 + 0.02 * sin(t * 3.0 + v.y * 4.0));
	} else if (part == R_R_HEAD) {
		X = xf_mul(rp_torso(p), xf_piv(eul(p.rhead_rot), RP_R_HEAD, vec3(0.0)));
		v.z -= wgt * wgt * (0.06 + 0.06 * min(p.speed, 9.0) / 9.0) * (1.0 + 0.3 * sin(t * 5.0 + var * 9.0));
	} else if (part == R_R_UARM_L || part == R_R_FARM_L || part == R_R_ITEM) {
		Xf up;
		Xf lo;
		ik_chain(RP_R_SHOULDER_L, RP_R_ELBOW_L, RP_R_HAND_L, rp_torso(p), p.hand_l, p.elbow_l, 1.04, up, lo);
		X = part == R_R_UARM_L ? up : lo;
	} else if (part == R_R_UARM_R || part == R_R_FARM_R) {
		Xf up;
		Xf lo;
		ik_chain(RP_R_SHOULDER_R, RP_R_ELBOW_R, RP_R_HAND_R, rp_torso(p), p.hand_r, p.elbow_r, 1.04, up, lo);
		X = part == R_R_UARM_R ? up : lo;
	} else if (part == R_R_WEAPON || part == R_R_CLOTH) {
		X = xf_grip(p.w_rot, p.w_pos, RP_R_HAND_R, p.w_vis);
		if (part == R_R_CLOTH) {
			vec3 wl = transpose(p.w_rot) * wind_m;
			v = cloth_flutter(v, vec3(RP_R_HAND_R.x, v.y, RP_R_HAND_R.z - 0.02), wgt, wl, t, var * 31.0);
		} else {
			// туг (конский хвост на древке) качается
			v.z -= wgt * 0.08 * (0.5 + 0.5 * sin(t * 3.0 + var * 5.0));
		}
	} else {
		// корпус, попона, седло, ноги всадника
		X = B;
		// подол попоны качается от шага
		v.z -= wgt * 0.04 * sin(t * 3.0 + var * 7.0) * min(p.speed, 8.0) / 8.0;
		v.x *= 1.0 + wgt * 0.05 * min(p.speed, 8.0) / 8.0;
	}
	return xf_mul(rp_root(p), X);
}
