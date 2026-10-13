// Стройка и руина из настоящей модели (VIEW), пока у модели нет своих _site/_ruin: тот же
// живописный материал, что у painterly_surface (атлас стороны, цвет вершин), плюс срез по высоте
// (стройка растёт снизу вверх) и копоть (руина, пожар). Параметры — на экземпляр модели.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

#include "res://shaders/include/painterly.gdshaderinc"

uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform bool use_vertex_color = false;
uniform bool alpha_cut = false;
uniform float rim_strength = 1.0;
uniform float roughness = 0.9;

instance uniform float clip_h = 100000.0;   // высота над основанием модели, выше — пусто
instance uniform float base_y = 0.0;        // мировая высота основания
instance uniform float scorch = 0.0;

void vertex() {
	PAINT_VERTEX;
}

void fragment() {
	float h = v_world_pos.y - base_y;
	vec4 a = texture(albedo_tex, UV) * albedo_tint;
	if (h > clip_h || (alpha_cut && a.a < 0.5)) {
		discard;
	}
	if (use_vertex_color) {
		a.rgb *= COLOR.rgb;
	}
	float n = paint_vnoise(v_world_pos.xz * 0.9 + v_world_pos.y * 0.6);
	a.rgb = mix(a.rgb, a.rgb * vec3(0.3, 0.27, 0.25), clamp(scorch * (0.6 + 0.6 * n), 0.0, 1.0));
	if (clip_h < 1000.0) {
		a.rgb *= 1.0 + 0.22 * smoothstep(clip_h - 0.3, clip_h, h);
	}
	ALBEDO = a.rgb;
	ROUGHNESS = roughness;
	paint_brush_v = paint_brush(v_world_pos, v_world_nrm);
}

void light() {
	PAINT_LIGHT(rim_strength);
}
