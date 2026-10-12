// Рисованный клуб дыма или пыли (ТЗ 11.1: «пороховой дым как рисованные 2D-эффекты, как в «Аркейне»).
// Спрайт-билборд из атласа tools/gen_fx.py: нормаль клуба (RG), мазки (B), плотность (A).
// Свет от солнца сцены ступенями: тёплая сторона к солнцу, средний тон, холодная бирюзовая тень;
// против солнца тонкие края светятся. Край — чёткий срез плотности по порогу; с возрастом
// порог растёт, и клуб тает с края и в тонких местах (а не просто бледнеет).
// Данные частицы — см. fx_drift.gdshader. Солнце (sun_dir, sun_color) ставит BattleFx.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D atlas : filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec2 grid = vec2(4.0, 4.0);
uniform vec3 sun_dir = vec3(-0.9, 0.17, 0.38);   // к солнцу, мир
uniform vec3 sun_color = vec3(1.0, 0.74, 0.52);
uniform float sun_energy = 1.0;
uniform vec4 col_lit : source_color = vec4(1.0, 0.86, 0.68, 1.0);
uniform vec4 col_mid : source_color = vec4(0.66, 0.6, 0.6, 1.0);
uniform vec4 col_shade : source_color = vec4(0.27, 0.36, 0.44, 1.0);
uniform vec4 col_glow : source_color = vec4(1.0, 0.62, 0.32, 1.0);
uniform float lit_edge = 0.42;       // где начинается освещённый тон (по N·L)
uniform float shade_edge = -0.02;    // где кончается тень
uniform float band = 0.035;          // ширина нарисованной границы тонов
uniform float brush = 0.5;           // насколько мазки ломают границы
uniform float glow_strength = 1.0;
uniform float erode_start = 0.1;     // порог плотности при рождении
uniform float erode_end = 0.78;      // и к концу жизни
uniform float erode_curve = 1.3;
uniform float edge = 0.025;          // чёткость края
uniform float opacity = 0.95;
uniform float stretch = 1.0;         // ширина/высота (пыль — шире)
uniform float soft_dist = 0.8;       // мягкое касание земли, м
uniform float fade_in = 0.02;
uniform float age_thin = 0.45;       // насколько старый клуб прозрачнее

varying float v_age;
varying float v_rot;
varying vec4 v_col;
varying float v_cell;

void vertex() {
	float s = length(MODEL_MATRIX[0].xyz);
	v_rot = INSTANCE_CUSTOM.x;
	v_age = clamp(INSTANCE_CUSTOM.y, 0.0, 1.0);
	v_col = COLOR;
	v_cell = float(INSTANCE_ID % int(grid.x * grid.y));
	float c = cos(v_rot), sn = sin(v_rot);
	vec2 q = VERTEX.xy * vec2(stretch, 1.0);
	q = vec2(q.x * c - q.y * sn, q.x * sn + q.y * c);
	vec3 right = normalize(INV_VIEW_MATRIX[0].xyz);
	vec3 up = normalize(INV_VIEW_MATRIX[1].xyz);
	vec3 back = normalize(INV_VIEW_MATRIX[2].xyz);
	mat4 world = mat4(vec4(right * s, 0.0), vec4(up * s, 0.0), vec4(back * s, 0.0), MODEL_MATRIX[3]);
	VERTEX = vec3(q, 0.0);
	MODELVIEW_MATRIX = VIEW_MATRIX * world;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	float cols = grid.x;
	float cell = v_cell;
	vec2 cxy = vec2(mod(cell, cols), floor(cell / cols));
	vec2 uv = (cxy + clamp(UV, vec2(0.004), vec2(0.996))) / grid;
	vec4 t = texture(atlas, uv);
	// нормаль клуба: из спрайта в вид, повёрнутая вместе со спрайтом, затем в мир
	vec2 nxy = t.rg * 2.0 - 1.0;
	float c = cos(v_rot), sn = sin(v_rot);
	nxy = vec2(nxy.x * c - nxy.y * sn, nxy.x * sn + nxy.y * c);
	vec3 nv = normalize(vec3(nxy * 1.25, sqrt(max(1.0 - dot(nxy, nxy), 0.0))));
	vec3 nw = normalize((INV_VIEW_MATRIX * vec4(nv, 0.0)).xyz);
	vec3 L = normalize(sun_dir);
	float b = (t.b - 0.5) * brush;
	float ndl = dot(nw, L) + b;
	// ступени тона с нарисованной границей
	// «найденные и потерянные» границы: где мазок светлее — граница тона мягче
	float bw = band * mix(0.6, 3.0, t.b);
	float s1 = smoothstep(shade_edge - bw, shade_edge + bw, ndl);
	float s2 = smoothstep(lit_edge - bw, lit_edge + bw, ndl);
	vec3 col = mix(col_shade.rgb, col_mid.rgb * mix(vec3(1.0), sun_color, 0.35), s1);
	col = mix(col, col_lit.rgb * sun_color * sun_energy, s2);
	// низ клуба темнее (небо светит сверху), верх светлее
	col *= mix(0.72, 1.06, smoothstep(-0.6, 0.6, nw.y));
	// порог плотности: клуб тает с края
	float thr = mix(erode_start, erode_end, pow(v_age, erode_curve));
	// край: где-то чёткий, где-то растушёван (по мазку и возрасту)
	float ew = edge * mix(0.7, 3.5, t.b * t.b) * (1.0 + v_age * 1.5);
	float cov = smoothstep(thr - ew, thr + ew, t.a);
	// против солнца дым светится (рассеяние вперёд): весь клуб чуть, тонкие края — сильно
	vec3 cam_fwd = -normalize(INV_VIEW_MATRIX[2].xyz);
	float back = pow(clamp(dot(cam_fwd, L) * 1.15, 0.0, 1.0), 2.0);
	float thin = 1.0 - smoothstep(thr, thr + 0.32, t.a);
	float scatter = back * clamp(0.1 + 0.9 * thin, 0.0, 1.0) * glow_strength;
	col = mix(col * mix(1.0, 0.8, back), col_glow.rgb * sun_color * sun_energy * 1.25, clamp(scatter, 0.0, 0.95));
	col *= v_col.rgb;
	// мягкое касание земли и предметов
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 vp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float scene_z = -vp.z / vp.w;
	float soft = clamp((scene_z + VERTEX.z) / soft_dist, 0.0, 1.0);
	ALBEDO = col;
	// старый дым редеет
	float thin_age = 1.0 - age_thin * v_age;
	ALPHA = cov * opacity * v_col.a * soft * thin_age * smoothstep(0.0, fade_in, v_age);
}
