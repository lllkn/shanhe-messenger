shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform float wind_time = 0.0;
uniform float phase = 0.0;
void vertex() {
	VERTEX.x += sin(wind_time*0.38+VERTEX.y*1.5+phase)*0.13;
	VERTEX.z += cos(wind_time*0.31+VERTEX.y+phase)*0.09;
}
void fragment() {
	float ribbon = 0.55+0.45*sin(UV.y*15.0+UV.x*9.0-wind_time*0.6+phase);
	float rim = pow(clamp(dot(normalize(NORMAL),normalize(VIEW)),0.0,1.0),0.7);
	ALBEDO = vec3(0.65,0.85,0.80);
	ALPHA = (0.055+ribbon*0.12)*rim;
}
