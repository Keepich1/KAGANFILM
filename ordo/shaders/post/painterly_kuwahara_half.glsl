#[compute]
#version 450
// Живописный фильтр в уменьшенном кадре (вдвое или до 1080 точек по высоте), шаг 3: та же
// анизотропная Кувахара, что в painterly_kuwahara.glsl, но по уменьшенному кадру и без тона: пишет мазок
// («перцептивный» цвет, rgb) и долю мазка в этом месте (a: 1 — мазок, меньше — пёстрая деталь).
// Тон, холст и виньетку кладёт painterly_up в полном разрешении.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict readonly image2D src_image;
layout(rgba16f, set = 0, binding = 1) uniform restrict readonly image2D tensor_image;
layout(rgba16f, set = 0, binding = 2) uniform restrict writeonly image2D painted_image;

layout(push_constant, std430) uniform Params {
	vec2 size;
	float radius;       // радиус ядра, пикселей (уменьшенного кадра)
	float hardness;
	float q;
	float zeta;
	float zero_cross;
	float alpha;
} p;

void main() {
	ivec2 uv = ivec2(gl_GlobalInvocationID.xy);
	if (uv.x >= int(p.size.x) || uv.y >= int(p.size.y)) {
		return;
	}
	vec3 painted = imageLoad(src_image, uv).rgb;
	float keep = 1.0;

	if (p.radius >= 1.0) {
		vec3 t = imageLoad(tensor_image, uv).xyz;
		float E = t.x, F = t.y, G = t.z;
		float root = sqrt(max((E - G) * (E - G) + 4.0 * F * F, 0.0));
		float l1 = 0.5 * (E + G + root);
		float l2 = 0.5 * (E + G - root);
		vec2 v = vec2(l1 - E, -F);
		vec2 dir = length(v) > 1e-6 ? normalize(v) : vec2(0.0, 1.0);
		float phi = -atan(dir.y, dir.x);
		float A = (l1 + l2 > 1e-6) ? (l1 - l2) / (l1 + l2) : 0.0;

		float r = p.radius;
		float a = r * clamp((p.alpha + A) / p.alpha, 0.1, 2.0);
		float b = r * clamp(p.alpha / (p.alpha + A), 0.1, 2.0);
		float cp = cos(phi);
		float sp = sin(phi);
		mat2 R = mat2(cp, -sp, sp, cp);
		mat2 S = mat2(0.5 / a, 0.0, 0.0, 0.5 / b);
		mat2 SR = S * R;
		int mx = int(sqrt(a * a * cp * cp + b * b * sp * sp));
		int my = int(sqrt(a * a * sp * sp + b * b * cp * cp));

		float zeta = p.zeta;
		float sz = sin(p.zero_cross);
		float eta = (zeta + cos(p.zero_cross)) / (sz * sz);

		vec4 m[8];
		vec3 s[8];
		for (int k = 0; k < 8; k++) {
			m[k] = vec4(0.0);
			s[k] = vec3(0.0);
		}
		for (int y = -my; y <= my; y++) {
			for (int x = -mx; x <= mx; x++) {
				vec2 vv = SR * vec2(float(x), float(y));
				if (dot(vv, vv) > 0.25) {
					continue;
				}
				ivec2 qq = clamp(uv + ivec2(x, y), ivec2(0), ivec2(p.size) - 1);
				vec3 c = imageLoad(src_image, qq).rgb;
				float w[8];
				float sum = 0.0;
				float z;
				float vxx = zeta - eta * vv.x * vv.x;
				float vyy = zeta - eta * vv.y * vv.y;
				z = max(0.0, vv.y + vxx); w[0] = z * z; sum += w[0];
				z = max(0.0, -vv.x + vyy); w[2] = z * z; sum += w[2];
				z = max(0.0, -vv.y + vxx); w[4] = z * z; sum += w[4];
				z = max(0.0, vv.x + vyy); w[6] = z * z; sum += w[6];
				vec2 v2 = 0.70710678 * vec2(vv.x - vv.y, vv.x + vv.y);
				vxx = zeta - eta * v2.x * v2.x;
				vyy = zeta - eta * v2.y * v2.y;
				z = max(0.0, v2.y + vxx); w[1] = z * z; sum += w[1];
				z = max(0.0, -v2.x + vyy); w[3] = z * z; sum += w[3];
				z = max(0.0, -v2.y + vxx); w[5] = z * z; sum += w[5];
				z = max(0.0, v2.x + vyy); w[7] = z * z; sum += w[7];
				float g = exp(-3.125 * dot(vv, vv)) / max(sum, 1e-6);
				for (int k = 0; k < 8; k++) {
					float wk = w[k] * g;
					m[k] += vec4(c * wk, wk);
					s[k] += c * c * wk;
				}
			}
		}
		vec3 mean[8];
		float sig[8];
		float smin = 1e9;
		for (int k = 0; k < 8; k++) {
			float wsum = max(m[k].w, 1e-12);
			mean[k] = m[k].rgb / wsum;
			vec3 var = abs(s[k] / wsum - mean[k] * mean[k]);
			sig[k] = var.r + var.g + var.b;
			if (m[k].w > 1e-12) {
				smin = min(smin, sig[k]);
			}
		}
		vec4 outc = vec4(0.0);
		float base = 1.0 + pow(p.hardness * 1000.0 * smin, 0.5 * p.q);
		for (int k = 0; k < 8; k++) {
			if (m[k].w <= 1e-12) {
				continue;
			}
			float wk = base / (1.0 + pow(p.hardness * 1000.0 * sig[k], 0.5 * p.q));
			outc += vec4(mean[k] * wk, wk);
		}
		if (outc.w > 0.0) {
			painted = outc.rgb / outc.w;
		}
		// пёстрая деталь — ближе к исходнику (как в painterly_kuwahara)
		float busy = smoothstep(0.0015, 0.012, smin) * (1.0 - smoothstep(0.25, 0.7, A));
		keep = 1.0 - 0.6 * busy;
	}
	imageStore(painted_image, uv, vec4(painted, keep));
}
