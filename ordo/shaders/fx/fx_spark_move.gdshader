// Полёт искр: тяжесть, сопротивление воздуха; ось X трансформа = скорость × trail (для следа).
shader_type particles;

uniform float gravity = 9.0;
uniform float drag = 2.5;
uniform float trail = 0.07;

void start() {
	if (RESTART_CUSTOM) {
		CUSTOM = vec4(0.0, 0.0, 1.0, 1.0);
	}
	CUSTOM.y = 0.0;
	if (RESTART_POSITION) {
		TRANSFORM = EMISSION_TRANSFORM;
	}
	if (RESTART_VELOCITY) {
		VELOCITY = vec3(0.0, 2.0, 0.0);
	}
}

void process() {
	CUSTOM.y += DELTA / (LIFETIME * max(CUSTOM.w, 0.05));
	if (CUSTOM.y >= 1.0) {
		ACTIVE = false;
	}
	VELOCITY.y -= gravity * DELTA;
	VELOCITY *= 1.0 - min(drag * DELTA, 0.9);
	vec3 p = TRANSFORM[3].xyz;
	TRANSFORM = mat4(vec4(VELOCITY * trail, 0.0), vec4(0.0, 1.0, 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(p, 1.0));
}
