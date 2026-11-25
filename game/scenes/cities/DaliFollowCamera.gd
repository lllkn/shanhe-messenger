extends RefCounted
## 固定跟随、手动轨道。建筑不干预角度和距离，只有地面高度跟随做平滑。
var focus_position := Vector3.ZERO
var current_length := 12.0

func update(camera: Camera3D, player: CharacterBody3D, yaw: float, pitch: float, distance: float, delta: float, reset: bool) -> void:
	var wanted_focus := player.global_position + Vector3(0, 0.8, 0)
	var height := wanted_focus.y
	if not reset and player.is_on_floor() and absf(height - focus_position.y) < 1.0:
		height = lerpf(focus_position.y, height, 1.0 - exp(-14.0 * maxf(delta, 0.0)))
	focus_position = Vector3(wanted_focus.x, height, wanted_focus.z)
	current_length = distance
	var direction := Basis(Vector3.UP, yaw) * Vector3(0, sin(pitch), cos(pitch))
	camera.global_position = focus_position + direction * distance
	camera.look_at(focus_position, Vector3.UP)
