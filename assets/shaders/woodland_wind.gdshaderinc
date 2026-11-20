// The world-space wave repeats across a 42 m origin shift. Trunk meshes stay fixed.
vec3 woodland_sway(vec3 p, mat4 model, float clock, float amplitude) {
	vec3 world = (model * vec4(p, 1.0)).xyz;
	float phase = world.x * .19 + world.z * (6.2831853 / 42.0);
	float gust = sin(clock * .82 + phase) + .32 * sin(clock * 1.47 + 2.0 * phase + p.x * .46);
	float tips = smoothstep(1.2, 6.0, p.y) * mix(.45, 1.0, smoothstep(.3, 2.6, length(p.xz)));
	vec3 motion = vec3(gust, .14 * sin(clock * 1.34 + phase + p.z), gust * .41) * tips * amplitude;
	return transpose(mat3(model)) * motion / max(dot(model[0].xyz, model[0].xyz), .0001);
}
