extends "res://tests/test_dali_chain.gd"
## 手动优先：在墙边验证实际鼠标/滚轮、松手保持、复位和经过巷道不改角度。
func _ready() -> void:
	get_tree().current_scene = null
	original_save = GameState.save_path
	evidence = OS.get_environment("DALI_TEST_EVIDENCE")
	if not evidence.is_empty(): DirAccess.make_dir_recursive_absolute(evidence)
	GameState.save_path = "user://dali-manual-camera-test.cfg"
	GameState.reset_game()
	GameState.unlocked.assign(["lijiang","xianggelila","dali"])
	SceneRouter.goto_station("dali")
	var city := await city_ready()
	await finish_talk(city)
	city.set_process(false)
	city.player.set_physics_process(false)
	city._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)
	city.mouse_look = true
	city._sync_mouse_mode()
	check(city.hotspots.size()==4 and hotspot(city,"zhaobi").is_empty() and hotspot(city,"pagodas").is_empty(),"只保留四位主线人物")
	var intact := true
	for mesh: MeshInstance3D in city.map_root.find_children("*","MeshInstance3D",true,false):
		if not (str(mesh.name).begins_with("B_03_") or str(mesh.name).begins_with("B_07_")): continue
		if not mesh.visible or mesh.material_override != null: intact = false
		for surface in mesh.mesh.get_surface_count():
			if mesh.get_surface_override_material(surface) != null: intact = false
	check(intact,"建筑原网格、原材质完整，无裁切或隐藏")
	var fixture := blocked_orbit(city)
	check(not fixture.is_empty(),"找到实际镜头碰撞约束点")
	city.player.position = fixture.get("position",city.spawn_position)
	city.yaw = fixture.get("yaw",0.55)
	city.pitch = 0.7
	city.distance = 12.0
	city.camera_initialized = false
	city._update_camera()
	check(orbit_matches(city),"受遮挡时仍保持用户角度和距离")
	var before_yaw: float = city.yaw
	var before_pitch: float = city.pitch
	motion(Vector2(600,350),Vector2(40,-20))
	city._update_camera()
	check(is_equal_approx(city.yaw,before_yaw-0.12*GameSettings.camera_sensitivity) and is_equal_approx(city.pitch,before_pitch-0.06*GameSettings.camera_sensitivity) and orbit_matches(city),"墙边鼠标输入直接改变实际画面")
	wheel(MOUSE_BUTTON_WHEEL_UP)
	city._update_camera()
	check(is_equal_approx(city.distance,11.0) and orbit_matches(city),"墙边滚轮缩近直接生效")
	wheel(MOUSE_BUTTON_WHEEL_DOWN)
	city._update_camera()
	check(is_equal_approx(city.distance,12.0) and orbit_matches(city),"墙边滚轮拉远不被碰撞锁住")
	var saved := Vector3(city.yaw,city.pitch,city.distance)
	for frame in 240:
		city.follow_camera.update(city.camera,city.player,city.yaw,city.pitch,city.distance,1.0/60.0,false)
	check(saved==Vector3(city.yaw,city.pitch,city.distance) and orbit_matches(city),"松手4秒不自动回正、换角度或缩放")
	await shot("01-manual-at-wall")
	key(KEY_TAB,true);key(KEY_TAB,false)
	await get_tree().process_frame
	before_yaw = city.yaw
	motion(Vector2(600,350),Vector2(80,0))
	check(not city.mouse_look and is_equal_approx(city.yaw,before_yaw),"Tab光标模式不误转镜头")
	key(KEY_TAB,true);key(KEY_TAB,false)
	await get_tree().process_frame
	motion(Vector2(600,350),Vector2(80,0))
	city._update_camera()
	check(city.mouse_look and is_equal_approx(city.yaw,before_yaw-0.24*GameSettings.camera_sensitivity) and orbit_matches(city),"Tab返回后可继续自由转动")
	for i in 20: wheel(MOUSE_BUTTON_WHEEL_UP)
	city._update_camera()
	check(city.distance==7 and orbit_matches(city),"最近缩放由用户控制，限制7米")
	for i in 20: wheel(MOUSE_BUTTON_WHEEL_DOWN)
	city._update_camera()
	check(city.distance==16 and orbit_matches(city),"最远缩放由用户控制，限制16米")
	var context: Dictionary = city.city_context()
	check(context["yaw"]==city.yaw and context["pitch"]==city.pitch and context["distance"]==city.distance,"返回场景保存用户实际设置")
	key(KEY_R,true);key(KEY_R,false)
	await get_tree().process_frame
	city._update_camera()
	check(is_equal_approx(city.yaw,0.55) and is_equal_approx(city.pitch,0.7) and city.distance==12 and orbit_matches(city),"只有R恢复默认斜视角")
	route_survey(city)
	var route: PackedVector3Array = city.walk_guide.path(hotspot(city,"youngster")["position"],hotspot(city,"granny")["position"])
	city.player.position = route[maxi(0,route.size()-6)]
	city.yaw = 0.0
	city.pitch = 0.7
	city.distance = 12.0
	city.camera_initialized = false
	city._update_camera()
	await shot("02-alley-fixed")
	motion(Vector2(600,350),Vector2(-PI/(0.003*GameSettings.camera_sensitivity),0))
	city._update_camera()
	check(orbit_matches(city),"经过巷道后仍可手动转到反方向")
	await shot("03-alley-manually-turned")
	city.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_restore_save()
	GameMusic.stop()
	await get_tree().create_timer(0.2).timeout
	print("DALI_MANUAL_CAMERA checks=",checks," failures=",failures," renderer=",DisplayServer.get_name())
	get_tree().quit(failures)

func wheel(button: int) -> void:
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.pressed = pressed
		event.position = Vector2(600,350)
		get_viewport().push_input(event,true)

func orbit_matches(city: Node3D) -> bool:
	var expected := Basis(Vector3.UP,city.yaw)*Vector3(0,sin(city.pitch),cos(city.pitch))
	return city.camera.global_basis.z.angle_to(expected)<0.001 and absf(city.camera.position.distance_to(city.follow_camera.focus_position)-city.distance)<0.001

func route_survey(city: Node3D) -> void:
	var points := PackedVector3Array()
	var start: Vector3 = city.spawn_position
	for item in city.hotspots:
		var path: PackedVector3Array = city.walk_guide.path(start,item["position"])
		check(not path.is_empty(),"访谈路线可达 "+item["id"])
		points.append_array(path)
		start = item["position"]
	var samples := 0
	var changed := 0
	for yaw_index in 8:
		city.yaw = yaw_index*TAU/8.0
		city.pitch = 0.7
		city.distance = 12.0
		city.camera_initialized = false
		for point in points:
			city.player.position = point
			city._update_camera()
			if not orbit_matches(city): changed+=1
			samples+=1
	print("MANUAL_ROUTE samples=",samples," unexpected_camera_changes=",changed)
	check(samples>1000 and changed==0,"连续经过实际巷道不自动改变视角和距离")

func blocked_orbit(city: Node3D) -> Dictionary:
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.28
	query.shape = sphere
	query.collision_mask = 4
	for point in [Vector3(12.4,0.035,-7.2),city.spawn_position]:
		for yaw in [0.55,0.0,1.57,3.14,4.71]:
			query.transform = Transform3D(Basis.IDENTITY,point+Vector3(0,0.8,0))
			query.motion = Basis(Vector3.UP,yaw)*Vector3(0,sin(0.7),cos(0.7))*12.0
			var hit: PackedFloat32Array = city.get_world_3d().direct_space_state.cast_motion(query)
			if not hit.is_empty() and hit[0]<0.9: return {"position":point,"yaw":yaw}
	return {}
