// Неподвижная короткая частица (вспышка выстрела): только возраст. Трансформ пуска сохраняется —
// его ось X несёт направление и длину вспышки. CUSTOM.w — доля общей жизни.
shader_type particles;
render_mode disable_velocity;

void start() {
	if (RESTART_CUSTOM) {
		CUSTOM = vec4(0.0, 0.0, 1.0, 1.0);
	}
	CUSTOM.y = 0.0;
	if (RESTART_POSITION) {
		TRANSFORM = EMISSION_TRANSFORM;
	}
}

void process() {
	CUSTOM.y += DELTA / (LIFETIME * max(CUSTOM.w, 0.05));
	if (CUSTOM.y >= 1.0) {
		ACTIVE = false;
	}
}
