// Временная рисованная земля для проверки лагеря (настоящую землю делает мир).
// Пятна мазков в мировых координатах: олива, охра, серо-зелёный; у лагеря — пыль.
shader_type spatial;
render_mode cull_back;

#include "res://shaders/include/painterly.gdshaderinc"

uniform vec4 c_grass_dark : source_color = vec4(0.14, 0.19, 0.11, 1.0);
uniform vec4 c_grass : source_color = vec4(0.22, 0.28, 0.14, 1.0);
uniform vec4 c_ochre : source_color = vec4(0.38, 0.34, 0.2, 1.0);
uniform vec4 c_dust : source_color = vec4(0.4, 0.35, 0.26, 1.0);
uniform vec3 camp_center = vec3(-60.0, 0.0, 20.0);
uniform float camp_radius = 58.0;

float stroke(vec2 p) {
	return texture(ordo_brush, p).r;
}

void vertex() {
	PAINT_VERTEX;
}

void fragment() {
	vec2 p = v_world_pos.xz;
	float big = stroke(p * 0.004 + vec2(0.13, 0.71));
	float mid = stroke(p * 0.021 + vec2(0.4, 0.2));
	float fine = stroke(p * 0.11);
	vec3 col = mix(c_grass_dark.rgb, c_grass.rgb, smoothstep(0.3, 0.7, big));
	col = mix(col, c_ochre.rgb, smoothstep(0.55, 0.85, mid) * 0.6);
	float d = length(p - camp_center.xz) / camp_radius + (mid - 0.5) * 0.35 + (big - 0.5) * 0.3;
	float dust = 1.0 - smoothstep(0.75, 1.05, d);
	col = mix(col, c_dust.rgb * (0.9 + 0.2 * mid), dust * 0.75);
	col *= 0.86 + 0.24 * fine;
	// вблизи — крупные мазки кисти по траве (не гладкая заливка)
	float near_s = stroke(p * 0.32 + vec2(big * 0.2, 0.0));
	col *= 0.9 + 0.2 * near_s;
	ALBEDO = col;
	ROUGHNESS = 1.0;
	paint_brush_v = paint_brush(v_world_pos, v_world_nrm);
}

void light() {
	// земля при низком солнце: свет по косинусу (полоса painterly на плоской земле давала бы
	// «полный свет» и заливала кадр); мазок слегка ломает тон
	float ndl = dot(NORMAL, LIGHT);
	float b = (paint_brush_v - 0.5) * 0.3;
	float lit = clamp(ndl * 1.7 + b * 0.35, 0.0, 1.0) * ATTENUATION;
	DIFFUSE_LIGHT += LIGHT_COLOR * ordo_key_tint.rgb * lit / PI;
	if (LIGHT_IS_DIRECTIONAL) {
		float hidden = (1.0 - ATTENUATION) * smoothstep(0.0, 0.3, ndl);
		DIFFUSE_LIGHT += ordo_shadow_tint.rgb * hidden * length(LIGHT_COLOR) * 0.1 / PI;
	}
}
