shader_type spatial;
render_mode cull_disabled;
uniform vec4 base_color : source_color = vec4(0.2,0.35,0.1,1.0);
uniform float surface_roughness = 0.85;
uniform float wind_time = 0.0;
uniform float amplitude = 0.14;
// 0 = tree canopy, 1 = tea shrubs, 2 = cloth fixed at the top edge.
uniform int movement_kind = 0;
void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
	float phase = world.x*0.48 + world.z*0.37;
	float wave = sin(wind_time*1.35+phase)*0.65 + sin(wind_time*0.62+phase*0.3)*0.35;
	float weight = smoothstep(1.3,5.0,world.y);
	if (movement_kind==1) { weight = 0.65; }
	if (movement_kind==2) { weight = 1.0-smoothstep(1.46,2.13,world.y); }
	vec3 offset = vec3(wave, sin(wind_time*1.1+phase)*0.12, cos(wind_time+phase)*0.42)*amplitude*weight;
	VERTEX += (inverse(MODEL_MATRIX)*vec4(offset,0.0)).xyz;
}
void fragment() {
	ALBEDO = base_color.rgb;
	ROUGHNESS = surface_roughness;
}
