// Толпа: общая математика поз — жёсткие преобразования, ИК двух костей, циклы шага.
//
// Кость — Xf: p' = b * p + o (b — поворот, иногда с равномерным растяжением ноги).
// Все цели (стопы, кисти, оружие) задаются в осях модели до корневого поворота:
// +Z — вперёд, +X — левая сторона юнита, Y — вверх (CONTRACT §2).

struct Xf {
	mat3 b;
	vec3 o;
};

Xf xf_id() {
	return Xf(mat3(1.0), vec3(0.0));
}

vec3 xf_pt(Xf x, vec3 p) {
	return x.b * p + x.o;
}

// a после c
Xf xf_mul(Xf a, Xf c) {
	return Xf(a.b * c.b, a.b * c.o + a.o);
}

// Поворот r вокруг точки piv и сдвиг off
Xf xf_piv(mat3 r, vec3 piv, vec3 off) {
	return Xf(r, piv - r * piv + off);
}

// Предмет: точка хвата g (в позе покоя) переносится в pos, оси — rot; vis = 0 прячет (сжимает в точку)
Xf xf_grip(mat3 rot, vec3 pos, vec3 g, float vis) {
	mat3 b = rot * vis;
	return Xf(b, pos - b * g);
}

mat3 rot_x(float a) {
	float c = cos(a), s = sin(a);
	return mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, c, s), vec3(0.0, -s, c));
}

mat3 rot_y(float a) {
	float c = cos(a), s = sin(a);
	return mat3(vec3(c, 0.0, -s), vec3(0.0, 1.0, 0.0), vec3(s, 0.0, c));
}

mat3 rot_z(float a) {
	float c = cos(a), s = sin(a);
	return mat3(vec3(c, s, 0.0), vec3(-s, c, 0.0), vec3(0.0, 0.0, 1.0));
}

// Углы (x — наклон вперёд для того, что смотрит вверх; y — поворот влево; z — крен к правому боку)
mat3 eul(vec3 e) {
	return rot_y(e.y) * rot_x(e.x) * rot_z(e.z);
}

// Кратчайший поворот единичного a в единичный b
mat3 rot_ft(vec3 a, vec3 b) {
	vec3 v = cross(a, b);
	float c = dot(a, b);
	float k = 1.0 / max(1.0 + c, 1e-4);
	return mat3(
		vec3(v.x * v.x * k + c, v.y * v.x * k + v.z, v.z * v.x * k - v.y),
		vec3(v.x * v.y * k - v.z, v.y * v.y * k + c, v.z * v.y * k + v.x),
		vec3(v.x * v.z * k + v.y, v.y * v.z * k - v.x, v.z * v.z * k + c));
}

// Базис по оси y (вдоль предмета) и подсказке направления z
mat3 basis_yz(vec3 y, vec3 zref) {
	vec3 yy = normalize(y);
	vec3 xx = normalize(cross(yy, zref));
	vec3 zz = cross(xx, yy);
	return mat3(xx, yy, zz);
}

// ИК двух костей: сустав между s (плечо/бедро) и t (кисть/стопа), сгиб в сторону pole.
vec3 ik_joint(vec3 s, vec3 t, float l1, float l2, vec3 pole) {
	vec3 d = t - s;
	float dl = clamp(length(d), abs(l1 - l2) + 1e-3, l1 + l2 - 1e-4);
	vec3 u = length(d) > 1e-5 ? normalize(d) : vec3(0.0, -1.0, 0.0);
	float x = (l1 * l1 - l2 * l2 + dl * dl) / (2.0 * dl);
	float h = sqrt(max(l1 * l1 - x * x, 0.0));
	vec3 pv = pole - u * dot(pole, u);
	pv = length(pv) > 1e-5 ? normalize(pv) : vec3(0.0, 0.0, 1.0);
	return s + u * x + pv * h;
}

// Цепь из двух костей (s0 → j0 → e0 в позе покоя) под родителем par: кость up и low.
// stretch — допустимое растяжение (нога дотягивается до земли на краю шага).
void ik_chain(vec3 s0, vec3 j0, vec3 e0, Xf par, vec3 target, vec3 pole, float stretch, out Xf up, out Xf low) {
	vec3 s = xf_pt(par, s0);
	float l1 = length(j0 - s0);
	float l2 = length(e0 - j0);
	float k = clamp(length(target - s) / (l1 + l2), 1.0, stretch);
	vec3 j = ik_joint(s, target, l1 * k, l2 * k, pole);
	vec3 e = j + normalize(target - j) * l2 * k;
	mat3 ru = rot_ft(normalize(par.b * (j0 - s0)), normalize(j - s)) * par.b;
	up = Xf(ru * k, s - ru * k * s0);
	mat3 rl = rot_ft(normalize(ru * (e0 - j0)), normalize(e - j)) * ru;
	low = Xf(rl * k, j - rl * k * j0);
}

// ---------------------------------------------------------------- время и кривые

float hash11(float x) {
	return fract(sin(x * 127.1 + 311.7) * 43758.5453);
}

// Плавный шум 0..1 по времени (для взглядов, смены веса, ушей)
float noise1(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash11(i), hash11(i + 1.0), f);
}

// Отрезок 0..1 с плавными краями
float seg01(float x, float a, float b) {
	return smoothstep(a, b, x);
}

// Окно: 0 → 1 на [a, a+f], 1 → 0 на [b-f, b]
float win(float x, float a, float b, float f) {
	return smoothstep(a, a + f, x) * (1.0 - smoothstep(b - f, b, x));
}

// Быстрый удар: резкий разгон и мягкое торможение
float snap(float x, float a, float b) {
	float t = clamp((x - a) / (b - a), 0.0, 1.0);
	return 1.0 - pow(1.0 - t, 3.0);
}

// Стопа или копыто на цикле шага. s — фаза ноги (0 — касание), duty — доля опоры.
// Возврат: x — сдвиг вдоль хода от середины шага, y — подъём.
// В опоре стопа идёт назад ровно со скоростью тела: при фазе = путь / stride нет скольжения.
// В переносе — кривая Эрмита с той же скоростью на концах (ступня не «тормозит» у земли).
vec2 gait_foot(float s, float duty, float stride, float lift) {
	float L = duty * stride;
	if (s < duty) {
		return vec2(L * (0.5 - s / duty), 0.0);
	}
	float t = (s - duty) / (1.0 - duty);
	float m = -L / duty * (1.0 - duty);
	float t2 = t * t;
	float t3 = t2 * t;
	float z = (2.0 * t3 - 3.0 * t2 + 1.0) * (-0.5 * L) + (t3 - 2.0 * t2 + t) * m
		+ (-2.0 * t3 + 3.0 * t2) * (0.5 * L) + (t3 - t2) * m;
	float y = lift * sin(PI * pow(t, 0.75));
	return vec2(z, y);
}

// Полотно знамени или вымпела: разворот по видимому ветру вокруг древка и бегущая волна.
// v — вершина в позе покоя (полотно уходит от древка в −Z), axis — точка на древке,
// wgt — 0 у древка … 1 на свободном краю, wind — видимый ветер в осях древка (м/с).
vec3 cloth_flutter(vec3 v, vec3 axis, float wgt, vec3 wind, float t, float seed) {
	float ws = length(wind.xz);
	vec2 dir = ws > 1e-3 ? wind.xz / ws : vec2(0.0, -1.0);
	float str = clamp(ws / 7.0, 0.0, 1.0);
	float yaw = atan(-dir.x, -dir.y) * smoothstep(0.03, 0.35, str);
	float dist = axis.z - v.z;
	float ph = dist * 4.5 - t * (4.0 + 8.0 * str) + seed;
	float amp = (0.035 + 0.11 * str) * wgt;
	vec3 q = v - axis;
	q.x += amp * sin(ph) + 0.025 * wgt * sin(ph * 0.47 + 1.3 + seed);
	q.y += 0.035 * wgt * sin(ph * 0.7 + 0.5);
	// без ветра полотно обвисает вдоль древка
	float slack = 1.0 - str;
	q.y -= slack * 0.45 * wgt * wgt;
	q.z *= 1.0 - slack * 0.45 * wgt - 0.05 * wgt * (0.5 + 0.5 * sin(ph));
	return axis + rot_y(yaw) * q;
}
