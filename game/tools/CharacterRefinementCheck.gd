extends Node
## Actual four-city model, movement and conversation checks; isolated save file.
var checks := 0
var failures := 0
var output := OS.get_environment("CHARACTER_REFINEMENT_OUTPUT")
var shots := false
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", message)
func settle() -> void:
	await get_tree().process_frame
	while SceneRouter.is_switching(): await get_tree().process_frame
	var city := get_tree().current_scene
	while not city.walk_guide.ready: await get_tree().physics_frame
func bounds(root: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for obj in root.find_children("*", "MeshInstance3D", true, false):
		for surface in obj.mesh.get_surface_count():
			var vertices: PackedVector3Array = obj.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				var point: Vector3 = obj.global_transform * vertex
				result = AABB(point, Vector3.ZERO) if first else result.expand(point)
				first = false
	return result
func key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
func shot(file: String) -> void:
	if not shots: return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join(file + ".png"))
func _ready() -> void:
	get_tree().current_scene = null
	shots = OS.get_cmdline_user_args().has("--screenshots")
	if output.is_empty(): output = "res://../drafts/character-refinement-20261014/screenshots/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	GameState.save_path = "user://refined-character-check.cfg"
	GameState.reset_game()
	GameState.unlocked.assign(["lijiang", "xianggelila", "dali", "puer"])
	for id in ["lijiang", "xianggelila", "dali", "puer"]:
		SceneRouter.goto_station(id)
		await settle()
		var city := get_tree().current_scene
		var guard := 0
		while city.dialogue != null and guard < 100:
			city.dialogue._continue()
			guard += 1
		check(city.dialogue == null, id + " arrival completed")
		await get_tree().process_frame
		var actors: Array[Node3D] = [city.player]
		var ids: Array[String] = ["protagonist"]
		var heights: Array[float] = [1.65]
		for item in city.hotspots:
			if item.get("observation", false): continue
			actors.append(item["actor"])
			ids.append(item["id"])
			heights.append(1.75 if id == "lijiang" and item["id"] == "dongba" else item.get("height", 1.65))
		for i in actors.size():
			var model: Node3D = actors[i].get_node_or_null("CharacterVisual")
			check(model != null, id + "/" + ids[i] + " v02 model loaded")
			if model == null: continue
			var box := bounds(model)
			check(absf(box.size.y-heights[i]) < .026, id+"/"+ids[i]+" height matches " + str(heights[i]))
			var expected_foot: float = actors[i].global_position.y
			if id == "xianggelila" and i > 0:
				var at: Vector3 = actors[i].global_position
				var ray := PhysicsRayQueryParameters3D.create(at+Vector3(0,.3,0),at-Vector3(0,1.2,0),1)
				ray.exclude = [city.player.get_rid(), actors[i].get_node("NpcCollision").get_rid()]
				var hit: Dictionary = city.get_world_3d().direct_space_state.intersect_ray(ray)
				if not hit.is_empty(): expected_foot = hit.position.y
			check(absf(box.position.y-expected_foot) < .04, id+"/"+ids[i]+" feet on ground")
			check(box.size.x < 1.1 and box.size.z < 1.1, id+"/"+ids[i]+" no stray geometry")
			for limb in ["Leg_L", "Leg_R", "Arm_L", "Arm_R"]:
				check(model.find_child("*" + limb + "*", true, false) != null,id+"/"+ids[i]+" "+limb+" preserved")
			check(model.visible, id+"/"+ids[i]+" visible after arrival")
			print("REFINED_BOUNDS ", id, "/", ids[i], " ", box)
		# Move using actual keyboard input and confirm animated limbs are still connected.
		var start: Vector3 = city.player.position
		key(KEY_W, true)
		var visual: Node3D = city.player.get_node("CharacterVisual")
		var peak_sway := 0.0
		for i in 12:
			await get_tree().physics_frame
			await get_tree().process_frame
			peak_sway = maxf(peak_sway, absf(visual.left_leg.rotation.x))
		check(peak_sway > .005, id + " walking animates leg pivot")
		key(KEY_W, false)
		for i in 4: await get_tree().physics_frame
		check(city.player.position.distance_to(start) > .12, id + " real WASD movement")
		city.yaw = 0.0
		city.pitch = .38
		city.distance = 6.0
		city.camera_initialized = false
		await shot(id+"-map")
		# Photograph one actual actor pair near the first interview point.
		var item: Dictionary = city.hotspots[1] if id == "dali" else city.hotspots[0]
		city.player.position = item["position"] + Vector3(.75,.15,1.15)
		city.player.velocity = Vector3.ZERO
		city.player.get_node("CharacterVisual").rotation.y = 0
		city.distance = 4.0
		city.yaw = .22
		city.camera_initialized = false
		for i in 20: await get_tree().physics_frame
		await shot(id+"-close")
		city.open_conversation(item["dialogue"], "refinement-check")
		await get_tree().process_frame
		check(city.dialogue != null, id + " interview opens")
		check(not visual.visible and not item["actor"].visible, id + " models hidden during dialogue")
		city.dialogue._leave()
		await get_tree().process_frame
		check(visual.visible and item["actor"].visible, id + " models restored after dialogue")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.save_path))
	print("CHARACTER_REFINEMENT_CHECK checks=", checks, " failures=", failures)
	get_tree().quit(failures)
