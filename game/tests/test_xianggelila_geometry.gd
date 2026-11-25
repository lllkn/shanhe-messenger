extends Node
var failures := 0
var checks := 0
var original_save := ""
func check(ok: bool, message: String) -> void:
	checks += 1
	print("PASS: " if ok else "FAIL: ", message)
	if not ok: failures += 1
func settle() -> void:
	await get_tree().process_frame
	while SceneRouter.is_switching(): await get_tree().process_frame
	await get_tree().process_frame
func physics(frames: int = 4) -> void:
	for i in frames: await get_tree().physics_frame
func key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
func mouse_motion(relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.relative = relative
	event.screen_relative = relative
	get_viewport().push_input(event, true)
func mouse_captured(city: Node3D) -> bool:
	# Dummy DisplayServer没有原生鼠标捕获，窗口版本另验证实际模式。
	return city.mouse_look and city.window_focused and (DisplayServer.get_name() == "headless" or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)
func city_ready() -> Node3D:
	await settle()
	var city := get_tree().current_scene
	while not city.walk_guide.ready: await get_tree().physics_frame
	await get_tree().process_frame
	return city
func finish_talk(city: Node3D) -> void:
	var guard := 0
	while city.dialogue != null and guard < 200:
		city.dialogue._continue()
		guard += 1
	await get_tree().process_frame
func teleport(city: Node3D, pos: Vector3) -> void:
	city.player.position = pos + Vector3(0, 0.1, 0)
	city.player.velocity = Vector3.ZERO
	await physics(8)
func walk(city: Node3D, target: Vector3, message: String) -> void:
	var route: PackedVector3Array = city.walk_guide.path(city.player.position, target)
	check(not route.is_empty(), message + " 有物理可达引导路径")
	var stuck := false
	var start_time := Time.get_ticks_msec()
	key(KEY_W, true)
	for point in route:
		var frames := 0
		while Vector2(city.player.position.x - point.x, city.player.position.z - point.z).length() > 0.22 and frames < 100:
			var direction: Vector3 = point - city.player.position
			city.yaw = atan2(-direction.x, -direction.z)
			await get_tree().physics_frame
			frames += 1
		if frames >= 100:
			printerr("STUCK ", message, " at ", city.player.position, " wanted ", point)
			stuck = true
			break
	key(KEY_W, false)
	await physics(3)
	check(not stuck and city.player.position.distance_to(target) < 1.5, message + " 真实WASD连续步行抵达")
	print("WALK elapsed_ms=", Time.get_ticks_msec() - start_time, " points=", route.size())
func point_for(city: Node3D, id: String) -> Dictionary:
	for item in city.hotspots:
		if item["id"] == id: return item
	return {}

func pointer(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = position
	get_viewport().push_input(event,true)

func motion_to(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	get_viewport().push_input(event,true)

func fill_point(puzzle: Control, id: String) -> Vector2:
	var poly: Polygon2D = puzzle._region_nodes[id]
	var min_x := INF
	var min_y := INF
	var max_x := -INF
	var max_y := -INF
	for p in poly.polygon:
		min_x = minf(min_x,p.x)
		min_y = minf(min_y,p.y)
		max_x = maxf(max_x,p.x)
		max_y = maxf(max_y,p.y)
	for y in range(int(min_y),int(max_y)+1,2):
		for x in range(int(min_x),int(max_x)+1,2):
			var pos := Vector2(x+0.5,y+0.5)
			if puzzle._hit_region(pos) == id: return pos
	return Vector2(-1,-1)

func _ready() -> void:
	get_tree().current_scene = null
	original_save=GameState.save_path
	GameState.save_path="user://xgeometry.cfg"
	GameState.reset_game()
	GameState.collect_fragment("frag_dongba_tea")
	GameState.collect_fragment("frag_dye_five")
	SceneRouter.goto_station("xianggelila")
	var city := await city_ready()
	# 两座真实模型桥都用连续步行跨越，台阶/桥头/水域分别验证。
	for bridge in city.story["bridges"]:
		var middle: Vector3 = city.bridge_center(bridge)
		var v: Array = bridge["across"]
		var across := Vector3(v[0],v[1],v[2]).normalized()
		await teleport(city,middle-across*2.5)
		var route: PackedVector3Array = city.walk_guide.path(city.player.position,middle+across*2.5)
		var crosses := false
		for point in route:
			if Vector2(point.x-middle.x,point.z-middle.z).length()<1.2: crosses = true
		check(crosses,"路线实际经过本桥 "+bridge["id"])
		await walk(city,middle+across*2.5,"跨桥 "+bridge["id"])
	var river_mid := Vector3(-30.5,-0.4,2)
	await teleport(city,river_mid+Vector3(2.1,0,0))
	city.yaw=PI*0.5
	key(KEY_W,true)
	key(KEY_SPACE,true)
	await physics(85)
	key(KEY_W,false)
	key(KEY_SPACE,false)
	await get_tree().process_frame
	check(city.player.position.x > river_mid.x+0.7,"非桥溪水持续前行与跳跃不能横穿")
	await teleport(city,Vector3(-15.5,0,-12.6))
	var wall_ray := PhysicsRayQueryParameters3D.create(Vector3(-15.5,1,-12.6),Vector3(-11,1,-12.6),1)
	var wall_hit := city.get_world_3d().direct_space_state.intersect_ray(wall_ray)
	city.yaw=-PI*0.5
	key(KEY_W,true)
	await physics(42)
	key(KEY_W,false)
	print("WALL_STOP position=",city.player.position)
	var body_point: Vector3 = city.player.position+Vector3.UP
	check(not wall_hit.is_empty() and (body_point-wall_hit.position).dot(wall_hit.normal)>0.25,"布料店墙体不能穿透")
	await teleport(city,Vector3(-13,0,-11.7))
	check(city.near_hotspot().get("id","") != "cloth","近距离隔店墙不能交谈")
	await get_tree().process_frame
	check(not city.interaction_prompt.visible,"隔墙不显示E提示")
	for angle in [0.0,1.3,3.14,-1.2]:
		city.yaw=angle
		city.camera_initialized=false
		city._update_camera()
		var query := PhysicsShapeQueryParameters3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius=0.18
		query.shape=sphere
		query.collision_mask=4
		query.transform=Transform3D(Basis.IDENTITY,city.camera.position)
		var camera_hits := city.get_world_3d().direct_space_state.intersect_shape(query)
		if not camera_hits.is_empty(): print("CAMERA_OVERLAP ",angle," at=",city.camera.position," player=",city.player.position," hits=",camera_hits)
		check(camera_hits.is_empty(),"镜头球形避墙 "+str(angle))
	GameState.save_path=original_save
	GameState.load_game()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://xgeometry.cfg"))
	print("XIANGGELILA_GEOMETRY_TEST checks=",checks," failures=",failures)
	get_tree().quit(failures)
