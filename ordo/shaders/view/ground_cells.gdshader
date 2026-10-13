// Клетки под призраком постройки (VIEW, GhostView): квадрат 4 м на каждую клетку следа, цвет —
// решение NavApi по клетке (COLOR экземпляра). Рамка ярче середины — сетка видна на траве.
// Без освещения, поверх земли (лёгкий подъём), не пишет глубину.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

varying vec4 v_col;

void vertex() {
	v_col = COLOR;
}

void fragment() {
	vec2 q = abs(UV - 0.5) * 2.0;
	float edge = smoothstep(0.78, 0.92, max(q.x, q.y));
	float fill = 0.22 + 0.55 * edge;
	ALBEDO = mix(v_col.rgb, vec3(1.0), edge * 0.25);
	ALPHA = fill * v_col.a * (1.0 - smoothstep(0.97, 1.0, max(q.x, q.y)));
}
