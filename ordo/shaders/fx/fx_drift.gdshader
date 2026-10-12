// Движение рисованных клубов (дым, пыль): торможение, всплытие, снос ветром ordo_wind, рост, поворот.
// Частицы пускает скрипт (GPUParticles3D.emit_particle):
//   позиция, скорость; COLOR — оттенок и непрозрачность;
//   CUSTOM: x — поворот спрайта, y — возраст (0 при пуске), z — размер при рождении, м,
//           w — доля общей жизни (0.05..1), поэтому клубы живут разное время.
// Возраст CUSTOM.y идёт 0→1 за LIFETIME × CUSTOM.w; рисующий шейдер берёт его оттуда же.
shader_type particles;

global uniform vec4 ordo_wind;

uniform float drag = 1.4;          // торможение к скорости ветра, 1/с
uniform float buoyancy = 0.25;     // всплытие, м/с²
uniform float wind_scale = 0.6;    // доля ветра ordo_wind (x, z — куда, z — сила)
uniform float grow = 2.6;          // во сколько раз вырастает к концу жизни
uniform float grow_curve = 2.4;    // быстрый рост вначале, медленный потом
uniform float spin = 0.12;         // поворот, рад/с
uniform float ground_y = 0.0;      // ниже не опускается (центр клуба)

float hash(uint n) {
	n = (n << 13u) ^ n;
	n = n * (n * n * 15731u + 789221u) + 1376312589u;
	return float(n & 0x7fffffffu) / float(0x7fffffff);
}

void start() {
	if (RESTART_CUSTOM) {
		CUSTOM = vec4(0.0, 0.0, 1.0, 1.0);
	}
	CUSTOM.y = 0.0;
	if (RESTART_POSITION) {
		TRANSFORM = EMISSION_TRANSFORM;
	}
	if (RESTART_VELOCITY) {
		VELOCITY = vec3(0.0);
	}
	if (RESTART_COLOR) {
		COLOR = vec4(1.0);
	}
}

void process() {
	float life = max(CUSTOM.w, 0.05);
	CUSTOM.y += DELTA / (LIFETIME * life);
	if (CUSTOM.y >= 1.0) {
		ACTIVE = false;
	}
	vec3 wind = vec3(ordo_wind.x, 0.0, ordo_wind.y) * ordo_wind.z * wind_scale;
	VELOCITY += (wind - VELOCITY) * min(drag * DELTA, 1.0);
	VELOCITY.y += buoyancy * DELTA * (1.0 - CUSTOM.y);
	float a = clamp(CUSTOM.y, 0.0, 1.0);
	float s = CUSTOM.z * mix(1.0, grow, 1.0 - pow(1.0 - a, grow_curve));
	CUSTOM.x += spin * DELTA * (hash(INDEX + 17u) * 2.0 - 1.0);
	vec3 p = TRANSFORM[3].xyz;
	p.y = max(p.y, ground_y + s * 0.35);
	TRANSFORM = mat4(vec4(s, 0.0, 0.0, 0.0), vec4(0.0, s, 0.0, 0.0), vec4(0.0, 0.0, s, 0.0), vec4(p, 1.0));
}
