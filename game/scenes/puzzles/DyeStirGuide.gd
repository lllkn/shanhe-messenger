extends Control
## A perspective guide around the vat mouth; never consumes pointer input.
var progress := 0.0
var active := false
var clock := 0.0

func _process(delta: float) -> void:
	if visible:
		clock += delta
		queue_redraw()

func _draw() -> void:
	var center := size * 0.5
	var radius := size * Vector2(0.46, 0.42)
	var track := PackedVector2Array()
	var completed := PackedVector2Array()
	for i in 97:
		var a := -PI * 0.5 + TAU * float(i) / 96.0
		var pt := center + Vector2(cos(a), sin(a)) * radius
		track.append(pt)
		if float(i) / 96.0 <= progress:
			completed.append(pt)
	draw_polyline(track, Color(0.93, 0.89, 0.75, 0.20), 1.5, true)
	if completed.size() > 1:
		draw_polyline(completed, Color("c9a24b"), 2.5, true)
	if not active:
		var a := clock * 0.9
		var point := center + Vector2(cos(a), sin(a)) * radius
		draw_circle(point, 4.0, Color(0.93, 0.83, 0.54, 0.7))
