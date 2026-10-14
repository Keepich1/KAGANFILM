// Деревья мира (тополь, ива, арча, карагач): кора и рисованные грозди листвы из общего атласа
// assets/textures/world/trees.png (делает tools/gen_world_models.py, там же договор вершин).
//
//  * Грозди (UV2: тип 1 и 3) разворачиваются к камере в плоскости экрана: все карточки параллельны
//    друг другу и не режут друг друга, ребром не видны никогда — крона пушистая, без «кубиков».
//    Каскады прядей ивы (тип 2) разворачиваются к камере только вокруг вертикали — висят отвесно;
//    каскад нарисован дугой в одну сторону, на левой для камеры стороне кроны он зеркалится —
//    пряди всегда расходятся от ствола наружу («колокол»).
//  * Свет кроны: нормаль от центра кроны и грозди + «купол» внутри каждой карточки — каждая
//    гроздь лепится солнцем отдельно (светлая шапка на солнце, холодная тень с другой стороны),
//    крона остаётся одним объёмом. У «масс» (тип 3: карагач, купол ивы) купол слабый — лопасть
//    кроны светится одной крупной массой. Свет — общий живописный (painterly.gdshaderinc),
//    граница света на листве мягче, чем на стенах, на прядях ивы — ещё мягче.
//  * Против низкого солнца тонкий край грозди (альфа атласа — поле расстояния до края)
//    и край кроны просвечивают тёплым; по силуэту — контровой свет.
//  * Ветер: крона и ствол гнутся вместе (COLOR.a — сила изгиба), грозди дрожат, пряди ивы
//    качаются маятником (низ сильнее).
//  * В тени (проход теней — ортографический) карточка смотрит на солнце и отодвинута от него
//    на свой радиус: крона отбрасывает пушистую тень и затеняет свою глубину, но карточка
//    не затеняет сама себя полосой.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, skip_vertex_transform;

#include "res://shaders/include/painterly.gdshaderinc"

global uniform vec4 ordo_wind;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 bark_tint : source_color = vec4(1.0);
uniform float alpha_cut = 0.5;
uniform float sway = 0.35;               // качание кроны, м
uniform float flutter = 0.05;            // дрожь гроздей, м
uniform float strand_swing = 0.08;       // маятник прядей ивы, доля длины
uniform float translucency = 0.55;
uniform float edge_glow = 2.0;           // ореол освещённого края грозди против солнца
uniform vec4 trans_color : source_color = vec4(1.0, 0.78, 0.42, 1.0);
uniform float rim_strength = 0.45;
uniform float variation = 0.14;          // разброс тона между деревьями
uniform float card_scale = 1.0;          // множитель размера гроздей
uniform float dome = 0.5;                // насколько каждая гроздь лепится как свой шар
uniform float mass_dome = 0.35;          // доля купола у «масс» (тип 3)
uniform float shadow_push = 1.0;         // отодвиг карточки в проходе теней, доля её радиуса
uniform float self_shadow = 0.85;        // сила тени кроны на себе (1 — как есть)
uniform float strand_shadow = 0.55;      // то же у прядей ивы: между прядями просветы, тень дырявая
uniform float shadow_fill = 1.1;         // холодное заполнение неба в тени листвы: тени цветные, не чёрные

varying vec3 v_var;
varying vec3 v_card;                     // xy — место в карточке (−1..1), z — тип (0 кора, 1, 2)
varying float v_thin;                    // тонкий край грозди (из фрагмента в свет)

void vertex() {
	vec3 inst = MODEL_MATRIX[3].xyz;
	float ph = dot(inst.xz, vec2(0.131, 0.173));
	vec2 wdir = normalize(ordo_wind.xy + vec2(1e-4));
	float w = COLOR.a;
	float t = TIME * (0.7 + ordo_wind.w);
	float gust = sin(t * 0.9 + ph) * 0.55 + sin(t * 2.1 + ph * 1.7) * 0.25 + 0.55;
	float kind = floor(UV2.x / 20.0 + 0.5);
	vec2 o = vec2(UV2.x - 20.0 * kind, UV2.y);
	vec3 n = normalize(NORMAL);
	// центр карточки в плоскости покоя (для коры — сама вершина)
	vec3 c = VERTEX;
	if (kind > 0.5) {
		vec3 r = cross(vec3(0.0, 1.0, 0.0), n);
		r = dot(r, r) < 1e-6 ? vec3(1.0, 0.0, 0.0) : normalize(r);
		vec3 u = cross(n, r);
		c = VERTEX - r * o.x - u * o.y;
	}
	// ветер задан в мире — переводим в пространство модели (поворот + равномерный масштаб)
	mat3 m3 = mat3(MODEL_MATRIX);
	// срубленное дерево (WorldScatter.hide_tree) сжато в точку: масштаб 0 — без деления на ноль
	float s2 = max(dot(m3[0], m3[0]), 1e-10);
	float s = sqrt(s2);
	vec3 off = vec3(wdir.x, 0.0, wdir.y) * gust * sway * ordo_wind.z * w;
	float cph = dot(c, vec3(1.7, 2.3, 1.9)) + ph;
	off += vec3(sin(t * 4.3 + cph), 0.4 * sin(t * 3.1 + cph * 1.3), cos(t * 3.9 + cph)) * flutter * w
		* step(0.5, kind);
	c += transpose(m3) * off / s2;

	vec3 cv = (MODELVIEW_MATRIX * vec4(c, 1.0)).xyz;
	vec3 nv = mat3(MODELVIEW_MATRIX) * n;
	nv = dot(nv, nv) > 1e-12 ? normalize(nv) : vec3(0.0, 0.0, 1.0);
	if (kind < 0.5) {
		VERTEX = cv;
		v_card = vec3(0.0);
	} else {
		bool shadow_pass = PROJECTION_MATRIX[3][3] > 0.5;   // солнце рисует тень ортографически
		vec2 os = o * s * card_scale;
		vec3 p;
		bool strand = abs(kind - 2.0) < 0.5;
		if (!strand) {
			p = cv + vec3(os, 0.0);
			v_card = vec3(o / max(length(o), 1e-4), kind);  // углы — на единичной окружности
		} else {
			vec3 up_v = mat3(VIEW_MATRIX) * vec3(0.0, 1.0, 0.0);
			vec3 rt = cross(up_v, vec3(0.0, 0.0, 1.0));
			rt = dot(rt, rt) < 1e-4 ? vec3(1.0, 0.0, 0.0) : normalize(rt);
			// каскад нарисован дугой к +u: на левой (для камеры) стороне кроны зеркалим —
			// пряди всегда расходятся от ствола наружу
			os.x *= dot(nv, rt) < 0.0 ? -1.0 : 1.0;
			// маятник: низ пряди (oy < 0) отходит по ветру сильнее
			float k = -o.y * strand_swing * ordo_wind.z * (0.6 + 0.4 * sin(t * 1.7 + cph));
			vec3 swing = mat3(VIEW_MATRIX) * vec3(wdir.x, 0.0, wdir.y) * k * s;
			p = cv + rt * os.x + up_v * os.y + swing;
			v_card = vec3(sign(os.x), 0.0, 2.0);
		}
		if (shadow_pass) {
			// грозди — на свой радиус; прядь — на полширины (иначе длинный низ уходит далеко)
			p.z -= (strand ? abs(os.x) + 0.2 * s : length(os)) * shadow_push;
		}
		VERTEX = p;
	}
	NORMAL = nv;
	v_world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_nrm = normalize(mat3(INV_VIEW_MATRIX) * NORMAL);
	// тон дерева: свой у каждого экземпляра (INSTANCE_CUSTOM.x — оттенок, .y — светлота);
	// у одиночной модели (не MultiMesh) INSTANCE_CUSTOM пустой — средний тон
	vec4 ic = INSTANCE_CUSTOM;
	if (dot(ic, ic) < 1e-6) {
		ic = vec4(0.5);
	}
	v_var = vec3(1.0 + (ic.x - 0.5) * variation, 1.0 + (ic.x - 0.5) * variation * 0.4, 1.0 - (ic.x - 0.5) * variation)
		* (1.0 + (ic.y - 0.5) * variation * 1.5);
}

void fragment() {
	vec4 a = texture(albedo_tex, UV);
	bool bark = v_card.z < 0.5;
	ALBEDO = a.rgb * COLOR.rgb * (bark ? bark_tint.rgb : tint.rgb * v_var);
	ALPHA = bark ? 1.0 : a.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
	if (bark) {
		v_thin = 0.0;
	} else {
		// «купол» грозди: к камере в середине, вбок у края. У «масс» (тип 3: карагач, купол ивы)
		// купол слабый — карточки одной лопасти светятся вместе, лопасть читается одной массой,
		// а не россыпью шариков; у каскада ивы — слабый и только по ширине
		vec2 q = v_card.xy;
		float dm = dome;
		if (abs(v_card.z - 2.0) < 0.5) {
			q.y = 0.0;
			dm *= 0.3;
		} else if (v_card.z > 2.5) {
			dm *= mass_dome;
		}
		q *= 0.85;
		vec3 dn = vec3(q, sqrt(max(1.0 - dot(q, q), 0.0)));
		// карточка всегда развёрнута к камере, но у зеркальной (каскад на левой стороне кроны)
		// обход углов обратный: движок считает её изнанкой и переворачивает нормаль (cull_disabled) —
		// свет лёг бы не с той стороны. Нормаль карточки задана явно — возвращаем её
		vec3 n0 = FRONT_FACING ? NORMAL : -NORMAL;
		NORMAL = normalize(normalize(n0) * (1.0 - dm) + dn * dm);
		// тонкий край грозди: альфа (поле расстояния) чуть выше порога
		v_thin = 1.0 - smoothstep(alpha_cut, alpha_cut + 0.22, a.a);
	}
	paint_brush_v = paint_brush(v_world_pos, v_world_nrm);
}

void light() {
	if (v_card.z < 0.5) {
		PAINT_LIGHT(rim_strength * 0.7);
	} else {
		// тень кроны на себе чуть мягче: глубина темнее, но не «дыра»
		bool strand = abs(v_card.z - 2.0) < 0.5;
		float att = mix(1.0, PAINT_ATTEN, strand ? strand_shadow : self_shadow);
		// граница света на листве мягче, чем на стенах; на тонких прядях ивы — ещё мягче
		DIFFUSE_LIGHT += paint_diffuse_soft(NORMAL, LIGHT, LIGHT_COLOR, att, paint_brush_v, LIGHT_IS_DIRECTIONAL,
			strand ? 2.4 : 1.3);
		// просвет против солнца: тонкий край грозди и край кроны светятся тёплым цветом листа;
		// пряди ивы тонкие — просвечивают целиком
		float back = clamp(dot(LIGHT, -VIEW), 0.0, 1.0);
		float edge = 1.0 - abs(dot(NORMAL, VIEW));
		float thin = clamp(0.2 + 0.8 * v_thin + 0.5 * edge + (strand ? 0.45 : 0.0), 0.0, 1.0);
		vec3 glow = mix(trans_color.rgb, trans_color.rgb * ALBEDO * 4.0, 0.5);
		// ореол: рваный край грозди, на который падает солнце, горит ярче — у кроны против
		// заката светящаяся кромка, как у листвы на просвет (внутри кроны края в тени — не горят)
		float halo = v_thin * v_thin * PAINT_ATTEN * edge_glow;
		DIFFUSE_LIGHT += LIGHT_COLOR * glow * pow(back, 3.0) * translucency
			* (thin * mix(0.3, 1.0, PAINT_ATTEN) + halo) / PI;
		// холодное заполнение неба там, куда солнце не достаёт (теневая сторона и глубина кроны):
		// тени листвы цветные, сине-бирюзовые, а не чёрные (ТЗ 11.1)
		if (LIGHT_IS_DIRECTIONAL) {
			float sunlit = smoothstep(-0.25, 0.35, dot(NORMAL, LIGHT)) * att;
			DIFFUSE_LIGHT += ordo_shadow_tint.rgb * length(LIGHT_COLOR) * shadow_fill * (strand ? 1.3 : 1.0)
				* (1.0 - sunlit) * 0.25 / PI;
		}
		// контровой свет — по краю гроздей (тонкая кромка), а не плоской заливкой всей карточки
		SPECULAR_LIGHT += paint_rim(NORMAL, LIGHT, VIEW, LIGHT_COLOR, PAINT_ATTEN, rim_strength)
			* (0.35 + 0.65 * v_thin);
	}
}
