#[compute]
#version 450
// Живописный фильтр, шаг 2: размытие структурного тензора по Гауссу (раздельно по осям).

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict readonly image2D in_image;
layout(rgba16f, set = 0, binding = 1) uniform restrict writeonly image2D out_image;

layout(push_constant, std430) uniform Params {
	vec2 size;
	vec2 dir;
	float sigma;
	float pad0;
	float pad1;
	float pad2;
} p;

void main() {
	ivec2 uv = ivec2(gl_GlobalInvocationID.xy);
	if (uv.x >= int(p.size.x) || uv.y >= int(p.size.y)) {
		return;
	}
	int k = int(ceil(p.sigma * 2.5));
	vec4 acc = vec4(0.0);
	float wsum = 0.0;
	ivec2 d = ivec2(p.dir);
	for (int i = -k; i <= k; i++) {
		ivec2 q = clamp(uv + d * i, ivec2(0), ivec2(p.size) - 1);
		float w = exp(-float(i * i) / (2.0 * p.sigma * p.sigma));
		acc += imageLoad(in_image, q) * w;
		wsum += w;
	}
	imageStore(out_image, uv, acc / wsum);
}
