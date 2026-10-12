// Свет толпы: общий живописный свет Ордо (painterly.gdshaderinc) — те же глобальные
// параметры, тёплый терминатор, цветная тень, контровой свет, — но граница света мягче
// в soft раз. У мелких круглых частей юнита (рукава, шапки, шея коня) жёсткая граница
// ложится по рёбрам низкополигональной сетки и даёт «гранёный», игрушечный вид.
// Подключать после painterly.gdshaderinc.

vec3 crowd_diffuse(vec3 n, vec3 l, vec3 light_color, float atten, float brush, bool directional, float soft_mul) {
	return paint_diffuse_soft(n, l, light_color, atten, brush, directional, soft_mul);
}

#define CROWD_LIGHT(rim_strength, soft_mul) DIFFUSE_LIGHT += crowd_diffuse(NORMAL, LIGHT, LIGHT_COLOR, PAINT_ATTEN, paint_brush_v, LIGHT_IS_DIRECTIONAL, soft_mul); SPECULAR_LIGHT += paint_rim(NORMAL, LIGHT, VIEW, LIGHT_COLOR, PAINT_ATTEN, rim_strength)
