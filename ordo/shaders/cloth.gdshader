// Живописная ткань лагеря: вымпел туга, навес ордо, знамёна (ТЗ 11.3, 11.4).
//
// Колышется от общего ветра ordo_wind (xy — направление по x/z мира, z — сила,
// w — порывы). Размах растёт от крепления к свободному краю:
//   UV2.x — доля длины полотна от древка/крепления (0) к свободному краю (1),
//   UV2.y — доля поперёк полотна (0..1).
// Волнистый край вырезается по альфе атласа. Полотно двустороннее и на просвет
// светится (низкое солнце за знаменем — тёплое свечение, как у живописцев).
//
// follow_wind: полотно разворачивается по ветру вокруг локальной оси Y модели
// (для вымпела на древке; древко — в начале координат узла).
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

#include "res://shaders/include/painterly.gdshaderinc"

global uniform vec4 ordo_wind;

uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform bool use_vertex_color = false;
uniform float alpha_cut = 0.5;
uniform float rim_strength = 1.3;
uniform float flutter = 0.3;          // размах волны на свободном конце при силе ветра 1, м
uniform float wave_length = 1.6;      // длина волны вдоль полотна, м
uniform float wave_speed = 5.5;       // бег волны, рад/с
uniform float cloth_length = 3.0;     // длина полотна (UV2.x = 1), м
uniform float pin_power = 1.3;        // как быстро растёт размах от крепления
uniform vec3 along_axis = vec3(1.0, 0.0, 0.0); // направление роста UV2.x в модели
uniform bool follow_wind = false;
uniform float droop = 0.3;            // провис свободного конца в штиль, м
uniform float translucency = 0.6;     // свечение на просвет
uniform float back_shade = 0.85;      // изнанка чуть темнее

void vertex() {
	float s = UV2.x;
	float q = UV2.y;
	float t = TIME;
	float ph = dot(MODEL_MATRIX[3].xz, vec2(0.37, 0.61));
	float gust = 1.0 + ordo_wind.w * (0.45 * sin(t * 0.7 + ph) + 0.3 * sin(t * 1.9 + ph * 2.1));
	float w = clamp(ordo_wind.z * gust, 0.0, 2.0);
	float sp = max(s, 1e-3);
	float amp = flutter * pow(sp, pin_power) * w;
	float damp = flutter * pin_power * pow(sp, pin_power - 1.0) * w;
	float k = 6.2831853 * cloth_length / wave_length;
	float a1 = s * k - t * wave_speed * (0.6 + 0.4 * w) + ph;
	float a2 = s * k * 1.7 + q * 2.3 - t * wave_speed * 1.3 + ph * 1.7;
	float f = sin(a1) + 0.35 * sin(a2);
	float df = cos(a1) * k + 0.35 * cos(a2) * k * 1.7;
	float d = amp * f;
	float dd = (amp * df + damp * f) / cloth_length;   // наклон по длине, м/м
	vec3 n = NORMAL;
	vec3 v = VERTEX + n * d;
	// ткань не тянется: при колыхании свободный край чуть подтягивается, в штиль провисает
	v -= along_axis * abs(d) * 0.2 * s;
	v.y -= droop * s * s * (1.0 - clamp(w, 0.0, 1.0));
	n = normalize(n - along_axis * dd);
	if (follow_wind) {
		vec3 wl = (inverse(MODEL_MATRIX) * vec4(ordo_wind.x, 0.0, ordo_wind.y, 0.0)).xyz;
		vec2 wd = normalize(wl.xz + vec2(1e-5, 0.0));
		v = vec3(v.x * wd.x - v.z * wd.y, v.y, v.x * wd.y + v.z * wd.x);
		n = vec3(n.x * wd.x - n.z * wd.y, n.y, n.x * wd.y + n.z * wd.x);
	}
	VERTEX = v;
	NORMAL = n;
	PAINT_VERTEX;
}

void fragment() {
	vec4 a = texture(albedo_tex, UV) * albedo_tint;
	if (use_vertex_color) {
		a.rgb *= COLOR.rgb;
	}
	// изнанка: нормаль Godot уже развернул сам (cull_disabled → DO_SIDE_CHECK), второй разворот
	// освещал изнанку как лицо; здесь только темнее
	if (!FRONT_FACING) {
		a.rgb *= back_shade;
	}
	ALBEDO = a.rgb;
	ALPHA = a.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ROUGHNESS = 0.95;
	BACKLIGHT = vec3(translucency);
	paint_brush_v = paint_brush(v_world_pos, v_world_nrm);
}

void light() {
	DIFFUSE_LIGHT += paint_diffuse(NORMAL, LIGHT, LIGHT_COLOR, ATTENUATION, paint_brush_v, LIGHT_IS_DIRECTIONAL);
	// контровой свет окрашен цветом ткани (идёт в DIFFUSE, умножается на ALBEDO):
	// тонкое полотно против солнца горит своим цветом, а не белеет
	DIFFUSE_LIGHT += paint_rim(NORMAL, LIGHT, VIEW, LIGHT_COLOR, ATTENUATION, rim_strength) * 1.3;
	// на просвет: солнце с изнанки проходит сквозь тонкую ткань
	float through = clamp(-dot(NORMAL, LIGHT), 0.0, 1.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * ordo_key_tint.rgb * BACKLIGHT * through * ATTENUATION / PI;
}
