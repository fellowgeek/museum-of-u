shader_type spatial;
render_mode cull_disabled;

void fragment() {
	float edge = smoothstep(0.0,.14,min(UV.x,1.0-UV.x));
	float glint = pow(.5+.5*sin(UV.x*35.0+sin(UV.y*10.0-TIME*4.1)),4.0);
	ALBEDO = mix(vec3(.17,.30,.26),vec3(.64,.78,.71),glint);
	ROUGHNESS = .12;
	SPECULAR = .82;
	ALPHA = edge*(.23+glint*.30);
}
