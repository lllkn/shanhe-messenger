extends Node3D
## 五站共用地图外壳。地点、出生点由 journeys.json 维护。
@export var station_id := "lijiang"
var spec: Dictionary
var map_root: Node3D
var player: CharacterBody3D
var camera: Camera3D
var adapter: CityAdapter
var spawn_position := Vector3.ZERO
var goal_position := Vector3.ZERO
var yaw := 0.0
var pitch := 0.80
var distance := 8.0
var dragging := false
var hint: Label
var ambient_details: Node3D

func _ready() -> void:
	if SceneRouter.current_key == "city":
		station_id = SceneRouter.params.get("station", station_id)
	if not GameState.is_unlocked(station_id):
		SceneRouter.goto_map.call_deferred()
		return
	spec = ContentDB.station(station_id).get("city", {})
	if spec.is_empty() or not _load_map():
		GameUI.notify("此站地图暂时无法载入。")
		SceneRouter.goto_map.call_deferred()
		return
	_build_collision()
	_build_environment()
	spawn_position = anchor_position(spec["spawn_anchor"])
	var spawn_offset: Array = spec.get("spawn_offset", [0, 0, 0])
	spawn_position += Vector3(spawn_offset[0], spawn_offset[1], spawn_offset[2])
	goal_position = anchor_position(spec["goal_anchor"])
	yaw = float(spec.get("yaw", 0.0))
	pitch = float(spec.get("pitch", pitch))
	distance = float(spec.get("distance", distance))
	_build_player()
	adapter = CityAdapter.new()
	adapter.station_id = station_id
	add_child(adapter)
	_build_hud()
	var context: Dictionary = SceneRouter.params.get("city_context", {})
	if context.get("station", "") == station_id and context.get("position") is Vector3:
		player.position = context["position"]
		yaw = float(context.get("yaw", yaw))
		pitch = float(context.get("pitch", pitch))
		distance = float(context.get("distance", distance))
	_update_camera()
	_build_map_dynamics.call_deferred()
	print("CITY_READY ", station_id, " spawn=", spawn_position)

func _load_map() -> bool:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file("res://assets/cities/%s/map.glb" % spec["asset"], state) != OK:
		return false
	map_root = doc.generate_scene(state)
	if map_root == null:
		return false
	map_root.name = "CityGeometry"
	add_child(map_root)
	var animation := map_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if animation != null and not OS.get_cmdline_user_args().has("--no-dynamics"):
		for clip_name in animation.get_animation_list():
			if clip_name == "RESET": continue
			# 导入的环境动作循环播放，不在第一个8秒周期后停住。
			animation.get_animation(clip_name).loop_mode = Animation.LOOP_LINEAR
			animation.play(clip_name)
			break
	return true

func _build_map_dynamics() -> void:
	if OS.get_cmdline_user_args().has("--no-dynamics") or ambient_details != null: return
	match str(spec["asset"]):
		"lijiang":
			ambient_details = preload("res://scenes/cities/ambient/LijiangAmbient.gd").new()
			ambient_details.bind_map(map_root)
		"dali":
			ambient_details = preload("res://scenes/cities/ambient/DaliAmbient.gd").new()
			ambient_details.bind_map(map_root)
		"puer":
			ambient_details = preload("res://scenes/cities/ambient/PuerAmbient.gd").new()
			var visuals: Array[Node3D] = []
			# 子类热点也在ready里创建；动态层延后一帧绑定现有演员视觉。
			for actor in find_children("CharacterVisual", "Node3D", true, false):
				if actor.get_parent() != player: visuals.append(actor)
			ambient_details.bind_map(map_root, visuals)
	if ambient_details != null:
		ambient_details.name = "AmbientDetails"
		add_child(ambient_details)

func anchor_position(anchor: String) -> Vector3:
	var node := map_root.find_child(anchor, true, false) as Node3D
	if node == null:
		push_error("地图缺少锚点：" + anchor)
		return Vector3.ZERO
	# 大理旧GLB的Empty保留Blender轴向；网格已转为Y向上。
	if spec["asset"] == "dali":
		return Vector3(node.position.x, -node.position.z, -node.position.y)
	return node.global_position

func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "MapCollision"
	add_child(body)
	if spec["asset"] == "puer":
		var data := ContentDB.read_json("res://assets/cities/puer/map_data.json")
		for item in data.get("collisions", []):
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			var size: Array = item["size"]
			box.size = Vector3(size[0], size[1], size[2])
			shape.shape = box
			var center: Array = item["center"]
			shape.position = Vector3(center[0], center[1], center[2])
			body.add_child(shape)
	else:
		var data: Resource = load("res://assets/cities/%s/collision.res" % spec["asset"])
		body.set_meta("shape_names", data.names)
		for i in data.shapes.size():
			var shape := CollisionShape3D.new()
			shape.shape = data.shapes[i]
			shape.transform = data.transforms[i]
			body.add_child(shape)

	if ResourceLoader.exists("res://assets/cities/%s/camera_collision.res" % spec["asset"]):
		var camera_body := StaticBody3D.new()
		camera_body.name = "CameraCollision"
		camera_body.collision_layer = 4
		camera_body.collision_mask = 0
		add_child(camera_body)
		var camera_data: Resource = load("res://assets/cities/%s/camera_collision.res" % spec["asset"])
		for i in camera_data.shapes.size():
			var shape := CollisionShape3D.new()
			shape.shape = camera_data.shapes[i]
			shape.transform = camera_data.transforms[i]
			camera_body.add_child(shape)

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.40, 0.58, 0.83)
	sky_mat.sky_horizon_color = Color(0.79, 0.86, 0.87)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.65, 0.75, 0.86)
	env.ambient_light_energy = 0.4
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 0.78
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.35
	sun.light_color = Color(1, 0.96, 0.87)
	if spec["asset"] == "lijiang":
		sun.light_color = Color(1, 0.79, 0.59)
	sun.rotation_degrees = Vector3(-52, -34, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 100
	add_child(sun)

func _build_player() -> void:
	player = load("res://scenes/cities/CityPlayer.gd").new()
	player.name = "Player"
	player.collision_layer = 2
	player.collision_mask = 1
	player.floor_snap_length = 0.4
	player.safe_margin = 0.02
	player.position = spawn_position + Vector3(0, 0.15, 0)
	var collider := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.7
	collider.shape = cap
	collider.position.y = 0.85
	player.add_child(collider)
	# 延用原普洱测试角色；正式女主模型后续替换。
	var visual := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.23
	mesh.height = 1.6
	visual.mesh = mesh
	visual.position.y = 0.85
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.24, 0.46, 0.47)
	visual.material_override = material
	player.add_child(visual)
	add_child(player)
	camera = Camera3D.new()
	camera.name = "FollowCamera"
	camera.far = 1200
	camera.fov = float(spec.get("fov", 62))
	camera.current = true
	add_child(camera)

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(margin)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(col)
	var header := PanelContainer.new()
	header.add_theme_stylebox_override("panel", UiKit.style(Color(0.04, 0.09, 0.08, 0.82), UiKit.GOLD, 10))
	col.add_child(header)
	var row := HBoxContainer.new()
	header.add_child(row)
	var title := UiKit.label(GameState.stations[GameState.station_index[station_id]]["name"] + " · " + spec["spawn_label"], 28, UiKit.PAPER)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	row.add_child(UiKit.button("行囊", func(): SceneRouter.goto_codex()))
	row.add_child(UiKit.button("返回长卷", func(): SceneRouter.goto_map()))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(spacer)
	var footer := PanelContainer.new()
	footer.add_theme_stylebox_override("panel", UiKit.style(Color(0.04, 0.09, 0.08, 0.82), UiKit.GOLD, 10))
	col.add_child(footer)
	var help := VBoxContainer.new()
	footer.add_child(help)
	hint = UiKit.label("", 24, UiKit.PAPER)
	help.add_child(hint)
	help.add_child(UiKit.label("WASD 移动 · Shift 跑 · 空格 跳 · 右键拖动视角 · 滚轮缩放 · E 交互 · Esc 暂停", 20, UiKit.PAPER))

func city_context() -> Dictionary:
	return {"station": station_id, "position": player.position, "yaw": yaw, "pitch": pitch, "distance": distance}

func can_interact() -> bool:
	return Vector2(player.position.x, player.position.z).distance_to(Vector2(goal_position.x, goal_position.z)) <= 3.0

func interact() -> void:
	if can_interact() and not SceneRouter.is_switching() and not JourneyFlow.next_step(station_id).is_empty():
		adapter.resume_story()

func _process(_delta: float) -> void:
	if player == null:
		return
	player.heading = yaw
	if player.position.y < -2.0 or absf(player.position.x) > 40 or absf(player.position.z) > 35:
		player.position = spawn_position + Vector3(0, 0.15, 0)
		player.velocity = Vector3.ZERO
	_update_camera()
	var target: String = ContentDB.station(station_id).get("location", "本站地点")
	if station_id == "gucheng":
		target = "织坊"
	var step := JourneyFlow.next_step(station_id)
	hint.text = ("E · 走进" + target if not step.is_empty() else "此处故事已完成") if can_interact() else "沿街寻找" + target

func _update_camera() -> void:
	var focus := player.global_position + Vector3(0, 1.0, 0)
	var offset := Basis(Vector3.UP, yaw) * Vector3(0, sin(pitch) * distance, cos(pitch) * distance)
	# 相机在建筑前收近，避免镜头穿过屋墙。
	var ray := PhysicsRayQueryParameters3D.create(focus, focus + offset, 5)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	camera.global_position = focus + offset if hit.is_empty() else hit.position + hit.normal * 0.25
	if camera.global_position.distance_to(focus) > 0.01:
		camera.look_at(focus, Vector3.UP)

func _unhandled_input(event: InputEvent) -> void:
	if player == null or SceneRouter.is_switching():
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			dragging = event.pressed
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(4, distance - 1)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(18, distance + 1)
	elif event is InputEventMouseMotion and dragging:
		yaw -= event.screen_relative.x * 0.003 * GameSettings.camera_sensitivity
		pitch = clampf(pitch + event.screen_relative.y * 0.003 * GameSettings.camera_sensitivity, 0.25, 1.15)
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_E:
		interact()
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_PAUSED:
		dragging = false
