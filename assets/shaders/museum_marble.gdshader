shader_type spatial;
// Staggered, honed slabs share the wing's coordinates through origin rebases.
uniform sampler2D marble_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool slabs = true;
uniform bool shadowless = false;
// Center X/Z, half span, and height of the lantern above this room.
uniform vec4 lantern;
uniform vec3 to_sun;
varying vec2 floor_position;
varying float facing_up;
void vertex() {
	facing_up = NORMAL.y;
	floor_position = abs(NORMAL.y) > 0.5 ? VERTEX.xz : vec2(dot(VERTEX.xz, abs(NORMAL.zx)), VERTEX.y);
}

float lantern_light(vec2 floor_at) {
	vec2 ray = to_sun.xz / max(to_sun.y, 0.01);
	vec2 at_roof = floor_at + ray * lantern.w - lantern.xy;
	vec2 corner = abs(at_roof) - (lantern.z - 1.5);
	float rim = length(max(corner, vec2(0.0))) + min(max(corner.x, corner.y), 0.0) - 1.5;
	float arch = clamp(1.0 - pow(abs(at_roof.x) / (lantern.z + 0.14), 2.0), 0.0, 1.0);
	float at_ribs = at_roof.y + ray.y * (0.50 + 0.32 * lantern.z * arch);
	float rib_distance = abs(fract((at_ribs + lantern.z) / 0.75) - 0.5) * 0.75;
	return (1.0 - smoothstep(-0.06, 0.06, rim)) * smoothstep(0.025, 0.115, rib_distance);
}
void fragment() {
	vec2 pitch = vec2(3.0, 1.5);
	vec2 course = floor_position / pitch;
	course.x += mod(floor(course.y), 2.0) * 0.5;
	float block = slabs ? fract(dot(floor(course), vec2(0.3819, 0.6180))) : 0.5;
	vec2 uv = floor_position * 0.28 + vec2(block, block * 1.7);
	vec3 stone = textureGrad(marble_color, uv, dFdx(floor_position) * 0.28, dFdy(floor_position) * 0.28).rgb;
	vec2 edge = min(fract(course), 1.0 - fract(course)) * pitch;
	vec2 footprint = max(fwidth(floor_position), vec2(0.0001));
	vec2 joint = (1.0 - smoothstep(vec2(0.001), vec2(0.003) + footprint, edge)) * min(vec2(1.0), 0.005 / footprint);
	float seam = slabs ? max(joint.x, joint.y) : 0.0;
	ALBEDO = mix(vec3(0.42, 0.37, 0.29), stone, 0.38) * (0.92 + 0.13 * block) * (1.0 - 0.46 * seam);
	ROUGHNESS = 0.48 + 0.12 * block + 0.14 * seam;
	SPECULAR = 0.28;
	if (shadowless && facing_up > 0.9) {
		EMISSION = ALBEDO * vec3(1.0, 0.82, 0.61) * lantern_light(floor_position) * 0.76;
	}
}
