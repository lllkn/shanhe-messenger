shader_type canvas_item;
render_mode unshaded;

// 0 = 云幕完全闭合；1 = 云层散尽。只在运行时采样用户已有透明云素材。
uniform float opening : hint_range(0.0, 1.0) = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 centered = UV - vec2(0.5);
	vec2 drift_uv = centered / (1.0 + opening * 0.65) + vec2(0.5);
	vec4 edge = texture(TEXTURE, drift_uv);
	// 云图中央本身透明，用其左侧云团填满遮挡阶段，透明区以暖白补底。
	vec4 fill = texture(TEXTURE, vec2(UV.x * 0.24, UV.y));
	vec3 cloud = mix(vec3(0.965, 0.944, 0.901), fill.rgb, fill.a);
	cloud = mix(cloud, edge.rgb, edge.a);
	float billow = noise(UV * 7.0) * 0.08 + noise(UV * 19.0) * 0.025;
	float distance_from_center = length(centered * vec2(1.35, 1.0)) + billow;
	float radius = opening * 1.3 - 0.14;
	float alpha = smoothstep(radius - 0.09, radius + 0.09, distance_from_center);
	alpha *= 1.0 - smoothstep(0.88, 1.0, opening);
	COLOR = vec4(cloud, alpha);
}
