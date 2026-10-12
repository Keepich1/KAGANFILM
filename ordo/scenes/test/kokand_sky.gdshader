// Временное рисованное небо заката для проверки города Коканда (копия неба проверки лагеря;
// настоящее небо делает мир).
// Градиент от глубокой синевы к огненному горизонту, свечение вокруг солнца,
// полосы облаков с тёплым подбоем, дальние хребты силуэтом в дымке.
shader_type sky;

global uniform sampler2D ordo_brush : hint_default_white, filter_linear_mipmap, repeat_enable;

uniform vec3 c_top : source_color = vec3(0.07, 0.1, 0.2);
uniform vec3 c_mid : source_color = vec3(0.24, 0.29, 0.42);
uniform vec3 c_low : source_color = vec3(0.78, 0.5, 0.42);
uniform vec3 c_horizon : source_color = vec3(1.0, 0.66, 0.36);
uniform vec3 c_ridge : source_color = vec3(0.24, 0.24, 0.33);
uniform vec3 c_ridge_far : source_color = vec3(0.45, 0.4, 0.48);
uniform vec3 c_cloud_dark : source_color = vec3(0.3, 0.26, 0.36);
uniform vec3 c_cloud_lit : source_color = vec3(1.0, 0.62, 0.4);

float brush(vec2 p) {
	return texture(ordo_brush, p).r;
}

void sky() {
	vec3 d = EYEDIR;
	float y = d.y;
	float az = atan(d.x, d.z) / 6.2831853 + 0.5;
	vec3 sun = LIGHT0_DIRECTION;
	float sd = max(dot(d, sun), 0.0);
	float toward = pow(max(dot(normalize(d.xz + vec2(1e-4)), normalize(sun.xz + vec2(1e-4))), 0.0), 2.0);
	// градиент неба: у солнца горизонт горячее и шире
	vec3 col = mix(c_horizon, c_low, smoothstep(0.0, 0.06 + 0.1 * toward, y));
	col = mix(col, c_mid, smoothstep(0.08, 0.32, y));
	col = mix(col, c_top, smoothstep(0.3, 0.9, y));
	col = mix(col, col * vec3(0.72, 0.68, 0.82), (1.0 - toward) * smoothstep(0.0, 0.2, y) * 0.6);
	col += LIGHT0_COLOR * (pow(sd, 6.0) * 0.3 + pow(sd, 90.0) * 0.5);
	// облака: вытянутые мазки, подбой светлее к солнцу
	float band = smoothstep(0.04, 0.1, y) * (1.0 - smoothstep(0.16, 0.3, y));
	// множители азимута целые — иначе на севере шов (az переходит 1 → 0)
	vec2 cp = vec2(az * 1.0, y * 2.4 + 0.2);
	float c1 = textureLod(ordo_brush, cp, 5.0).r * 0.6 + textureLod(ordo_brush, cp * 2.0 + 0.37, 3.5).r * 0.4;
	float c2 = textureLod(ordo_brush, vec2(az * 4.0 + 0.3, y * 6.0), 2.0).r;
	float cloud = smoothstep(0.52, 0.58, c1 + (c2 - 0.5) * 0.08) * band;
	vec3 cc = mix(c_cloud_dark, c_cloud_lit, clamp(toward * 0.9 + (c2 - 0.5) * 0.4, 0.0, 1.0));
	cc += LIGHT0_COLOR * pow(sd, 10.0) * 0.6;
	col = mix(col, cc, cloud * 0.85);
	if (LIGHT0_ENABLED && sd > 0.99975) {
		col = mix(col, vec3(1.7, 1.3, 0.85), smoothstep(0.99975, 0.9999, sd));
	}
	// дальние хребты: два плана силуэтов в дымке
	float h_far = 0.035 + 0.03 * brush(vec2(az * 2.0, 0.37)) + 0.012 * brush(vec2(az * 9.0, 0.71));
	float h_near = 0.012 + 0.022 * brush(vec2(az * 3.0 + 0.5, 0.11)) * (0.6 + 0.4 * brush(vec2(az * 13.0, 0.2)));
	vec3 rf = mix(c_ridge_far, c_horizon * 0.8, toward * 0.45);
	vec3 rn = mix(c_ridge, c_ridge_far * 0.9, toward * 0.3);
	col = mix(col, rf, step(y, h_far));
	col = mix(col, rn, step(y, h_near));
	if (y < 0.0) {
		col = mix(rn, vec3(0.12, 0.1, 0.12), smoothstep(0.0, -0.3, y));
	}
	COLOR = col;
}
