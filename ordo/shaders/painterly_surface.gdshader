// Живописная поверхность для зданий и предметов (glb с атласом стороны).
// Цвет вершины (COLOR_0 из glb) — нарисованная заранее тень/подсветка, множитель.
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

#include "res://shaders/include/painterly.gdshaderinc"

uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform bool use_vertex_color = false;
uniform float rim_strength = 1.0;
uniform float roughness = 0.9;
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;

void vertex() {
	PAINT_VERTEX;
}

void fragment() {
	vec4 a = texture(albedo_tex, UV) * albedo_tint;
	if (use_vertex_color) {
		a.rgb *= COLOR.rgb;
	}
	ALBEDO = a.rgb;
	ROUGHNESS = roughness;
	EMISSION = emission.rgb * emission_energy;
	paint_brush_v = paint_brush(v_world_pos, v_world_nrm);
}

void light() {
	PAINT_LIGHT(rim_strength);
}
