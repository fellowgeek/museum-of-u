shader_type spatial;
render_mode cull_disabled;
#include "res://assets/shaders/woodland_wind.gdshaderinc"

uniform sampler2D spray : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float amplitude = .052;
void vertex() {
	VERTEX += woodland_sway(VERTEX, MODEL_MATRIX, TIME, amplitude);
}
void fragment() {
	vec4 leaf = texture(spray, UV);
	ALBEDO = leaf.rgb;
	ROUGHNESS = .84;
	SPECULAR = .27;
	ALPHA = leaf.a;
	ALPHA_SCISSOR_THRESHOLD = .33;
}
