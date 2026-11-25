shader_type canvas_item;
render_mode unshaded;

uniform vec4 dye_color : source_color = vec4(0.24, 0.30, 0.28, 1.0);
uniform float flow = 0.0;
uniform float energy : hint_range(0.0, 1.0) = 0.0;
uniform float clarity : hint_range(0.0, 1.0) = 0.0;
uniform float clock = 0.0;
uniform vec2 spoon = vec2(0.5);

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float spiral = a * 3.0 + r * 13.0 - flow * 1.8;
	float cloud = sin(spiral + sin(a * 4.0 - r * 7.0 + clock * 0.3)) * 0.5 + 0.5;
	float grain = sin(p.x * 36.0 + p.y * 29.0) * sin(p.y * 42.0 - p.x * 17.0);
	vec3 deep = dye_color.rgb * 0.40;
	vec3 light = mix(dye_color.rgb, vec3(0.83, 0.84, 0.68), 0.10);
	vec3 water = mix(deep, light, 0.36 + cloud * (0.42 - clarity * 0.25));
	water += grain * 0.012;
	float ribbon = pow(max(0.0, sin(spiral)), 18.0) * energy;
	float rings = pow(max(0.0, sin(r * 57.0 - clock * 3.4 + sin(a * 3.0 + flow) * energy)), 22.0);
	water += vec3(0.80, 0.83, 0.69) * (ribbon * 0.16 + rings * (0.028 + energy * 0.05));
	float wake_distance = length((UV - spoon) * 2.0);
	float wake = pow(max(0.0, sin(wake_distance * 60.0 - clock * 9.0)), 10.0);
	water += vec3(0.70, 0.78, 0.66) * wake * exp(-wake_distance * 6.0) * energy * 0.17;
	water *= 1.0 - smoothstep(0.67, 1.0, r) * 0.46;
	float glint = exp(-pow((p.y + 0.43) * 8.0, 2.0)) * exp(-p.x * p.x * 2.8);
	water += vec3(0.72, 0.78, 0.66) * glint * 0.10;
	COLOR = vec4(water, (1.0 - smoothstep(0.97, 1.0, r)) * dye_color.a);
}
