// Пух ковыля и пепел в воздухе: рождаются в коробке вокруг узла (узел ходит за камерой),
// плывут по ветру ordo_wind, порхают; CUSTOM.y — возраст, CUSTOM.x — поворот, CUSTOM.z — размер.
shader_type particles;

global uniform vec4 ordo_wind;

uniform vec3 box = vec3(60.0, 14.0, 60.0);
uniform float height = 0.6;          // низ коробки над узлом, м
uniform float size_min = 0.05;
uniform float size_max = 0.12;
uniform float wind_scale = 1.6;
uniform float flutter = 0.6;
uniform float rise = 0.05;

float hash(uint n) {
	n = (n << 13u) ^ n;
	n = n * (n * n * 15731u + 789221u) + 1376312589u;
	return float(n & 0x7fffffffu) / float(0x7fffffff);
}

void start() {
	uint s = RANDOM_SEED + INDEX * 7u;
	vec3 r = vec3(hash(s), hash(s + 1u), hash(s + 2u));
	vec3 org = EMISSION_TRANSFORM[3].xyz;
	vec3 p = org + vec3((r.x - 0.5) * box.x, height + r.y * box.y, (r.z - 0.5) * box.z);
	float sz = mix(size_min, size_max, hash(s + 3u));
	TRANSFORM = mat4(vec4(sz, 0.0, 0.0, 0.0), vec4(0.0, sz, 0.0, 0.0), vec4(0.0, 0.0, sz, 0.0), vec4(p, 1.0));
	VELOCITY = vec3(0.0);
	CUSTOM = vec4(hash(s + 4u) * 6.28, 0.0, sz, hash(s + 5u));
	COLOR = vec4(1.0);
}

void process() {
	CUSTOM.y += DELTA / LIFETIME;
	vec3 wind = vec3(ordo_wind.x, 0.0, ordo_wind.y) * ordo_wind.z * wind_scale;
	float ph = TIME * (1.3 + CUSTOM.w) + CUSTOM.w * 40.0;
	vec3 fl = vec3(sin(ph), sin(ph * 1.7 + 1.0) * 0.6, cos(ph * 0.8)) * flutter;
	VELOCITY = wind + fl + vec3(0.0, rise, 0.0);
	CUSTOM.x += DELTA * (CUSTOM.w - 0.5) * 3.0;
}
