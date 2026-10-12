#[compute]
#version 450
// Живописный фильтр в половине разрешения («Среднее», «Низкое»), шаг 1:
// кадр → вдвое меньше, в «перцептивном» виде (как у painterly_tensor: HDR сжат в 0..1, корень),
// каждая точка — среднее четырёх точек кадра.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict readonly image2D color_image;
layout(rgba16f, set = 0, binding = 1) uniform restrict writeonly image2D half_image;

layout(push_constant, std430) uniform Params {
	vec2 size;   // кадр
	vec2 hsize;  // половина
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
	ivec2 q = uv * 2;
	vec3 c = load_c(q) + load_c(q + ivec2(1, 0)) + load_c(q + ivec2(0, 1)) + load_c(q + ivec2(1, 1));
	imageStore(half_image, uv, vec4(c * 0.25, 1.0));
}
