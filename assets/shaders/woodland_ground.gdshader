shader_type spatial;

uniform sampler2D leaf_litter : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D litter_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D meadow : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D limestone : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 court;
uniform vec2 glade;
uniform float glade_radius;
uniform float deep_woods_x;

void fragment() {
	vec2 p = UV;
	vec3 litter = texture(leaf_litter, p / 3.15).rgb;
	vec3 broad = texture(leaf_litter, p.yx / 10.4).rgb;
	float mottling = clamp(dot(broad, vec3(.27, .58, .15)) * 2.6, 0.0, 1.0);
	vec3 grass = texture(meadow, p / 3.85).rgb;
	float patch = .5 + .5*sin(p.x*.40 + sin(p.y*.47)*1.4)*cos(p.y*.27-p.x*.21);
	vec3 green = vec3(grass.g*.64, grass.g*1.04, grass.b*.65);
	vec3 earth = mix(litter * vec3(.76,.81,.60), green, smoothstep(.03,.72,patch+mottling*.16)*.88);
	float woods = smoothstep(deep_woods_x-3.0,deep_woods_x+8.0,p.x);
	vec3 duff = mix(litter * vec3(.81,.75,.61), green*.85, smoothstep(.36,.92,patch)*.50);
	earth = mix(earth,duff,woods);
	float trail = smoothstep(.06, .88, COLOR.r + (mottling - .4) * .22 * smoothstep(0.0,.28,COLOR.r));
	vec3 grains = texture(gravel, p / 2.4).rgb;
	vec3 path = mix(grains, vec3(dot(grains,vec3(.27,.58,.15))), .54)*vec3(1.02,.97,.88);
	vec2 edge = min(p - court.xy, court.zw - p);
	float radial = length(p - glade);
	float paving = max(smoothstep(-.035, .035, min(edge.x, edge.y)), 1.0 - smoothstep(glade_radius-.035, glade_radius+.035, radial));
	vec2 stones = p / vec2(1.18, .64);
	stones.x += mod(floor(stones.y), 2.0) * .5;
	vec2 joint = (.5 - abs(fract(stones) - .5)) * vec2(1.18, .64);
	float line = min(joint.x, joint.y);
	float aa = max(.003, fwidth(p.x) + fwidth(p.y));
	float mortar = smoothstep(-aa, .011+aa, line);
	vec3 stone = texture(limestone, p / 2.1).rgb;
	vec3 tiles = mix(vec3(.27, .246, .20), stone * vec3(.88, .80, .64) + .17, mortar);
	float rim = 1.0 - smoothstep(.07, .115, abs(radial - glade_radius + .17));
	tiles *= 1.0 - rim * .29;
	ALBEDO = mix(mix(earth, path, trail), tiles, paving);
	NORMAL_MAP = mix(texture(litter_normal, p / 3.15).rgb, vec3(.5,.5,1.0), max(trail*.84, paving));
	NORMAL_MAP_DEPTH = .43;
	ROUGHNESS = mix(.96, .78, paving);
	SPECULAR = .23;
}
