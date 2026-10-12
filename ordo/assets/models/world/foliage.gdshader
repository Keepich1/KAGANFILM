// Деревья мира (тополь, ива, арча, карагач): кора и карточки листвы из общего атласа
// assets/textures/world/trees.png. Нормали кроны смотрят от её центра — крона
// затеняется одним мягким объёмом, силуэт рваный. Крона качается на ветру
// (ordo_wind, сила — альфа цвета вершины), листва просвечивает тёплым против солнца,
// по краю силуэта — контровой свет. Свет — общий живописный (painterly.gdshaderinc).
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

#include "res://shaders/include/painterly.gdshaderinc"

global uniform vec4 ordo_wind;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 bark_tint : source_color = vec4(1.0);
uniform float alpha_cut = 0.45;
uniform float sway = 0.35;               // качание кроны, м
uniform float flutter = 0.05;            // дрожь листвы, м
uniform float translucency = 0.55;
uniform vec4 trans_color : source_color = vec4(1.0, 0.78, 0.42, 1.0);
uniform float rim_strength = 0.45;
uniform float variation = 0.14;          // разброс тона между деревьями

varying vec3 v_var;

void vertex() {
	vec3 inst = MODEL_MATRIX[3].xyz;
	float ph = dot(inst.xz, vec2(0.131, 0.173));
	vec2 wdir = normalize(ordo_wind.xy + vec2(1e-4));
	float w = COLOR.a;
	float t = TIME * (0.7 + ordo_wind.w);
	float gust = sin(t * 0.9 + ph) * 0.55 + sin(t * 2.1 + ph * 1.7) * 0.25 + 0.55;
	vec3 off = vec3(wdir.x, 0.0, wdir.y) * gust * sway * ordo_wind.z * w;
	off += vec3(sin(t * 4.3 + VERTEX.y * 1.7 + ph), 0.4 * sin(t * 3.1 + VERTEX.x * 2.3),
		cos(t * 3.9 + VERTEX.z * 1.9 + ph)) * flutter * w;
	// смещение задано в мире — переводим в пространство модели (поворот + равномерный масштаб)
	mat3 m3 = mat3(MODEL_MATRIX);
	float s2 = dot(m3[0], m3[0]);
	VERTEX += transpose(m3) * off / s2;
	PAINT_VERTEX;
	// тон дерева: свой у каждого экземпляра (INSTANCE_CUSTOM.x — оттенок, .y — светлота)
	vec4 ic = INSTANCE_CUSTOM;
	v_var = vec3(1.0 + (ic.x - 0.5) * variation, 1.0 + (ic.x - 0.5) * variation * 0.4, 1.0 - (ic.x - 0.5) * variation)
		* (1.0 + (ic.y - 0.5) * variation * 1.5);
}

void fragment() {
	vec4 a = texture(albedo_tex, UV);
	bool bark = (UV.y > 0.5) && ((UV.x > 0.5 && UV.x < 0.75) || (UV.x >= 0.75 && UV.y > 0.75));
	vec3 col = a.rgb * COLOR.rgb * (bark ? bark_tint.rgb : tint.rgb * v_var);
	ALBEDO = col;
	ALPHA = bark ? 1.0 : a.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
	// обе стороны карточки — как поверхность кроны (нормаль от центра кроны)
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	paint_brush_v = paint_brush(v_world_pos, v_world_nrm);
}

void light() {
	DIFFUSE_LIGHT += paint_diffuse(NORMAL, LIGHT, LIGHT_COLOR, ATTENUATION, paint_brush_v, LIGHT_IS_DIRECTIONAL);
	float back = clamp(dot(LIGHT, -VIEW), 0.0, 1.0);
	// просвет сильнее по краю кроны, где листва тоньше
	float edge = 1.0 - abs(dot(NORMAL, VIEW));
	DIFFUSE_LIGHT += LIGHT_COLOR * trans_color.rgb * pow(back, 3.0) * translucency * (0.25 + 0.75 * edge) * ATTENUATION / PI;
	SPECULAR_LIGHT += paint_rim(NORMAL, LIGHT, VIEW, LIGHT_COLOR, ATTENUATION, rim_strength);
}
