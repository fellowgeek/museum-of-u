shader_type spatial;

uniform sampler2D bark : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 bark_pos;
varying vec3 bark_normal;

void vertex() {
	bark_pos = VERTEX;
	bark_normal = NORMAL;
}

// The right edge of the scan is outside its UV island. Mirror within the photographed bark.
vec3 sample_bark(vec2 uv) {
	vec2 folded = 1.0 - abs(fract(uv*.5)*2.0 - 1.0);
	return textureGrad(bark,vec2(.015,.03)+folded*vec2(.69,.94),dFdx(uv)*vec2(.69,.94),dFdy(uv)*vec2(.69,.94)).rgb;
}

void fragment() {
	vec3 w = abs(normalize(bark_normal));
	vec3 scanned = mix(sample_bark(bark_pos.xy*vec2(2.5,1.6)),sample_bark(bark_pos.zy*vec2(2.5,1.6)),w.x/(w.x+w.z+.001));
	float height = smoothstep(.25,2.5,bark_pos.y);
	vec3 paper = scanned * mix(vec3(.84,.85,.77),vec3(1.27,1.22,1.09),height)+.052*height;
	ALBEDO = mix(paper,paper*vec3(.58,.51,.41),smoothstep(5.2,10.6,bark_pos.y));
	ROUGHNESS = .91;
}
