// Рисованное небо заката (ТЗ 11.1): глубокий сине-бирюзовый зенит → тёплый оранжево-розовый
// горизонт на западе-юго-западе, солнечный диск со свечением, облака мазками — снизу
// подсвечены тёплым, сверху холодные; дальние хребты Тянь-Шаня слоями воздушной
// перспективы, снег на вершинах ловит последний свет. Без TIME — небо считается один раз.
shader_type sky;
render_mode use_debanding;

global uniform sampler2D ordo_brush : hint_default_white, filter_linear_mipmap, repeat_enable;

group_uniforms gradient;
uniform vec4 zenith_color : source_color = vec4(0.04, 0.09, 0.17, 1.0);
uniform vec4 upper_color : source_color = vec4(0.12, 0.27, 0.36, 1.0);
uniform vec4 horizon_sun : source_color = vec4(1.0, 0.56, 0.26, 1.0);
uniform vec4 horizon_rose : source_color = vec4(0.86, 0.47, 0.44, 1.0);
uniform vec4 horizon_cool : source_color = vec4(0.38, 0.40, 0.55, 1.0);
uniform vec4 ground_haze : source_color = vec4(0.22, 0.2, 0.22, 1.0);
uniform float horizon_height = 0.1;     // толщина тёплой полосы, рад
uniform float sun_spread = 1.1;          // ширина тёплого сектора по азимуту, рад
uniform float sky_energy = 1.0;
uniform float stroke_amount = 0.035;     // насколько мазки ломают полосы градиента
group_uniforms;

group_uniforms sun;
uniform vec4 sun_color : source_color = vec4(1.0, 0.82, 0.58, 1.0);
uniform float sun_radius = 0.0105;       // рад (≈0,6°)
uniform float sun_energy = 22.0;
uniform float glow_energy = 1.4;
uniform float glow_tight = 90.0;
uniform float glow_wide = 7.0;
group_uniforms;

group_uniforms clouds;
uniform vec4 cloud_lit : source_color = vec4(1.0, 0.62, 0.42, 1.0);
uniform vec4 cloud_gold : source_color = vec4(1.0, 0.82, 0.5, 1.0);
uniform vec4 cloud_shade : source_color = vec4(0.30, 0.28, 0.40, 1.0);
uniform vec4 cloud_far : source_color = vec4(0.44, 0.38, 0.48, 1.0);
uniform float cloud_cover = 0.52;
uniform float cloud_soft = 0.16;
uniform float cloud_scale = 0.9;
group_uniforms;

group_uniforms mountains;
uniform vec4 mount_far : source_color = vec4(0.50, 0.50, 0.66, 1.0);
uniform vec4 mount_mid : source_color = vec4(0.30, 0.31, 0.47, 1.0);
uniform vec4 mount_near : source_color = vec4(0.17, 0.18, 0.28, 1.0);
uniform vec4 snow_lit : source_color = vec4(0.98, 0.7, 0.6, 1.0);
uniform vec4 snow_shade : source_color = vec4(0.56, 0.60, 0.78, 1.0);
uniform float mount_height = 1.4;        // общий множитель высоты хребтов
uniform float mount_haze = 0.62;
group_uniforms;


float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Периодический шум по азимуту (период P клеток)
float pnoise1(float x, float P, float seed) {
	float i = floor(x);
	float f = fract(x);
	float u = f * f * (3.0 - 2.0 * f);
	return mix(hash11(mod(i, P) + seed), hash11(mod(i + 1.0, P) + seed), u);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm2(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int o = 0; o < 5; o++) {
		s += a * noise2(p);
		p = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6)) * p + vec2(3.1, 1.7);
		a *= 0.5;
	}
	return s;
}

// Гребень хребта по азимуту t (0..1 — полный круг)
float ridge(float t, float period, float seed) {
	float s = 0.0;
	float a = 0.55;
	float f = 1.0;
	for (int o = 0; o < 6; o++) {
		float n = pnoise1(t * period * f, period * f, seed + float(o) * 17.0);
		n = 1.0 - abs(n * 2.0 - 1.0);
		s += a * n * n;
		a *= 0.5;
		f *= 2.0;
	}
	return s;
}

float gauss_az(float az, float center, float width) {
	float d = mod(az - center + 540.0, 360.0) - 180.0;
	return exp(-(d * d) / (width * width));
}

// Высота дальних хребтов по направлению (градусы азимута, 0 — север, 90 — восток)
float range_profile(float az) {
	return 0.22 + 0.95 * gauss_az(az, 352.0, 45.0) + 1.05 * gauss_az(az, 308.0, 30.0)
		+ 0.6 * gauss_az(az, 40.0, 30.0) + 0.3 * gauss_az(az, 140.0, 40.0) + 0.25 * gauss_az(az, 200.0, 30.0);
}

// Высота гребня слоя k (градусы) и его сглаженная версия (для света склонов)
float mount_h(int k, float t, float prof) {
	if (k == 0) return prof * (2.4 + 4.2 * ridge(t, 20.0, 3.0));
	if (k == 1) return prof * (1.2 + 2.6 * ridge(t, 31.0, 11.0)) + 0.4;
	return 0.4 + prof * 0.3 + 1.3 * ridge(t, 47.0, 23.0) * (0.4 + 0.6 * prof);
}

float ridge_lo(float t, float period, float seed) {
	float s = 0.0;
	float a = 0.55;
	float f = 1.0;
	for (int o = 0; o < 3; o++) {
		float n = pnoise1(t * period * f, period * f, seed + float(o) * 17.0);
		n = 1.0 - abs(n * 2.0 - 1.0);
		s += a * n * n;
		a *= 0.5;
		f *= 2.0;
	}
	return s;
}

float mount_h_lo(int k, float t, float prof) {
	if (k == 0) return prof * (2.4 + 4.2 * ridge_lo(t, 20.0, 3.0));
	if (k == 1) return prof * (1.2 + 2.6 * ridge_lo(t, 31.0, 11.0)) + 0.4;
	return 0.4 + prof * 0.3 + 1.3 * ridge_lo(t, 47.0, 23.0) * (0.4 + 0.6 * prof);
}

vec3 horizon_tint(float da) {
	// da — разница азимутов с солнцем, рад (0 — под солнцем)
	float a = abs(da);
	vec3 c = mix(horizon_rose.rgb, horizon_cool.rgb, smoothstep(0.9, 2.7, a));
	return mix(c, horizon_sun.rgb, exp(-(a * a) / (sun_spread * sun_spread)));
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 s = normalize(LIGHT0_DIRECTION);
	float elev = asin(clamp(d.y, -1.0, 1.0));
	float az = atan(d.x, -d.z);                 // 0 — север, +π/2 — восток
	float saz = atan(s.x, -s.z);
	float sel = asin(clamp(s.y, -1.0, 1.0));
	float da = mod(az - saz + 3.0 * 3.14159265, TAU) - 3.14159265;
	float cs = dot(d, s);
	float t = az / TAU + 0.5;                   // 0..1 по кругу

	// --- мазки: горизонтальные «полосы кисти» ломают градиент
	vec2 buv = vec2(t * 3.0, elev * 2.2);
	float st = texture(ordo_brush, buv).r;
	float st2 = texture(ordo_brush, vec2(t * 7.0 + 0.3, elev * 5.0)).r;
	float e = elev + (st - 0.5) * stroke_amount + (st2 - 0.5) * stroke_amount * 0.5;

	// --- градиент неба
	vec3 hz = horizon_tint(da);
	float hband = exp(-max(e, 0.0) / horizon_height);
	vec3 upper = mix(upper_color.rgb, zenith_color.rgb, smoothstep(0.15, 1.25, e));
	// тёплое свечение поднимается выше над солнцем
	float sun_side = exp(-(da * da) / (sun_spread * sun_spread * 1.6));
	upper = mix(upper, mix(upper, horizon_rose.rgb, 0.4), sun_side * exp(-max(e, 0.0) / 0.3));
	vec3 col = mix(upper, hz, hband);
	// светлая дымка у самого горизонта
	col = mix(col, hz * 1.15 + vec3(0.04), exp(-max(e, 0.0) / 0.03) * 0.5);

	// --- облака мазками: длинные горизонтальные гряды (азимут × высота), гуще у заката
	float cloud_a = 0.0;
	vec3 cloud_c = vec3(0.0);
	float e_deg = degrees(e);
	if (e_deg > -1.0) {
		// чем ближе к горизонту, тем «площе» облака (перспектива слоя)
		float squash = mix(3.2, 1.0, smoothstep(2.0, 30.0, e_deg));
		vec2 cq = vec2(t * 26.0 * cloud_scale, e_deg * 0.33 * squash);
		float dens = fbm2(cq * vec2(0.55, 1.0) + vec2(3.0, 0.0));
		float br = texture(ordo_brush, vec2(t * 9.0, e_deg * 0.05 * squash) + vec2(0.31, 0.12)).r;
		float br2 = texture(ordo_brush, vec2(t * 23.0, e_deg * 0.11 * squash) + vec2(0.7, 0.4)).r;
		dens = dens * 0.85 + (br - 0.5) * 0.28 + (br2 - 0.5) * 0.12;
		// гряды лежат полосами по высоте
		float band = smoothstep(1.0, 3.5, e_deg) * (1.0 - smoothstep(20.0, 38.0, e_deg));
		band *= 0.75 + 0.25 * sin(e_deg * 0.55 + 1.3);
		float cov = cloud_cover - 0.1 * sun_side;
		cloud_a = smoothstep(cov, cov + cloud_soft, dens) * band;
		// нижняя кромка гряды (плотность ниже меньше) — подсвечена снизу
		float dens_lo = fbm2(vec2(cq.x * 0.55 + 3.0, (e_deg - 0.6) * 0.33 * squash)) * 0.85 + (br - 0.5) * 0.28;
		float under = clamp((dens - dens_lo) * 7.0 + 0.35, 0.0, 1.0);
		float near_sun = pow(max(cs, 0.0), 4.0);
		float facing = 0.25 + 0.75 * exp(-(da * da) / 1.6);
		vec3 lit = mix(cloud_lit.rgb, cloud_gold.rgb, near_sun) * (0.55 + 1.2 * near_sun);
		vec3 shade = mix(cloud_far.rgb, cloud_shade.rgb, smoothstep(2.0, 18.0, e_deg));
		cloud_c = mix(shade, lit, clamp(under * facing + near_sun * 0.35, 0.0, 1.0));
		// тонкие края против солнца — золотая кайма
		float thin = 1.0 - smoothstep(cov, cov + cloud_soft * 3.0, dens);
		cloud_c += cloud_gold.rgb * thin * pow(max(cs, 0.0), 12.0) * 2.0;
		cloud_c *= 0.9 + 0.2 * br2;
	}

	// --- солнце: диск и свечение
	float ang = acos(clamp(cs, -1.0, 1.0));
	float disc = 1.0 - smoothstep(sun_radius * 0.82, sun_radius, ang);
	float glow = pow(max(cs, 0.0), glow_tight) * 1.3 + pow(max(cs, 0.0), glow_wide) * 0.12;
	col += sun_color.rgb * glow * glow_energy;
	col = mix(col, sun_color.rgb * sun_energy, disc * (1.0 - cloud_a * 0.85));
	col = mix(col, cloud_c, cloud_a);

	// --- дальние хребты: три слоя воздушной перспективы
	float azd = degrees(az);
	azd = azd < 0.0 ? azd + 360.0 : azd;
	float prof = range_profile(azd) * mount_height;
	float el_deg = degrees(elev);
	for (int k = 0; k < 3; k++) {
		float h = mount_h(k, t, prof);
		if (el_deg < h + 0.05) {
			// свет склона по сглаженному гребню: где хребет понижается к солнцу — освещён
			float dt = 0.004;
			float slope = (mount_h_lo(k, t + dt, prof) - mount_h_lo(k, t - dt, prof)) / (2.0 * dt);
			float side = -sign(da) * slope;
			float front = smoothstep(2.6, 0.8, abs(da));           // против солнца вершины светятся прямо
			float lit = clamp(smoothstep(-30.0, 50.0, side) * 0.8 + front * 0.35, 0.0, 1.0);
			// борозды-кулуары: вертикальные мазки
			float gully = texture(ordo_brush, vec2(t * 40.0 + float(k) * 0.37, el_deg * 0.08)).r;
			vec3 base = (k == 0) ? mount_far.rgb : ((k == 1) ? mount_mid.rgb : mount_near.rgb);
			vec3 rockc = base * mix(0.82, 1.1, lit) * mix(0.9, 1.06, gully);
			// снег: верх высоких гребней, языками вниз
			float snowline = (k == 0) ? 3.0 : 2.6;
			float depth = (h - snowline) * ((k == 0) ? 0.6 : 0.35);
			float sn = 0.0;
			if (k < 2) {
				float top = h - depth + (gully - 0.5) * 1.2;
				sn = smoothstep(snowline, snowline + 0.6, h) * smoothstep(top - 0.15, top + 0.15, el_deg);
			}
			vec3 snowc = mix(snow_shade.rgb, snow_lit.rgb, lit) * ((k == 0) ? 1.0 : 0.85);
			vec3 mc = mix(rockc, snowc, sn);
			// дымка: дальние слои почти тонут в воздухе, у подножия — туман
			float haze = (k == 0) ? mount_haze : ((k == 1) ? mount_haze * 0.65 : mount_haze * 0.4);
			haze = mix(haze, 1.0, exp(-max(el_deg, 0.0) / ((k == 2) ? 0.5 : 0.9)) * 0.8);
			mc = mix(mc, hz * 0.95, haze);
			float edge = smoothstep(h + 0.05, h - 0.05, el_deg);
			col = mix(col, mc, edge);
		}
	}

	// --- ниже горизонта — тёмная дымка земли (закрыта рельефом, но без провалов)
	if (elev < 0.0) {
		vec3 g = mix(hz * 0.55, ground_haze.rgb, smoothstep(0.0, 0.25, -elev));
		col = mix(col, g, smoothstep(0.0, 0.02, -elev));
	}

	COLOR = col * sky_energy;
}
