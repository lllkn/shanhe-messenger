extends Node3D
## 录景专用入口：只读取地图和环境，不进入剧情、不写玩家存档。
const IDS := ["lijiang", "xianggelila", "dali", "puer", "gucheng"]
const NAMES := ["丽江", "香格里拉", "大理", "普洱", "古城"]
var city: Node3D
var camera: Camera3D
var help: CanvasLayer
var index := 0
var speed := 5.0
var looking := false


func _ready() -> void:
	GameUI.set_process_input(false)
	GameUI.hide()
	help = CanvasLayer.new()
	add_child(help)
	var label := Label.new()
	label.position = Vector2(22, 18)
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.text = "1 丽江 / 2 香格里拉 / 3 大理 / 4 普洱 / 5 古城\n右键按住转向 · WASD 移动 · Q/E 升降 · Shift 加速 · 滚轮调速\nH 隐藏说明 · R 回到起点 · F11 全屏 · Esc 释放鼠标"
	help.add_child(label)
	var requested := OS.get_environment("CITY_PREVIEW")
	if requested in IDS: index = IDS.find(requested)
	_load_city(index)

func _load_city(next: int) -> void:
	_release_mouse()
	if is_instance_valid(city):
		remove_child(city)
		city.queue_free()
	index = next
	city = preload("res://tools/SceneryMap.gd").new()
	city.station_id = IDS[index]
	add_child(city)
	camera = Camera3D.new()
	camera.far = 1200
	camera.fov = 50
	city.add_child(camera)
	camera.make_current()
	_reset_camera()
	DisplayServer.window_set_title("山河信使 · %s景色预览" % NAMES[index])
	GameMusic.play("lijiang" if index == 4 else IDS[index])
	print("SCENERY_READY ", IDS[index])

func _reset_camera() -> void:
	var focus: Vector3 = city.anchor_position(city.spec["spawn_anchor"]) + Vector3(0, 1.5, 0)
	var offset: Array = city.spec.get("spawn_offset", [0, 0, 0])
	focus += Vector3(offset[0], offset[1], offset[2])
	var yaw := float(city.spec.get("yaw", 0.0))
	var pitch := float(city.spec.get("pitch", 0.7))
	camera.global_position = focus + Basis(Vector3.UP, yaw) * Vector3(0, sin(pitch) * 12, cos(pitch) * 12)
	camera.look_at(focus)

func _process(delta: float) -> void:
	if not is_instance_valid(camera) or not DisplayServer.window_is_focused(): return
	var direction := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W): direction -= camera.global_basis.z
	if Input.is_physical_key_pressed(KEY_S): direction += camera.global_basis.z
	if Input.is_physical_key_pressed(KEY_A): direction -= camera.global_basis.x
	if Input.is_physical_key_pressed(KEY_D): direction += camera.global_basis.x
	if Input.is_physical_key_pressed(KEY_Q): direction += Vector3.UP
	if Input.is_physical_key_pressed(KEY_E): direction -= Vector3.UP
	if not direction.is_zero_approx():
		camera.global_position += direction.normalized() * speed * (3.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0) * delta

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.physical_keycode
		if key >= KEY_1 and key <= KEY_5: _load_city(key - KEY_1)
		elif key == KEY_H: help.visible = not help.visible
		elif key == KEY_R: _reset_camera()
		elif key == KEY_ESCAPE: _release_mouse()
		elif key == KEY_F11:
			var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			looking = event.pressed
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if looking else Input.MOUSE_MODE_VISIBLE
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP: speed = minf(speed * 1.25, 30)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN: speed = maxf(speed / 1.25, 0.5)
	elif event is InputEventMouseMotion and looking:
		camera.rotation.y -= event.screen_relative.x * 0.003 * GameSettings.camera_sensitivity
		camera.rotation.x = clampf(camera.rotation.x - event.screen_relative.y * 0.003 * GameSettings.camera_sensitivity, -1.5, 1.5)

func _release_mouse() -> void:
	looking = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT: _release_mouse()
