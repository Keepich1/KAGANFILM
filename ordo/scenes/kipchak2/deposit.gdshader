// Месторождение (камень, золото): рисованные плитки трипланарно в осях модели — без растяжек
// на скалах любой формы. Общий живописный свет (painterly.gdshaderinc), как у зданий.
//
// Маски из glb (tools/gen_kipchak2_deposit.py):
//   UV2.x — стёсанная грань (камень) / кварц (золото) → tex_cut
//   UV2.y — плотность жил → tex_vein (RGBA: альфа — где жила), у золота светится тёплым
//   COLOR.rgb — нарисованный свет, COLOR.a — отвал/щебень → tex_spoil
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

#include "res://shaders/include/painterly.gdshaderinc"

global uniform vec3 ordo_sun_dir;

uniform sampler2D tex_face : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_cut : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_vein : source_color, hint_default_transparent, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_spoil : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float tile = 0.45;            // повторов плитки на метр
uniform float rim_strength = 0.5;
uniform float vein_glow = 0.0;        // свечение жил (золото ~1.2; камень 0)
uniform float glint = 0.0;            // искры на жилах по отражению солнца
uniform float glint_far = 0.0;        // жилы светятся сильнее издали — золото узнаётся с RTS-камеры
uniform vec2 glint_range = vec2(25.0, 90.0);

varying vec3 v_mpos;
varying vec3 v_mnrm;
varying vec2 v_mask;
varying float v_spoil;
varying float v_dist;

void vertex() {
	v_mpos = VERTEX;
	v_mnrm = NORMAL;
	v_mask = UV2;
	v_spoil = COLOR.a;
	v_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	PAINT_VERTEX;
}

vec4 tri(sampler2D t, vec3 p, vec3 w) {
	return texture(t, p.zy) * w.x + texture(t, p.xz) * w.y + texture(t, p.xy) * w.z;
}

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void fragment() {
	vec3 n = normalize(v_mnrm);
	vec3 w = pow(abs(n), vec3(4.0));
	w /= max(dot(w, vec3(1.0)), 1e-4);
	vec3 p = v_mpos * tile;
	vec3 col = tri(tex_face, p, w).rgb;
	vec3 cut = tri(tex_cut, p * 1.25 + vec3(0.37), w).rgb;
	col = mix(col, cut, clamp(v_mask.x, 0.0, 1.0));
	vec4 vein = tri(tex_vein, p * 0.85 + vec3(0.13, 0.0, 0.29), w);
	float vm = clamp(v_mask.y, 0.0, 1.0) * vein.a;
	col = mix(col, vein.rgb, vm);
	vec3 sp = tri(tex_spoil, p * 1.1, w).rgb;
	float spoil = clamp(v_spoil, 0.0, 1.0);
	col = mix(col, sp, spoil);
	col *= COLOR.rgb * tint.rgb;
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.5, vm);
	// жилы: тёплое свечение (сильнее издали) и искры, где отражение смотрит на солнце
	vec3 sun_v = normalize((VIEW_MATRIX * vec4(ordo_sun_dir, 0.0)).xyz);
	float spec = pow(max(dot(reflect(-VIEW, NORMAL), sun_v), 0.0), 6.0);
	float fleck = step(0.82, hash3(floor(v_mpos * 22.0)));
	float far_k = mix(1.0, 1.0 + glint_far, smoothstep(glint_range.x, glint_range.y, v_dist));
	float g = vein_glow * far_k + glint * (0.25 + spec * 2.0) * fleck;
	// блёстки в отвалах золота тоже ловят солнце
	float sp_lum = dot(sp, vec3(0.3, 0.55, 0.15));
	float sp_gold = spoil * smoothstep(0.55, 0.75, sp_lum) * step(0.5, glint);
	EMISSION = vein.rgb * vm * g + sp * sp_gold * spec * 0.8;
	paint_brush_v = paint_brush(v_world_pos, v_world_nrm);
}

void light() {
	PAINT_LIGHT(rim_strength);
}
