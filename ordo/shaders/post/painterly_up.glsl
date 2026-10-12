#[compute]
#version 450
// Живописный фильтр в половине разрешения, шаг 4: мазки (painterly_kuwahara_half) → полный кадр.
// Увеличение бережное (совместное двустороннее): из четырёх соседних точек половинного кадра
// больше весят те, что похожи цветом на исходную точку кадра, — край мазка не расплывается
// через контур. Мелочь, которой в половинном кадре нет (вспышка, древко, блик): ни одна из
// четырёх точек на неё не похожа — там остаётся исходная точка кадра. Затем тот же тон, что
// в painterly_kuwahara («Высокое»): цветные тени, тёплый свет, холст и виньетка — в полном разрешении.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict image2D color_image;
layout(rgba16f, set = 0, binding = 1) uniform restrict readonly image2D src_image;      // половина, «перцептивный»
layout(rgba16f, set = 0, binding = 2) uniform restrict readonly image2D painted_image;  // половина, мазок + доля

layout(push_constant, std430) uniform Params {
	vec2 size;
	vec2 hsize;
	vec4 lift;          // rgb — цвет подъёма теней, a — сила
	vec4 warm;          // rgb — тёплый множитель светов, a — сила
	float grain;
	float vignette;
	float amount;
	float shadow_range;
	float guide_k;      // строгость совпадения цвета при увеличении
	float pad0;
	float pad1;
	float pad2;
} p;

vec3 encode(vec3 c) {
	c = max(c, vec3(0.0));
	return sqrt(c / (1.0 + c));
}

vec3 decode(vec3 e) {
	vec3 y = min(e * e, vec3(0.995));
	return y / (1.0 - y);
}

float hash(vec2 v) {
	vec3 p3 = fract(vec3(v.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void main() {
	ivec2 uv = ivec2(gl_GlobalInvocationID.xy);
	if (uv.x >= int(p.size.x) || uv.y >= int(p.size.y)) {
		return;
	}
	vec4 orig = imageLoad(color_image, uv);
	vec3 guide = encode(orig.rgb);
	vec2 hp = (vec2(uv) + 0.5) * 0.5 - 0.5;
	ivec2 b = ivec2(floor(hp));
	vec2 f = hp - vec2(b);
	vec4 acc = vec4(0.0);
	float wsum = 0.0;
	float best = 0.0;
	for (int j = 0; j < 2; j++) {
		for (int i = 0; i < 2; i++) {
			ivec2 q = clamp(b + ivec2(i, j), ivec2(0), ivec2(p.hsize) - 1);
			float wb = (i == 0 ? 1.0 - f.x : f.x) * (j == 0 ? 1.0 - f.y : f.y);
			vec3 d = guide - imageLoad(src_image, q).rgb;
			// по цвету + малая доля обычного увеличения (чтобы не делить на ноль)
			float wr = exp(-dot(d, d) * p.guide_k);
			best = max(best, wr);
			float w = wb * (wr + 1e-4);
			acc += imageLoad(painted_image, q) * w;
			wsum += w;
		}
	}
	vec4 pt = acc / max(wsum, 1e-8);
	float local_amount = p.amount * pt.a * smoothstep(0.05, 0.5, best);
	vec3 col = mix(orig.rgb, decode(pt.rgb), local_amount);

	// тон: цветные тени (не чёрные), тёплый свет — как в painterly_kuwahara
	float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
	float sh = 1.0 - smoothstep(0.0, p.shadow_range, lum);
	col += p.lift.rgb * p.lift.a * sh;
	float hi = smoothstep(0.35, 1.6, lum);
	col *= mix(vec3(1.0), p.warm.rgb, hi * p.warm.a);

	// фактура холста: переплетение нитей и мелкое зерно
	vec2 fp = vec2(uv);
	float weave = sin(fp.x * 1.9) * sin(fp.y * 1.9 + sin(fp.x * 0.11) * 2.0);
	float n = hash(floor(fp * 0.5)) - 0.5;
	col *= 1.0 + p.grain * (weave * 0.6 + n * 0.8);

	// виньетка
	vec2 cuv = (fp / p.size - 0.5) * vec2(p.size.x / p.size.y, 1.0);
	float dd = length(cuv);
	col *= 1.0 - p.vignette * smoothstep(0.35, 1.05, dd);

	imageStore(color_image, uv, vec4(col, orig.a));
}
