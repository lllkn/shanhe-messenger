shader_type canvas_item;
// 仅在游戏绘制时淡化残页外围纯白，原始米色纸纹和素材文件保留。
void fragment() {
	vec4 source = texture(TEXTURE, UV);
	float white = smoothstep(0.94, 0.975, min(source.r, min(source.g, source.b)));
	COLOR.a *= 1.0 - white;
}
