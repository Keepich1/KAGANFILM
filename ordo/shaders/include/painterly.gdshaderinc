// Общий живописный свет Ордо (ТЗ 11.1). Один на все шейдеры: здания, юниты, земля.
//
// Низкое солнце даёт тёплый ключевой свет, окружение (небо) — холодное
// сине-бирюзовое заполнение. Граница света мягкая и «нарисованная»: её ломает
// карта мазков ordo_brush. На границе — насыщенная тёплая полоса, как у
// живописцев. По краям силуэтов — контровой свет. Тени цветные, не чёрные.
//
// Параметры общие для проекта (Проект → Настройки → Shader Globals, ordo_*).
//
// Подключение в spatial-шейдере:
//
//   #include "res://shaders/include/painterly.gdshaderinc"
//   void vertex() { PAINT_VERTEX; }       // после своих сдвигов VERTEX/NORMAL
//   void fragment() { ...; paint_brush_v = paint_brush(v_world_pos, v_world_nrm); }
//   void light() { PAINT_LIGHT(1.0); }       // аргумент — сила контрового света
//
// Для толпы (MultiMesh) мировая позиция считается так же: MODEL_MATRIX уже
// включает трансформ экземпляра.

global uniform vec4 ordo_key_tint;      // цвет-множитель солнца
global uniform vec4 ordo_shadow_tint;   // цветная тень: добавка там, где солнце закрыто
global uniform vec4 ordo_terminator;    // тёплая полоса на границе света (rgb, a — сила)
global uniform vec4 ordo_rim_color;     // контровой свет (rgb, a — сила)
global uniform float ordo_band_soft;    // мягкость границы света
global uniform float ordo_brush_amount; // насколько мазок ломает границу света
global uniform float ordo_brush_scale;  // плотность мазков в мире, 1/м
global uniform sampler2D ordo_brush : hint_default_white, filter_linear_mipmap, repeat_enable;

varying float paint_brush_v;
varying vec3 v_world_pos;
varying vec3 v_world_nrm;

#define PAINT_VERTEX v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; v_world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz)

// Мазок 0..1 в мировых координатах (трипланарно, без растяжений на склонах).
float paint_brush(vec3 wp, vec3 wn) {
	vec3 w = pow(abs(wn), vec3(4.0));
	w /= (w.x + w.y + w.z + 1e-4);
	float s = ordo_brush_scale;
	float bx = texture(ordo_brush, wp.zy * s).r;
	float by = texture(ordo_brush, wp.xz * s * 0.8).r;
	float bz = texture(ordo_brush, wp.xy * s).r;
	return bx * w.x + by * w.y + bz * w.z;
}

// Рассеянный свет с нарисованной границей. Возвращает добавку к DIFFUSE_LIGHT.
// soft_mul — во сколько раз граница света мягче общей (мелкие круглые формы юнитов: ~2).
vec3 paint_diffuse_soft(vec3 n, vec3 l, vec3 light_color, float atten, float brush, bool directional, float soft_mul) {
	float ndl = dot(n, l);
	float soft = max(ordo_band_soft * soft_mul, 0.005);
	float b = (brush - 0.5) * ordo_brush_amount;
	float band = smoothstep(-soft, soft, ndl + b);
	// внутри освещённой стороны — мягкая лепка формы
	float form = mix(0.62, 1.0, clamp(ndl * 0.5 + 0.5, 0.0, 1.0));
	// тень от предметов тоже чуть «размазана» мазком
	float sh = clamp(atten + b * 0.6 * step(0.001, atten) * (1.0 - atten), 0.0, 1.0);
	float lit = band * form * sh;
	vec3 c = light_color * ordo_key_tint.rgb * lit;
	float term = band * (1.0 - band) * 4.0 * sh;
	c += light_color * ordo_terminator.rgb * ordo_terminator.a * term;
	if (directional) {
		// цветная тень: где солнце закрыто, но поверхность к нему повёрнута
		float hidden = (1.0 - sh) * smoothstep(-0.2, 0.4, ndl);
		c += ordo_shadow_tint.rgb * hidden * length(light_color) * 0.25;
	}
	return c / PI;
}

vec3 paint_diffuse(vec3 n, vec3 l, vec3 light_color, float atten, float brush, bool directional) {
	return paint_diffuse_soft(n, l, light_color, atten, brush, directional, 1.0);
}

// Контровой свет по краю силуэта, сильнее всего против солнца.
vec3 paint_rim(vec3 n, vec3 l, vec3 v, vec3 light_color, float atten, float strength) {
	float fres = pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 3.0);
	float facing = smoothstep(-0.25, 0.45, dot(n, l));
	float back = mix(0.35, 1.0, smoothstep(-0.3, 0.9, -dot(l, v)));
	return ordo_rim_color.rgb * ordo_rim_color.a * light_color * fres * facing * back
		* clamp(atten * 1.5, 0.0, 1.0) * strength / PI;
}

#define PAINT_LIGHT(rim_strength) DIFFUSE_LIGHT += paint_diffuse(NORMAL, LIGHT, LIGHT_COLOR, ATTENUATION, paint_brush_v, LIGHT_IS_DIRECTIONAL); SPECULAR_LIGHT += paint_rim(NORMAL, LIGHT, VIEW, LIGHT_COLOR, ATTENUATION, rim_strength)
