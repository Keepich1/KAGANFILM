#[compute]
#version 450
// Живописный фильтр в уменьшенном кадре, шаг 1: кадр → меньше (вдвое — «Среднее», «Низкое»;
// до 1080 точек по высоте — «Высокое» на мониторах 1440p и 4K), в «перцептивном» виде (как у
// painterly_tensor: HDR сжат в 0..1, корень). Каждая точка — среднее точек кадра под ней
// с долями площади (при уменьшении ровно вдвое — простое среднее четырёх точек, как раньше).

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict readonly image2D color_image;
layout(rgba16f, set = 0, binding = 1) uniform restrict writeonly image2D half_image;

layout(push_constant, std430) uniform Params {
	vec2 size;   // кадр
	vec2 hsize;  // уменьшенный кадр
	vec2 step;   // сколько точек кадра на точку уменьшенного (1..2 по каждой оси)
	float pad0;
	float pad1;
} p;

vec3 encode(vec3 c) {
	c = max(c, vec3(0.0));
	return sqrt(c / (1.0 + c));
}

vec3 load_c(ivec2 q) {
	q = clamp(q, ivec2(0), ivec2(p.size) - 1);
	return encode(imageLoad(color_image, q).rgb);
}

void main() {
	ivec2 uv = ivec2(gl_GlobalInvocationID.xy);
	if (uv.x >= int(p.hsize.x) || uv.y >= int(p.hsize.y)) {
		return;
	}
	// след точки в кадре: [uv·step, (uv + 1)·step) — не больше трёх точек кадра по оси
	vec2 a = vec2(uv) * p.step;
	vec2 b = a + p.step;
	ivec2 i0 = ivec2(floor(a));
	vec3 c = vec3(0.0);
	float wsum = 0.0;
	for (int j = 0; j < 3; j++) {
		float y0 = float(i0.y + j);
		float wy = min(b.y, y0 + 1.0) - max(a.y, y0);
		if (wy <= 0.0) {
			continue;
		}
		for (int i = 0; i < 3; i++) {
			float x0 = float(i0.x + i);
			float wx = min(b.x, x0 + 1.0) - max(a.x, x0);
			if (wx <= 0.0) {
				continue;
			}
			float w = wx * wy;
			c += load_c(i0 + ivec2(i, j)) * w;
			wsum += w;
		}
	}
	imageStore(half_image, uv, vec4(c / max(wsum, 1e-6), 1.0));
}
