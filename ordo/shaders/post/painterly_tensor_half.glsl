#[compute]
#version 450
// Живописный фильтр в уменьшенном кадре, шаг 2: структурный тензор (направление мазков)
// по уже уменьшенному «перцептивному» кадру (painterly_down). Как painterly_tensor, без копии.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict readonly image2D src_image;
layout(rgba16f, set = 0, binding = 1) uniform restrict writeonly image2D tensor_image;

layout(push_constant, std430) uniform Params {
	vec2 size;
	float pad0;
	float pad1;
} p;

vec3 load_c(ivec2 q) {
	q = clamp(q, ivec2(0), ivec2(p.size) - 1);
	return imageLoad(src_image, q).rgb;
}

void main() {
	ivec2 uv = ivec2(gl_GlobalInvocationID.xy);
	if (uv.x >= int(p.size.x) || uv.y >= int(p.size.y)) {
		return;
	}
	vec3 c00 = load_c(uv + ivec2(-1, -1));
	vec3 c10 = load_c(uv + ivec2(0, -1));
	vec3 c20 = load_c(uv + ivec2(1, -1));
	vec3 c01 = load_c(uv + ivec2(-1, 0));
	vec3 c21 = load_c(uv + ivec2(1, 0));
	vec3 c02 = load_c(uv + ivec2(-1, 1));
	vec3 c12 = load_c(uv + ivec2(0, 1));
	vec3 c22 = load_c(uv + ivec2(1, 1));
	vec3 sx = (c00 + 2.0 * c01 + c02 - c20 - 2.0 * c21 - c22) * 0.25;
	vec3 sy = (c00 + 2.0 * c10 + c20 - c02 - 2.0 * c12 - c22) * 0.25;
	imageStore(tensor_image, uv, vec4(dot(sx, sx), dot(sx, sy), dot(sy, sy), 1.0));
}
