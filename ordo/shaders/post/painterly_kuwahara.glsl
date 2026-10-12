#[compute]
#version 450
// Живописный фильтр, шаг 3: анизотропный фильтр Кувахары (Kyprianidis 2009,
// полиномиальные веса секторов) — пятна цвета вытягиваются вдоль контуров, как мазки.
// Затем тон: холодный сине-бирюзовый подъём теней, тёплый скат светов, фактура
// холста и виньетка. Пишет обратно в кадр (HDR, до тональной кривой).

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict readonly image2D src_image;
layout(rgba16f, set = 0, binding = 1) uniform restrict readonly image2D tensor_image;
layout(rgba16f, set = 0, binding = 2) uniform restrict image2D color_image;

layout(push_constant, std430) uniform Params {
	vec2 size;
	float radius;       // радиус ядра, пикселей
	float hardness;     // чем больше, тем резче выбор сектора
	float q;            // степень в весах секторов
	float zeta;         // перекрытие секторов в центре
	float zero_cross;   // угол обнуления веса сектора, рад
	float alpha;        // вытянутость эллипса вдоль контура
	vec4 lift;          // rgb — цвет подъёма теней, a — сила
	vec4 warm;          // rgb — тёплый множитель светов, a — сила
	float grain;        // фактура холста
	float vignette;
	float amount;       // доля живописного фильтра (0 — только тон)
	float shadow_range; // яркость, ниже которой тень поднимается
} p;

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
	vec3 painted = imageLoad(src_image, uv).rgb;

	if (p.amount > 0.001 && p.radius >= 1.0) {
		// направление и анизотропия из тензора
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
		// веса секторов по разбросу цвета; в пёстрых местах они очень малы (~1e-10),
		// поэтому нормируем на самый спокойный сектор, чтобы не уйти в ноль
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
	}
	vec3 col = mix(orig.rgb, decode(painted), p.amount);

	// тон: цветные тени (не чёрные), тёплый свет
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
	float d = length(cuv);
	col *= 1.0 - p.vignette * smoothstep(0.35, 1.05, d);

	imageStore(color_image, uv, vec4(col, orig.a));
}
