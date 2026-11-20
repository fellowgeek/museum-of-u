shader_type spatial;
// Glazed utility tiles below the paint line. Wing-local coordinates keep the
// joints aligned when the museum shifts its physical origin.
varying vec2 wall_uv;
void vertex() {
	wall_uv = vec2(dot(VERTEX.xz,abs(NORMAL.zx)),VERTEX.y);
}
void fragment() {
	vec2 pitch = vec2(0.60,0.30);
	vec2 tile = wall_uv / pitch;
	tile.x += 0.5 * mod(floor(tile.y),2.0);
	vec2 distance_to_joint = min(fract(tile),1.0-fract(tile))*pitch;
	vec2 footprint = max(fwidth(wall_uv),vec2(.0005));
	vec2 line = (1.0-smoothstep(vec2(.001),vec2(.004)+footprint,distance_to_joint))*min(vec2(1.0),.006/footprint);
	float joint = max(line.x,line.y);
	float variation = fract(dot(floor(tile),vec2(.382,.618)));
	vec3 enamel = mix(vec3(.215,.303,.275),vec3(.251,.342,.308),variation);
	float lower = 1.0-smoothstep(2.398,2.402,wall_uv.y);
	ALBEDO = mix(vec3(.46,.465,.405),mix(enamel,vec3(.12,.15,.14),joint),lower);
	ROUGHNESS = mix(.83,.39+.45*joint,lower);
	SPECULAR = .34;
}
