// Кольцо выделения под юнитом (ТЗ 11.2: выделение видно в любом освещении).
// Без освещения: светлое кольцо цвета стороны с тёмной обводкой — читается и на светлой,
// и на тёмной земле. COLOR экземпляра — цвет (раненый краснеет), альфа — яркость.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform float width = 0.11;      // толщина кольца в долях радиуса
uniform float outline = 0.06;    // тёмная обводка

varying vec4 v_col;

void vertex() {
	v_col = COLOR;
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float inner = 1.0 - width * 2.0;
	float ring = smoothstep(inner - 0.03, inner, r) * (1.0 - smoothstep(1.0 - 0.04, 1.0, r));
	float dark = smoothstep(inner - outline - 0.03, inner - outline, r) * (1.0 - smoothstep(1.0 - 0.01, 1.0 + 0.0, r));
	vec3 c = mix(vec3(0.03, 0.03, 0.04), v_col.rgb, ring);
	ALBEDO = c;
	ALPHA = max(ring, dark * 0.55) * v_col.a;
}
