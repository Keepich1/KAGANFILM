// Свет толпы: общий живописный свет Ордо (painterly.gdshaderinc) — те же глобальные
// параметры, тёплый терминатор, цветная тень, контровой свет, — но граница света мягче
// в soft раз. У мелких круглых частей юнита (рукава, шапки, шея коня) жёсткая граница
// ложится по рёбрам низкополигональной сетки и даёт «гранёный», игрушечный вид.
// Подключать после painterly.gdshaderinc.

vec3 crowd_diffuse(vec3 n, vec3 l, vec3 light_color, float atten, float brush, bool directional, float soft_mul) {
	float ndl = dot(n, l);
	float soft = max(ordo_band_soft * soft_mul, 0.005);
	float b = (brush - 0.5) * ordo_brush_amount;
	float band = smoothstep(-soft, soft, ndl + b);
	float form = mix(0.62, 1.0, clamp(ndl * 0.5 + 0.5, 0.0, 1.0));
	float sh = clamp(atten + b * 0.6 * step(0.001, atten) * (1.0 - atten), 0.0, 1.0);
	float lit = band * form * sh;
	vec3 c = light_color * ordo_key_tint.rgb * lit;
	float term = band * (1.0 - band) * 4.0 * sh;
	c += light_color * ordo_terminator.rgb * ordo_terminator.a * term;
	if (directional) {
		float hidden = (1.0 - sh) * smoothstep(-0.2, 0.4, ndl);
		c += ordo_shadow_tint.rgb * hidden * length(light_color) * 0.25;
	}
	return c / PI;
}

#define CROWD_LIGHT(rim_strength, soft_mul) DIFFUSE_LIGHT += crowd_diffuse(NORMAL, LIGHT, LIGHT_COLOR, ATTENUATION, paint_brush_v, LIGHT_IS_DIRECTIONAL, soft_mul); SPECULAR_LIGHT += paint_rim(NORMAL, LIGHT, VIEW, LIGHT_COLOR, ATTENUATION, rim_strength)
