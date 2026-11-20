shader_type spatial;

uniform sampler2D court_view : source_color, filter_linear_mipmap, repeat_enable;
varying vec2 pool_position;
varying mat3 view_to_basin;

void vertex() {
	pool_position = VERTEX.xz;
	view_to_basin = transpose(mat3(MODELVIEW_MATRIX));
}

void fragment() {
	vec2 p = pool_position + vec2(4.3, 1.5);
	float t = TIME * .83;
	vec2 from_inlet = p - vec2(.60, 1.5);
	float radius = length(from_inlet);
	vec2 rings = from_inlet / max(radius, .01) * sin(radius * 25.0 - t * 3.2) * exp(-radius * .92);
	vec2 slope = .006 * vec2(sin(p.y*8.1+p.x*2.4-t)+.5*cos(p.x*4.3+t), cos(p.x*5.6-p.y*2.1+t*.71)) + rings*.021;
	vec3 n = normalize(vec3(slope.x,1.0,slope.y));
	vec3 eye = normalize(view_to_basin*VIEW);
	vec3 reflected = reflect(-eye,n);
	// Project the local court capture onto a box so the reflections move across the basin.
	vec3 at = vec3(pool_position.x,-.12,pool_position.y);
	vec3 walls = mix(vec3(-13,-3,-10),vec3(13,9,10),step(vec3(0.0),reflected));
	vec3 times = abs(walls-at)/max(abs(reflected),vec3(.0001));
	vec3 dir = normalize(at + reflected * min(times.x,min(times.y,times.z)));
	vec2 uv = vec2(atan(dir.z,dir.x)/TAU+.5, acos(clamp(dir.y,-1.0,1.0))/PI);
	vec3 mirrored = textureLod(court_view,uv,.65).rgb;
	float fresnel = .09 + .76*pow(1.0-clamp(dot(eye,n),0.0,1.0),2.35);
	float depth = smoothstep(0.0,.38,min(min(p.x,8.6-p.x),min(p.y,3.0-p.y)));
	vec3 bed = mix(vec3(.069,.121,.096),vec3(.016,.072,.058),depth);
	ALBEDO = bed*(1.0-fresnel);
	EMISSION = mirrored*fresnel*1.28;
	NORMAL_MAP = vec3(.5+slope.x,.5+slope.y,1.0);
	ROUGHNESS = .23;
	SPECULAR = .18;
}
