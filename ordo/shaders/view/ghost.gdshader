// Призрак постройки при расстановке (VIEW, GhostView): полупрозрачная модель цвета решения
// (зелёный — можно, красный — нельзя), светлый край по силуэту, косая штриховка «как на плане».
// Без теней и тумана: читается на любой земле и в любом свете (ТЗ 11.2). Цвет — на экземпляр.
shader_type spatial;
render_mode unshaded, blend_mix, cull_back, depth_draw_never, shadows_disabled, fog_disabled;

instance uniform vec4 ghost_col : source_color = vec4(0.35, 0.95, 0.5, 1.0);
uniform bool per_instance = false;    // MultiMesh звеньев стены: цвет звена — цвет экземпляра (COLOR)
uniform float opacity = 0.42;
uniform float rim = 1.4;
uniform float hatch = 0.22;

varying vec3 v_wp;
varying vec3 v_col;

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_col = per_instance ? COLOR.rgb : ghost_col.rgb;
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	float h = step(0.5, fract((v_wp.x + v_wp.y + v_wp.z) * 1.4));
	vec3 c = v_col * (0.75 + 0.25 * NORMAL.y);
	ALBEDO = mix(c, vec3(1.0), fres * 0.45);
	ALPHA = clamp(opacity + fres * rim * 0.4 + h * hatch * 0.35, 0.0, 0.9) * ghost_col.a;
}
