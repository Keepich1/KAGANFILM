// Временная земля для тестовой сцены боя (пока нет земли мира): приглушённые охры, олива,
// серо-зелёный (ТЗ 11.1), крупные живописные пятна, вытоптанный луг на поле боя.
// Земля темнее и спокойнее юнитов (ТЗ 11.2).
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

#include "res://shaders/include/painterly.gdshaderinc"

uniform vec4 c_ochre : source_color = vec4(0.541, 0.455, 0.282, 1.0);
uniform vec4 c_olive : source_color = vec4(0.392, 0.384, 0.22, 1.0);
uniform vec4 c_greygreen : source_color = vec4(0.365, 0.416, 0.333, 1.0);
uniform vec4 c_dust : source_color = vec4(0.702, 0.604, 0.431, 1.0);
uniform vec2 field_center = vec2(90.0, 2.0);
uniform float darkness = 0.55;

void vertex() {
	PAINT_VERTEX;
}

float nz(vec2 p) {
	return texture(ordo_brush, p).r;
}

void fragment() {
	vec2 p = v_world_pos.xz;
	float a = nz(p * 0.0035);
	float b = nz(p * 0.011 + vec2(0.37, 0.11));
	float c = nz(p * 0.045 + vec2(0.71, 0.29));
	float d = nz(p * 0.21 + vec2(0.13, 0.57));
	// крупные пятна — плоские заливки с мягким краем, как подмалёвок
	vec3 col = mix(c_olive.rgb, c_ochre.rgb, smoothstep(0.45, 0.7, a) * 0.7);
	col = mix(col, c_greygreen.rgb, smoothstep(0.35, 0.65, b) * 0.75);
	col = mix(col, c_dust.rgb, smoothstep(0.62, 0.85, c) * 0.3);
	// вытоптанный луг на поле боя: светлее и пыльнее
	float field = 1.0 - smoothstep(25.0, 90.0, length((p - field_center) * vec2(0.8, 1.3)));
	col = mix(col, c_dust.rgb * 0.92, field * (0.18 + 0.2 * c));
	// мелкий мазок травы
	col *= 0.9 + 0.2 * d;
	ALBEDO = col * darkness;
	ROUGHNESS = 1.0;
	paint_brush_v = paint_brush(v_world_pos, v_world_nrm);
}

void light() {
	PAINT_LIGHT(0.0);
}
