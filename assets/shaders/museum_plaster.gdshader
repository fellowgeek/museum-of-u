shader_type spatial;
// Broad limewash variation stays fixed to the wing when the world origin moves.
uniform vec4 plaster_color : source_color = vec4(0.70, 0.67, 0.61, 1.0);
uniform sampler2D plaster : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 surface_position;
varying vec3 face_normal;
void vertex() {
	surface_position = VERTEX;
	face_normal = NORMAL;
}
void fragment() {
	vec2 uv = abs(face_normal.y) > 0.7 ? surface_position.xz : vec2(dot(surface_position.xz, abs(face_normal.zx)), surface_position.y);
	float grain = texture(plaster, uv * 0.47).g;
	float wash = sin(surface_position.x * 1.7 + sin(surface_position.y * 2.1))
		* sin(surface_position.z * 1.4 + surface_position.y * 0.8);
	ALBEDO = plaster_color.rgb * (0.80 + grain * 0.38 + wash * 0.024);
	ROUGHNESS = 0.92;
	SPECULAR = 0.16;
}
