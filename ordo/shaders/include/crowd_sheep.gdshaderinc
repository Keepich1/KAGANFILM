// Толпа: курдючная овца (skeleton 2). Состояния — AnimSpec.Sheep.
// Ноги — по одной кости: поворот к цели копыта и лёгкое растяжение, чтобы копыто стояло на земле.

const int SS_GRAZE = 0;
const int SS_WALK = 1;
const int SS_RUN = 2;
const int SS_DYING = 3;
const int SS_DEAD = 4;

const float S_STRIDE_WALK = 0.7;
const float S_STRIDE_RUN = 1.6;

struct SPose {
	vec3 root_rot;
	vec3 root_piv;
	vec3 root_off;
	vec3 body_rot;
	vec3 body_off;
	vec3 head_rot;
	vec3 head_off;
	vec3 tail_rot;
	vec3 foot_fl;
	vec3 foot_fr;
	vec3 foot_hl;
	vec3 foot_hr;
};

SPose sheep_pose(int st, float ph, float aux, float var, float t) {
	SPose p;
	p.root_rot = vec3(0.0);
	p.root_piv = vec3(0.0);
	p.root_off = vec3(0.0);
	p.body_rot = vec3(0.0);
	p.body_off = vec3(0.0);
	p.head_rot = vec3(0.0);
	p.head_off = vec3(0.0);
	p.tail_rot = vec3(0.0);
	vec3 fl = vec3(SP_LEG_FL.x, 0.0, SP_LEG_FL.z);
	vec3 fr = vec3(SP_LEG_FR.x, 0.0, SP_LEG_FR.z);
	vec3 hl = vec3(SP_LEG_HL.x, 0.0, SP_LEG_HL.z);
	vec3 hr = vec3(SP_LEG_HR.x, 0.0, SP_LEG_HR.z);
	p.foot_fl = fl;
	p.foot_fr = fr;
	p.foot_hl = hl;
	p.foot_hr = hr;
	if (st == SS_WALK || st == SS_RUN) {
		bool run = st == SS_RUN;
		float stride = run ? S_STRIDE_RUN : S_STRIDE_WALK;
		float duty = run ? 0.4 : 0.6;
		vec4 off = run ? vec4(0.0, 0.5, 0.5, 0.0) : vec4(0.25, 0.75, 0.0, 0.5);
		float lift = run ? 0.12 : 0.06;
		vec2 a = gait_foot(fract(ph - off.x), duty, stride, lift);
		vec2 b = gait_foot(fract(ph - off.y), duty, stride, lift);
		vec2 c = gait_foot(fract(ph - off.z), duty, stride, lift);
		vec2 d = gait_foot(fract(ph - off.w), duty, stride, lift);
		p.foot_fl = fl + vec3(0.0, a.y, a.x);
		p.foot_fr = fr + vec3(0.0, b.y, b.x);
		p.foot_hl = hl + vec3(0.0, c.y, c.x);
		p.foot_hr = hr + vec3(0.0, d.y, d.x);
		float w = TAU * ph;
		p.body_off = vec3(0.0, (run ? 0.03 : 0.01) * cos(2.0 * w) - (run ? 0.03 : 0.0), 0.0);
		p.body_rot = vec3(run ? 0.05 * sin(w) : 0.0, 0.0, 0.02 * sin(w));
		p.head_rot = vec3(-0.05 + 0.06 * cos(2.0 * w), 0.06 * sin(w), 0.0);
		p.tail_rot = vec3(0.0, 0.25 * sin(w * 2.0), 0.0);
	} else if (st == SS_DYING || st == SS_DEAD) {
		float k = st == SS_DEAD ? 1.0 : ph;
		float sd = aux < 0.5 ? 1.0 : -1.0;
		float buck = seg01(k, 0.0, 0.4);
		float tt = clamp((k - 0.25) / 0.6, 0.0, 1.0);
		float roll = tt * tt;
		p.body_off = vec3(0.0, -0.2 * buck, 0.0);
		p.head_rot = vec3(0.4 * buck - 0.2 * roll, 0.3 * sd * roll, 0.0);
		vec3 tuck = vec3(0.0, 0.18, 0.0);
		p.foot_fl = mix(fl, fl + tuck + vec3(0.0, 0.0, -0.08), buck);
		p.foot_fr = mix(fr, fr + tuck + vec3(0.0, 0.0, -0.08), buck);
		p.foot_hl = mix(hl, hl + tuck + vec3(0.0, 0.0, 0.08), buck);
		p.foot_hr = mix(hr, hr + tuck + vec3(0.0, 0.0, 0.08), buck);
		// на боку ноги полусогнуты, вдоль тела
		vec3 o = vec3(0.0, -0.2 * buck, 0.0);
		p.foot_fl = mix(p.foot_fl, vec3(fl.x, 0.02, fl.z + 0.16) + o, roll);
		p.foot_fr = mix(p.foot_fr, vec3(fr.x, 0.06, fr.z + 0.1) + o, roll);
		p.foot_hl = mix(p.foot_hl, vec3(hl.x, 0.02, hl.z - 0.16) + o, roll);
		p.foot_hr = mix(p.foot_hr, vec3(hr.x, 0.06, hr.z - 0.1) + o, roll);
		p.root_piv = vec3(0.22 * sd, 0.0, 0.0);
		p.root_rot = vec3(0.0, 0.0, -sd * 1.32 * roll);
		p.root_off = vec3(0.0, -0.04 * roll, 0.0);
	} else {
		// пасётся: голова к траве, жуёт, изредка шаг, хвост дёргается
		float g = fract(t / 13.0 + var);
		float up = win(g, 0.55, 0.75, 0.05);  // поднимает голову, оглядывается
		float chew = sin(t * 9.0 + var * 20.0);
		p.head_rot = mix(vec3(0.72 + 0.04 * chew, 0.15 * sin(t * 0.3 + var), 0.0), vec3(-0.1, 0.5 * sin(t * 0.7 + var * 5.0), 0.0), up);
		p.head_off = mix(vec3(0.0, -0.13, 0.09), vec3(0.0), up);
		p.body_rot = vec3(0.08 * (1.0 - up), 0.0, 0.0);
		float s = fract(t / 3.1 + var * 7.0);
		float stp = win(s, 0.0, 0.18, 0.05) * (1.0 - up);
		int leg = int(floor(fract(t / 12.4 + var * 3.0) * 4.0));
		vec3 dstep = vec3(0.0, 0.05 * sin(PI * clamp(s / 0.18, 0.0, 1.0)), 0.06 * stp);
		if (leg == 0) {
			p.foot_fl += dstep;
		} else if (leg == 1) {
			p.foot_fr += dstep;
		} else if (leg == 2) {
			p.foot_hl += dstep;
		} else {
			p.foot_hr += dstep;
		}
		p.tail_rot = vec3(0.0, 0.25 * sin(t * 6.0) * smoothstep(0.7, 0.9, noise1(t * 0.5 + var * 13.0)), 0.0);
	}
	return p;
}

Xf sheep_leg(vec3 top, SPose p, Xf B, vec3 foot) {
	vec3 s = xf_pt(B, top);
	vec3 d = foot - s;
	float L0 = top.y;
	float k = clamp(length(d) / L0, 0.75, 1.12);
	mat3 r = rot_ft(normalize(B.b * vec3(0.0, -1.0, 0.0)), normalize(d)) * B.b;
	return Xf(r * k, s - r * k * top);
}

Xf sheep_bone(int part, SPose p, inout vec3 v, float wgt, float t, float var) {
	Xf B = xf_piv(eul(p.body_rot), SP_BODY, p.body_off);
	Xf X = B;
	if (part == S_HEAD) {
		X = xf_mul(B, xf_piv(eul(p.head_rot), SP_HEAD, p.head_off));
	} else if (part == S_LEG_FL) {
		X = sheep_leg(SP_LEG_FL, p, B, p.foot_fl);
	} else if (part == S_LEG_FR) {
		X = sheep_leg(SP_LEG_FR, p, B, p.foot_fr);
	} else if (part == S_LEG_HL) {
		X = sheep_leg(SP_LEG_HL, p, B, p.foot_hl);
	} else if (part == S_LEG_HR) {
		X = sheep_leg(SP_LEG_HR, p, B, p.foot_hr);
	} else if (part == S_TAIL) {
		X = xf_mul(B, xf_piv(eul(p.tail_rot), SP_TAIL, vec3(0.0)));
	}
	return xf_mul(xf_piv(eul(p.root_rot), p.root_piv, p.root_off), X);
}
