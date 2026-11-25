extends Node
## 对真实道路和GLB建筑采样；独立层8用来验证视线，不依赖烘焙结果。
var failures := 0
var output := OS.get_environment("CAMERA_TEST_OUTPUT")

func update_camera(city: Node3D, baseline: bool) -> void:
	if not baseline:
		city._update_camera()
		return
	var focus: Vector3 = city.player.position + Vector3(0,0.8,0)
	var offset: Vector3 = Basis(Vector3.UP,city.yaw)*Vector3(0,sin(city.pitch)*city.distance,cos(city.pitch)*city.distance)
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.28
	query.shape = sphere
	query.collision_mask = 4
	query.transform = Transform3D(Basis.IDENTITY,focus)
	query.motion = offset
	var fractions := city.get_world_3d().direct_space_state.cast_motion(query)
	var fraction: float = 1.0 if fractions.is_empty() else maxf(0.04,fractions[0]-0.02)
	city.camera.position = focus + offset*fraction
	city.camera.look_at(focus)

func _ready() -> void:
	get_tree().current_scene = null
	var baseline := OS.get_cmdline_user_args().has("--baseline")
	for id in ["lijiang","xianggelila","dali","puer"]:
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file("res://assets/cities/%s/map.glb" % id,state) != OK:
			failures += 1
			continue
		var map := doc.generate_scene(state)
		var map_spec: Dictionary = ContentDB.station(id)["city"]
		var valid: bool = map != null and map.find_child(map_spec["spawn_anchor"],true,false) != null and map.find_child(map_spec["goal_anchor"],true,false) != null
		print("MAP_IMPORT ",id," anchors=",valid," meshes=",state.get_meshes().size())
		if not valid: failures += 1
		if map != null: map.free()
	GameState.save_path = "user://puer-camera-test.cfg"
	GameState.reset_game()
	GameState.unlocked.assign(["lijiang", "xianggelila", "dali", "puer"])
	GameState.set_flag("flow/puer/arrival")
	SceneRouter.goto_station("puer")
	await get_tree().process_frame
	while SceneRouter.is_switching(): await get_tree().process_frame
	var city := get_tree().current_scene
	while not city.walk_guide.ready: await get_tree().physics_frame
	city.set_process(false)
	city.player.set_physics_process(false)
	if city.dialogue != null: city.close_conversation(city.dialogue.get_parent())
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if baseline:
		var original: Resource = load("res://tests/fixtures/puer-camera-before.res")
		if original == null:
			get_tree().quit(1)
			return
		city.get_node("CameraCollision").free()
		var old_body := StaticBody3D.new()
		old_body.collision_layer = 4
		old_body.collision_mask = 0
		city.add_child(old_body)
		for i in original.shapes.size():
			var shape := CollisionShape3D.new()
			shape.shape = original.shapes[i]
			shape.transform = original.transforms[i]
			old_body.add_child(shape)
	var reference := StaticBody3D.new()
	reference.collision_layer = 8
	reference.collision_mask = 0
	city.add_child(reference)
	for mesh in city.map_root.find_children("*", "MeshInstance3D", true, false):
		var n := str(mesh.name)
		if not (n.begins_with("B_03_") or n.begins_with("B_08_") or (n.begins_with("B_04_") and not n.contains("leaf") and not n.contains("tea") and not n.contains("cloth"))): continue
		var collider := CollisionShape3D.new()
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(mesh.mesh.get_faces())
		collider.shape = shape
		reference.add_child(collider)
		collider.global_transform = mesh.global_transform
	await get_tree().physics_frame
	var samples := 0
	var blocked := 0
	var head_blocked := 0
	var shortened := 0
	var too_close := 0
	var near_overlap := 0
	var minimum_length := INF
	var worst := {}
	var points: Array[Vector3] = []
	for road in city.story["roads"].values():
		for i in range(road.size()-1):
			var a := Vector3(road[i][0],road[i][1],road[i][2])
			var b := Vector3(road[i+1][0],road[i+1][1],road[i+1][2])
			for step in 4: points.append(a.lerp(b, float(step)/4.0))
	for point in points:
		var ground_query := PhysicsRayQueryParameters3D.create(point+Vector3(0,3,0),point-Vector3(0,2,0),1)
		ground_query.exclude = [city.player.get_rid()]
		var ground: Dictionary = city.get_world_3d().direct_space_state.intersect_ray(ground_query)
		if ground.is_empty(): continue
		city.player.position = ground.position + Vector3(0,0.03,0)
		for angle in 12:
			for setting in [[0.38,7.0],[0.7,7.0],[0.95,7.0],[0.38,12.0],[0.7,12.0],[0.95,12.0],[0.38,16.0],[0.7,16.0],[0.95,16.0]]:
				city.yaw = float(angle)*TAU/12.0
				city.pitch = setting[0]
				city.distance = setting[1]
				city.camera_initialized = false
				update_camera(city,baseline)
				samples += 1
				var actual_length: float = city.camera.position.distance_to(city.player.position+Vector3(0,0.8,0))
				minimum_length = minf(minimum_length,actual_length)
				if actual_length < float(setting[1])-0.1: shortened += 1
				if actual_length < 1.5:
					if too_close < 3: print("CLOSE_CASE ",city.player.position," yaw=",city.yaw," pitch=",city.pitch," length=",actual_length)
					too_close += 1
				var overlap := PhysicsShapeQueryParameters3D.new()
				var near_sphere := SphereShape3D.new()
				near_sphere.radius = 0.18
				overlap.shape = near_sphere
				overlap.collision_mask = 8
				overlap.transform = Transform3D(Basis.IDENTITY,city.camera.position)
				if not city.get_world_3d().direct_space_state.intersect_shape(overlap).is_empty(): near_overlap += 1
				var covered := false
				for height in [0.25,0.8,1.5]:
					var start: Vector3 = city.player.position + Vector3(0,height,0)
					var ray := PhysicsRayQueryParameters3D.create(start,city.camera.position,8)
					var hit: Dictionary = city.get_world_3d().direct_space_state.intersect_ray(ray)
					if not hit.is_empty():
						covered = true
						if height == 1.5: head_blocked += 1
						if worst.is_empty(): worst = {"position": city.player.position, "yaw": city.yaw, "pitch": city.pitch}
				if covered: blocked += 1
	print("PUER_CAMERA_SURVEY samples=", samples, " blocked=", blocked, " head_blocked=",head_blocked," shortened=",shortened," too_close=",too_close," near_overlap=",near_overlap," minimum_length=",minimum_length," baseline=",baseline," first_case=",worst)
	if not baseline and blocked > 0: failures += 1
	if not baseline and (too_close > 0 or near_overlap > 0): failures += 1
	if not baseline:
		var moving_blocked := 0
		var moving_overlap := 0
		city.camera_initialized = false
		for index in points.size():
			var point := points[index]
			var ground: Dictionary = city.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3(0,3,0),point-Vector3(0,2,0),1))
			if ground.is_empty(): continue
			city.player.position = ground.position+Vector3(0,0.03,0)
			city.yaw = float(index)*0.17
			city.pitch = 0.7
			city.distance = 16.0 if index%2 == 0 else 7.0
			for frame in 3:
				city._update_camera()
				for height in [0.25,0.8,1.5]:
					var start: Vector3 = city.player.position+Vector3(0,height,0)
					if not city.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(start,city.camera.position,8)).is_empty(): moving_blocked += 1
				var query := PhysicsShapeQueryParameters3D.new()
				var shape := SphereShape3D.new()
				shape.radius = 0.18
				query.shape = shape
				query.collision_mask = 8
				query.transform = Transform3D(Basis.IDENTITY,city.camera.position)
				if not city.get_world_3d().direct_space_state.intersect_shape(query).is_empty(): moving_overlap += 1
				await get_tree().process_frame
		print("PUER_CAMERA_MOTION blocked=",moving_blocked," overlap=",moving_overlap)
		if moving_blocked > 0 or moving_overlap > 0: failures += 1
	# 固定回归镜头（两版使用同一坐标、角度和距离）。
	city.player.position = Vector3(14.6,0.07,-4.8)
	city.yaw = 0.0
	city.pitch = 0.95
	city.distance = 12.0
	city.camera_initialized = false
	update_camera(city,baseline)
	if not output.is_empty() and DisplayServer.get_name() != "headless":
		for i in 8: await get_tree().process_frame
		RenderingServer.force_draw()
		get_viewport().get_texture().get_image().save_png(output.path_join("before.png" if baseline else "after.png"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.save_path))
	get_tree().quit(failures)
