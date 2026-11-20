shader_type spatial;
render_mode cull_disabled;
#include "res://assets/shaders/woodland_wind.gdshaderinc"

varying float warmth;
void vertex() {
	vec3 p = VERTEX;
	warmth = .5 + .5*sin(p.x*2.7+p.z*1.85+sin(p.y*3.27));
	VERTEX += woodland_sway(p, MODEL_MATRIX, TIME, .057);
}
void fragment() {
	float y = UV.y;
	float x = abs(UV.x-.5);
	float width = .349*pow(max(sin(3.14159*y),.001),.86)*(1.14-.35*y);
	width *= .96 + .04*fract(y*16.0);
	if (x > width) { discard; }
	float midrib = 1.0-smoothstep(.002,.014,x);
	float rib = abs(fract(7.0*y - x*4.4)-.5);
	float veins = (1.0-smoothstep(.015,.052,rib))*smoothstep(.014,.06,x);
	float pigment = .86+.12*sin(y*3.14159)+.09*cos(UV.x*20.0+y*6.1);
	vec3 leaf = mix(vec3(.10,.225,.042),vec3(.39,.38,.070),warmth)*pigment;
	ALBEDO = leaf + vec3(.076,.078,.026) * (midrib+.52*veins);
	BACKLIGHT = ALBEDO * .52;
	ROUGHNESS = .86;
}
