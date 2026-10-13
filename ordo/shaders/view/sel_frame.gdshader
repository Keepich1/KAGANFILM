// Рамка выделенной постройки (VIEW, SelectionView): по следу на земле — уголки цвета стороны с тёмной
// обводкой и тонкая пунктирная кромка. Без освещения: видна в любом свете (ТЗ 11.2).
// UV — 0..1 по следу; size — размер следа в метрах (толщина линий в метрах, не в долях).
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

instance uniform vec4 frame_col : source_color = vec4(0.2, 0.9, 0.8, 1.0);
instance uniform vec2 size = vec2(10.0, 10.0);
uniform float line_m = 0.32;
uniform float corner_frac = 0.26;

void fragment() {
	vec2 p = UV * size;
	vec2 d = min(p, size - p);                         // до ближайшей кромки, м
	float edge = min(d.x, d.y);
	vec2 cf = size * corner_frac;
	bool corner = (p.x < cf.x || p.x > size.x - cf.x) && (p.y < cf.y || p.y > size.y - cf.y);
	float line = 1.0 - smoothstep(line_m * 0.8, line_m, edge);
	float outline = 1.0 - smoothstep(line_m * 1.5, line_m * 1.8, edge);
	float dash = step(0.5, fract((p.x + p.y) * 0.5));
	float a = corner ? max(line, outline * 0.55) : line * dash * 0.55;
	vec3 c = mix(vec3(0.03, 0.03, 0.04), frame_col.rgb, corner ? line : 1.0);
	ALBEDO = c;
	ALPHA = a * frame_col.a;
}
