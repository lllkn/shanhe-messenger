extends Control
## 卡通反馈的小星星、短线与气泡；使用绘制图元，不新增位图素材。
var success := true
var progress := 0.0:
	set(value):
		progress = value
		queue_redraw()

func _draw() -> void:
	var colors := [Color("#FFE49C"), Color("#F9C66A"), Color("#F6F0D8")]
	var count := 9 if success else 5
	for i in count:
		var angle := TAU * float(i) / count - 0.35
		var radius := lerpf(48.0, 118.0, progress)
		var center := Vector2(cos(angle), sin(angle)) * radius
		var color: Color = colors[i % colors.size()] if success else Color("#F7A78F")
		color.a = 1.0 - progress
		if success and i % 2 == 0:
			var points := PackedVector2Array()
			var star_radius := (10.0 if i % 3 == 0 else 7.0) * (1.0 - progress * 0.5)
			for j in 8:
				var theta := TAU * j / 8.0
				var length := star_radius if j % 2 == 0 else star_radius * 0.28
				points.append(center + Vector2(cos(theta), sin(theta)) * length)
			draw_colored_polygon(points, color)
		else:
			draw_circle(center, 3.5 * (1.0 - progress * 0.5), color, true, -1.0, true)
			if success:
				draw_line(center, center + Vector2(cos(angle), sin(angle)) * 10.0, color, 3.0, true)
