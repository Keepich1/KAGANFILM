// Живописная поверхность с вырезом по альфе (листва, бахрома, вымпелы), двусторонняя.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

#include "res://shaders/include/painterly.gdshaderinc"

uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform bool use_vertex_color = false;
uniform float alpha_cut = 0.5;
uniform float rim_strength = 1.0;

void vertex() {
	PAINT_VERTEX;
}

void fragment() {
	vec4 a = texture(albedo_tex, UV) * albedo_tint;
	if (use_vertex_color) {
		a.rgb *= COLOR.rgb;
	}
	ALBEDO = a.rgb;
	ALPHA = a.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ROUGHNESS = 0.95;
	// у двусторонних полотен обратная сторона смотрит к камере
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	paint_brush_v = paint_brush(v_world_pos, v_world_nrm);
}

void light() {
	PAINT_LIGHT(rim_strength);
}
