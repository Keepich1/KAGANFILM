// Земля среза (ТЗ 11.1–11.2): рисованные слои почвы, смешанные «мазком», а не размытой
// границей; камень на крутых склонах — трипланарно; крупные пятна цвета как от широкой
// кисти; вытоптанная земля у лагеря и троп; мокрый берег; снег на дальних вершинах.
// Земля темнее и спокойнее юнитов. Свет — общий живописный (painterly.gdshaderinc).
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

#include "res://shaders/include/painterly.gdshaderinc"

// Карты 1024 × 1024 м (центр карты в 0,0): R сухая охра, G вытоптанная земля, B камень, A песок
uniform sampler2D splat_map : hint_default_black, filter_linear_mipmap, repeat_disable;
// R густота травы, G высота травы, B доля ковыля, A сырость у воды
uniform sampler2D grass_map : hint_default_black, filter_linear_mipmap, repeat_disable;
// Рисованные плитки (альфа — «высота» мазка для смешивания)
uniform sampler2D tex_grass : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_dry : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_earth : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_rock : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_sand : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
// кисть с мип-картами для крупных пятен (как ordo_brush, но без ряби вдали)
uniform sampler2D brush_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;

uniform float map_half = 512.0;
uniform float tile_size = 7.0;            // м на плитку текстуры
uniform float water_level = -4.0;
uniform float snow_line = 270.0;

// Тон слоёв (множители к рисованным текстурам) — тут настраивается палитра земли
uniform vec4 tint_grass : source_color = vec4(1.0, 1.16, 0.88, 1.0);
uniform vec4 tint_dry : source_color = vec4(0.95, 0.9, 0.82, 1.0);
uniform vec4 tint_earth : source_color = vec4(0.82, 0.82, 0.8, 1.0);
uniform vec4 tint_rock : source_color = vec4(0.92, 0.92, 0.95, 1.0);
uniform vec4 tint_sand : source_color = vec4(0.95, 0.92, 0.86, 1.0);
uniform vec4 snow_color : source_color = vec4(0.86, 0.85, 0.9, 1.0);
uniform vec4 wet_color : source_color = vec4(0.30, 0.31, 0.27, 1.0);
// Крупные пятна «широкой кистью»: олива ↔ серо-зелёный ↔ охра
uniform vec4 macro_cool : source_color = vec4(0.80, 0.92, 0.92, 1.0);
uniform vec4 macro_warm : source_color = vec4(1.08, 0.98, 0.80, 1.0);
uniform float macro_amount = 0.55;
uniform float macro_scale = 140.0;        // м
// Общая яркость земли (земля темнее юнитов, ТЗ 11.2)
uniform float ground_value = 0.95;
// Вдали детали гаснут, цвет спокойнее
uniform float far_calm_start = 120.0;
uniform float far_calm_end = 700.0;
uniform float far_calm = 0.55;
// Скользящий свет низкого солнца: ровная земля темнее склонов, обращённых к солнцу
uniform float grazing_dim = 0.62;
uniform float backlit_dim = 0.7;
uniform float rim_strength = 0.25;
// Насыщенность земли (приглушённая палитра ТЗ 11.1)
uniform float ground_saturation = 0.9;
// Нарисованная холодная тень: добавка там, куда солнце не попадает (rgb, a — сила)
uniform vec4 shadow_paint : source_color = vec4(0.26, 0.33, 0.47, 0.045);
// Крупный мазок, ломающий границу света на земле (м⁻¹)
uniform float big_brush_scale = 0.045;
// Насколько мазок ломает границу света на земле (на скользящем свете иначе пятна)
uniform float brush_light = 0.45;

varying float v_cam_dist;

void vertex() {
	PAINT_VERTEX;
	v_cam_dist = length(v_world_pos - CAMERA_POSITION_WORLD);
}

// Две выборки плитки разного масштаба и поворота — без заметного повтора
vec4 tile2(sampler2D t, vec2 p, float k) {
	vec4 a = texture(t, p / tile_size);
	vec2 q = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p / (tile_size * 3.3) + vec2(0.37, 0.71);
	vec4 b = texture(t, q);
	return mix(a, b, k);
}

vec4 triplanar(sampler2D t, vec3 p, vec3 n, float scale) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec4 x = texture(t, p.zy / scale);
	vec4 y = texture(t, p.xz / scale);
	vec4 z = texture(t, p.xy / scale);
	return x * w.x + y * w.y + z * w.z;
}

// Слой поверх: граница идёт по «высоте» мазков и по карте кисти, а не размыто
void layer(inout vec3 col, inout float hcur, vec4 t, vec3 tint, float w, float brush, float sharp) {
	float f = w * 1.25 - 0.12 + (t.a - hcur) * 0.5 + (brush - 0.5) * 0.6;
	f = smoothstep(0.5 - sharp, 0.5 + sharp, f);
	col = mix(col, t.rgb * tint, f);
	hcur = mix(hcur, t.a, f);
}

void fragment() {
	vec3 wp = v_world_pos;
	vec3 wn = normalize(v_world_nrm);
	vec2 muv = (wp.xz + vec2(map_half)) / (2.0 * map_half);
	float inside = step(abs(wp.x), map_half) * step(abs(wp.z), map_half);

	vec4 sp = texture(splat_map, muv) * inside;
	vec4 gm = texture(grass_map, muv) * inside;

	// мазки большой кисти в мире
	float b1 = texture(brush_tex, wp.xz * 0.021 + vec2(0.13, 0.57)).r;
	float b2 = texture(brush_tex, wp.xz * 0.083 + vec2(0.71, 0.29)).r;
	float b3 = texture(brush_tex, wp.xz * 0.31).r;
	float brush = mix(b2, b3, 0.4);

	float slope = 1.0 - wn.y;
	// за краем карты: камень по крутизне, охра и трава пятнами
	float rock_proc = smoothstep(0.16, 0.32, slope + (b1 - 0.5) * 0.12);
	float dry_proc = smoothstep(0.35, 0.75, b1);
	sp.r = mix(dry_proc, sp.r, inside);
	sp.b = max(sp.b, rock_proc * (1.0 - inside * 0.6));

	float detail_mix = 0.35 + 0.25 * smoothstep(40.0, 300.0, v_cam_dist);
	vec4 tg = tile2(tex_grass, wp.xz, detail_mix);
	vec4 td = tile2(tex_dry, wp.xz + vec2(31.0, 17.0), detail_mix);
	vec4 te = tile2(tex_earth, wp.xz + vec2(7.0, 53.0), detail_mix);
	vec4 ts = tile2(tex_sand, wp.xz + vec2(91.0, 3.0), detail_mix);
	// камень: мелкие грани + крупные плоскости (видны с дальних планов как широкие мазки)
	vec4 tr = triplanar(tex_rock, wp, wn, tile_size * 1.6);
	vec4 tr_big = triplanar(tex_rock, wp + vec3(13.0, 0.0, 7.0), wn, tile_size * 11.0);
	tr = mix(tr, tr_big, 0.2 + 0.25 * smoothstep(60.0, 500.0, v_cam_dist));
	tr.rgb *= mix(0.85, 1.1, tr_big.a);

	vec3 col = tg.rgb * tint_grass.rgb;
	float hcur = tg.a;
	layer(col, hcur, td, tint_dry.rgb, sp.r, brush, 0.22);
	layer(col, hcur, ts, tint_sand.rgb, sp.a, brush, 0.18);
	layer(col, hcur, te, tint_earth.rgb, sp.g, brush, 0.16);
	layer(col, hcur, tr, tint_rock.rgb, sp.b, brush, 0.12);

	// мокрый берег и дно: темнее, холоднее
	float under = smoothstep(water_level + 0.05, water_level - 0.6, wp.y);
	float wet = max(gm.a * 0.85, under);
	col = mix(col, col * wet_color.rgb * 2.2, wet * 0.75);

	// снег на высоких пологих местах (дальнее кольцо)
	float snow = smoothstep(snow_line - 25.0, snow_line + 20.0, wp.y + (b1 - 0.5) * 60.0)
		* (1.0 - smoothstep(0.25, 0.45, slope));
	col = mix(col, snow_color.rgb, snow);

	// крупные пятна цвета: холодный серо-зелёный ↔ тёплая охра (как широкой кистью)
	float m1 = texture(brush_tex, wp.xz / macro_scale + vec2(0.5, 0.2)).r;
	float m2 = texture(brush_tex, wp.zx / (macro_scale * 2.7) + vec2(0.1, 0.8)).r;
	float macro = mix(m1, m2, 0.5);
	vec3 tint = mix(macro_cool.rgb, macro_warm.rgb, smoothstep(0.3, 0.7, macro));
	col *= mix(vec3(1.0), tint, macro_amount * (1.0 - snow));
	// пятна света и тени, «написанные» по земле широкой кистью
	col *= mix(0.84, 1.14, smoothstep(0.25, 0.75, m2));

	// вдали спокойнее: детали гаснут к среднему тону
	float calm = smoothstep(far_calm_start, far_calm_end, v_cam_dist) * far_calm;
	vec3 avg = vec3(dot(col, vec3(0.3, 0.55, 0.15)));
	col = mix(col, mix(avg, col, 0.75), calm);

	col = mix(vec3(dot(col, vec3(0.3, 0.55, 0.15))), col, ground_saturation);
	ALBEDO = col * ground_value;
	ROUGHNESS = 1.0;
	SPECULAR = 0.15;
	// граница света ломается крупным мазком (земля видна издалека)
	float pb = mix(paint_brush(v_world_pos, v_world_nrm), texture(brush_tex, wp.xz * big_brush_scale).r, 0.6);
	paint_brush_v = 0.5 + (pb - 0.5) * brush_light;
}

void light() {
	// низкое солнце: ровная земля получает меньше, склоны к солнцу — больше
	float ndl = dot(NORMAL, LIGHT);
	float graze = mix(1.0 - grazing_dim, 1.0, smoothstep(0.0, 0.5, ndl));
	// против солнца земля в контражуре — темнее (видна теневая сторона травинок)
	float backlit = clamp(-dot(VIEW, LIGHT), 0.0, 1.0);
	graze *= mix(1.0, 1.0 - backlit_dim, backlit * backlit);
	DIFFUSE_LIGHT += paint_diffuse(NORMAL, LIGHT, LIGHT_COLOR * graze, ATTENUATION, paint_brush_v, LIGHT_IS_DIRECTIONAL);
	// контровой свет только на склонах-гребнях (на ровной земле под скользящим взглядом он лишний)
	float steep = smoothstep(0.88, 0.6, dot(NORMAL, (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz));
	SPECULAR_LIGHT += paint_rim(NORMAL, LIGHT, VIEW, LIGHT_COLOR, ATTENUATION, rim_strength * steep);
	if (LIGHT_IS_DIRECTIONAL) {
		// цветная тень: холодный сине-бирюзовый мазок, сохраняет рисунок почвы
		float sun_amt = smoothstep(-0.05, 0.25, ndl + (paint_brush_v - 0.5) * 0.2) * ATTENUATION;
		float luma = dot(ALBEDO, vec3(0.3, 0.55, 0.15));
		SPECULAR_LIGHT += shadow_paint.rgb * shadow_paint.a * (1.0 - sun_amt) * (0.35 + luma * 3.0) * length(LIGHT_COLOR);
	}
}
