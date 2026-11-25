shader_type canvas_item;

// 在裁剪窗口的入口/出口逐像素淡化，避免卡片被生硬截断。
uniform float belt_top = 142.0;
uniform float belt_bottom = 586.0;
uniform float fade_width = 34.0;
varying float canvas_y;

void vertex() {
	canvas_y = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).y;
}

void fragment() {
	// fragment 的 COLOR 已包含纹理与节点调色，直接修改透明度。
	float edge = smoothstep(belt_top, belt_top + fade_width, canvas_y);
	edge *= 1.0 - smoothstep(belt_bottom - fade_width, belt_bottom, canvas_y);
	COLOR.a *= edge;
}
