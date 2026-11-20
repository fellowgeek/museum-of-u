shader_type spatial;

uniform sampler2D oak : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool boards = false;
uniform vec3 grain_axis = vec3(1.0, 0.0, 0.0);
varying vec3 local_position;
varying vec3 local_normal;

void vertex() {
	local_position = VERTEX;
	local_normal = NORMAL;
}

void fragment() {
	// The photographed veneer has vertical grain. Run it along the span.
	vec3 transverse = cross(grain_axis, local_normal);
	float across = dot(local_position, transverse) / max(length(transverse), 0.001);
	vec2 uv = vec2(across, dot(local_position, grain_axis)) / vec2(1.8, 2.8);
	if (abs(dot(grain_axis, local_normal)) > 0.99) {
		uv = abs(local_normal.y) > 0.5 ? local_position.xz : vec2(local_position.x + local_position.z, local_position.y);
	}
	float offset = boards ? fract(floor(across / 0.30) * 0.618) : 0.0;
	vec3 grain = textureGrad(oak, uv + vec2(offset), dFdx(uv), dFdy(uv)).rgb;
	vec3 wood = mix(grain, vec3(0.53, 0.34, 0.18), 0.26);
	if (boards) {
		float distance_to_edge = abs(fract(across / 0.30 + 0.5) - 0.5) * 0.30;
		float joint = 1.0 - smoothstep(0.001, 0.004 + fwidth(across), distance_to_edge);
		wood *= 1.0 - joint * 0.27;
	}
	ALBEDO = wood;
	ROUGHNESS = 0.64;
	SPECULAR = 0.26;
}
