extends "res://scenes/cities/CityScene.gd"
## 共用城市叙事、引导和操作；点位、文案、步骤和前置条件来自各城配置。
@export var story_path := ""
var story: Dictionary
var hotspots: Array[Dictionary] = []
var target_id := ""
var walk_guide := CityWalkGuide.new()
var guide_path := PackedVector3Array()
var guide_mesh: MeshInstance3D
var minimap: Control
var hud: CanvasLayer
var objective: Label
var checklist: VBoxContainer
var dialogue: Control
var route_guide := CityRouteGuide.new()
var last_safe := Vector3.ZERO
var camera_initialized := false
var reward_panel: Control
var mouse_look := true
var window_focused := true
var control_help: Label
var interaction_prompt: PanelContainer
var interaction_text: Label
var arrival_screen := CityArrivalScreen.new()

func _ready() -> void:
	story = ContentDB.read_json(story_path)
	target_id = story["interviews"][0]["id"]
	add_child(arrival_screen)
	arrival_screen.prepare(self)
	super._ready()
	if player == null: return
	_configure_geometry()
	get_viewport().msaa_3d = Viewport.MSAA_2X
	_build_water_barriers()
	_build_hotspots()
	_build_route_mesh()
	last_safe = player.position
	if arrival_screen.active:
		open_conversation(story["arrival"], "arrival")
	await get_tree().physics_frame
	await get_tree().physics_frame
	walk_guide.build(self, story["bounds"])
	minimap.prepare_floor()
	_refresh_progress()
	while SceneRouter.is_switching(): await get_tree().process_frame
	if done(story["puzzle_step"]) and not done("farewell") and not GameState.is_completed(station_id):
		open_conversation(story["farewell"], "farewell")
	elif done("farewell") and not GameState.is_completed(station_id):
		_collect_reward()

func _collect_reward() -> void:
	if done("farewell") and done(story["puzzle_step"]) and clue_count() == interview_total() and done(story["visit_step"]) and not GameState.has_fragment(story["fragment"]):
		GameState.collect_fragment(story["fragment"])
		_refresh_progress()
		_show_reward()

func _configure_geometry() -> void:
	var offset: Array = story["core"].get("offset", [0, 0, 0])
	goal_position += Vector3(offset[0], offset[1], offset[2])
	for pattern in story.get("hide_meshes", []):
		for mesh in map_root.find_children(pattern, "MeshInstance3D", true, false): mesh.visible = false

func core_id() -> String:
	return story["core"]["id"]

func clue_key(id: String) -> String:
	return "clue/" + station_id + "/" + id

func interview_total() -> int:
	return story["interviews"].size()

func done(step: String) -> bool:
	return GameState.has_flag("flow/" + station_id + "/" + step)

func clue_count() -> int:
	var count := 0
	for item in story["interviews"]:
		if GameState.has_flag(clue_key(item["id"])): count += 1
	return count

func bridge_center(bridge: Dictionary) -> Vector3:
	if bridge.has("position"):
		var p: Array = bridge["position"]
		return Vector3(p[0], p[1], p[2])
	var a: Array = story["canal"][bridge["segment"]]
	var b: Array = story["canal"][bridge["segment"] + 1]
	return Vector3(a[0], 0, a[1]).lerp(Vector3(b[0], 0, b[1]), bridge["fraction"])

func _box(body: StaticBody3D, center: Vector3, box_size: Vector3, rotation_y: float = 0.0) -> void:
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box_size
	collider.shape = shape
	collider.position = center
	collider.rotation.y = rotation_y
	body.add_child(collider)

func _build_water_barriers() -> void:
	var body := StaticBody3D.new()
	body.name = "RiverSafety"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var river: Array = story.get("canal", [])
	for i in river.size() - 1:
		var a := Vector3(river[i][0], 0, river[i][1])
		var b := Vector3(river[i+1][0], 0, river[i+1][1])
		var length := a.distance_to(b)
		var direction := (b - a).normalized()
		if story.get("precise_water_bridges", false):
			# 逐格裁出真实桥面的矩形通道，不能把浅角桥的整段河道挖开。
			var across := direction.cross(Vector3.UP)
			var width: float=story.get("water_width",1.9)
			var along_cells:=ceili(length/0.32)
			var cross_cells:=ceili(width/0.32)
			for row in along_cells:
				for col in cross_cells:
					var center:=a+direction*((row+0.5)*length/along_cells)+across*((col+0.5)*width/cross_cells-width*0.5)
					var on_bridge:=false
					for bridge in story.get("bridges",[]):
						if not bridge.get("water",false):continue
						var axis_data: Array=bridge["across"]
						var axis:=Vector3(axis_data[0],0,axis_data[2])
						var local:=center-bridge_center(bridge)
						if absf(local.dot(axis))<2.85 and absf(local.dot(axis.cross(Vector3.UP)))<1.20:on_bridge=true
					if not on_bridge:_box(body,center+Vector3(0,1.05,0),Vector3(width/cross_cells+0.012,2.3,length/along_cells+0.012),atan2(direction.x,direction.z))
			continue
		var cuts: Array[Vector2] = []
		for bridge in story.get("bridges", []):
			if not bridge.get("water", true): continue
			if bridge.has("segment"):
				if bridge["segment"] == i:
					var middle: float = length * float(bridge["fraction"])
					cuts.append(Vector2(middle - 1.4, middle + 1.4))
			else:
				var p := bridge_center(bridge)
				var along := (p-a).dot(direction)
				var nearest := a + direction * clampf(along, 0, length)
				if p.distance_to(nearest) < 2.8:
					var axis_data: Array = bridge["across"]
					var axis := Vector3(axis_data[0], 0, axis_data[2])
					var sine := absf(axis.cross(direction).y)
					var half_gap := minf(4.6, 1.45 / maxf(0.35, sine))
					cuts.append(Vector2(along-half_gap, along+half_gap))
		cuts.sort_custom(func(x: Vector2, y: Vector2): return x.x < y.x)
		var cursor := 0.0
		var sections: Array[Vector2] = []
		for cut in cuts:
			if cut.x > cursor: sections.append(Vector2(cursor, minf(length, cut.x)))
			cursor = maxf(cursor, cut.y)
		if cursor < length: sections.append(Vector2(maxf(0, cursor), length))
		for section in sections:
			if section.y <= section.x: continue
			var center := a + direction * ((section.x + section.y) * 0.5)
			_box(body, center + Vector3(0, 1.05, 0), Vector3(float(story.get("water_width", 1.9)), 2.3, section.y-section.x+0.015), atan2(direction.x,direction.z))
	var edge := StaticBody3D.new()
	edge.name = "TownBoundary"
	add_child(edge)
	for item in story.get("boundary_boxes", []):
		var center: Array = item["center"]
		var box_size: Array = item["size"]
		_box(edge, Vector3(center[0],center[1],center[2]), Vector3(box_size[0],box_size[1],box_size[2]))

func _build_hotspots() -> void:
	for item in story["interviews"] + story.get("observations", []):
		var point: Dictionary = item.duplicate(true)
		point["position"] = anchor_position(point["anchor"])
		var offset: Array = point.get("offset", [0,0,0])
		point["position"] += Vector3(offset[0],offset[1],offset[2])
		hotspots.append(point)
	var core: Dictionary = story["core"].duplicate(true)
	core["position"] = goal_position
	hotspots.append(core)
	for item in hotspots:
		var actor := Node3D.new()
		actor.name = "Actor_" + item["id"]
		actor.position = item["position"]
		add_child(actor)
		var height: float = item.get("height", 1.65)
		if not item.get("observation", false):
			var visual := MeshInstance3D.new()
			var cap := CapsuleMesh.new()
			cap.radius = 0.23
			cap.height = height
			visual.mesh = cap
			visual.position.y = height * 0.5
			var material := StandardMaterial3D.new()
			material.albedo_color = Color(item.get("color", "bcab83"))
			visual.material_override = material
			actor.add_child(visual)
		var label := Label3D.new()
		label.text = item["name"]
		label.position.y = height + 0.65
		label.font_size = 46
		label.pixel_size = 0.009
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = false
		label.outline_size = 12
		label.modulate = UiKit.PAPER
		actor.add_child(label)
		item["label"] = label
		item["actor"] = actor
		var body := StaticBody3D.new()
		body.name = "NpcCollision"
		actor.add_child(body)
		if not item.get("observation", false):
			_box(body, Vector3(0,height*0.5,0), Vector3(0.42,height,0.42))

func _build_hud() -> void:
	hud = CanvasLayer.new()
	hud.name = "CityHUD"
	add_child(hud)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(root)
	var title := UiKit.label(story["title"], 26, UiKit.PAPER)
	title.position = Vector2(24, 20)
	title.size = Vector2(440, 44)
	title.add_theme_color_override("font_outline_color", UiKit.DEEP)
	title.add_theme_constant_override("outline_size", 8)
	root.add_child(title)
	var nav := HBoxContainer.new()
	nav.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	nav.position = Vector2(-278, 16)
	root.add_child(nav)
	var bag := UiKit.button("行囊", func(): SceneRouter.goto_codex())
	bag.add_theme_font_size_override("font_size", 20)
	bag.custom_minimum_size = Vector2(94, 44)
	nav.add_child(bag)
	var back := UiKit.button("返回长卷", func(): SceneRouter.goto_map())
	back.add_theme_font_size_override("font_size", 20)
	back.custom_minimum_size = Vector2(140, 44)
	nav.add_child(back)
	var task := PanelContainer.new()
	task.position = Vector2(20, 68)
	task.custom_minimum_size.x = 292
	task.add_theme_stylebox_override("panel", UiKit.style(Color(0.04, 0.09, 0.08, 0.87), UiKit.GOLD, 14))
	root.add_child(task)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	task.add_child(box)
	objective = UiKit.label("", 20, UiKit.PAPER)
	objective.custom_minimum_size.x = 264
	box.add_child(objective)
	checklist = VBoxContainer.new()
	box.add_child(checklist)
	minimap = load("res://scenes/cities/WalkMinimap.gd").new()
	minimap.city = self
	minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	minimap.position = Vector2(-280, 74)
	minimap.size = Vector2(260, 234)
	root.add_child(minimap)
	var footer := PanelContainer.new()
	footer.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_left = 20
	footer.offset_right = -20
	footer.offset_top = -84
	footer.offset_bottom = -16
	footer.add_theme_stylebox_override("panel", UiKit.style(Color(0.04, 0.09, 0.08, 0.90), UiKit.GOLD, 10))
	root.add_child(footer)
	var help := VBoxContainer.new()
	footer.add_child(help)
	hint = UiKit.label("", 21, UiKit.PAPER)
	help.add_child(hint)
	control_help = UiKit.label("", 16, UiKit.MUTED)
	help.add_child(control_help)
	interaction_prompt = PanelContainer.new()
	interaction_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	interaction_prompt.add_theme_stylebox_override("panel", UiKit.style(Color(0.04, 0.09, 0.08, 0.94), UiKit.GOLD, 9))
	interaction_text = UiKit.label("E 对话", 20, UiKit.PAPER)
	interaction_text.autowrap_mode = TextServer.AUTOWRAP_OFF
	interaction_prompt.custom_minimum_size = Vector2(110, 42)
	interaction_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	interaction_prompt.add_child(interaction_text)
	interaction_prompt.hide()
	root.add_child(interaction_prompt)

func _build_route_mesh() -> void:
	guide_mesh = route_guide.create_mesh()
	add_child(guide_mesh)

func hotspot_done(item: Dictionary) -> bool:
	if GameState.is_completed(station_id): return true
	if item["id"] == core_id(): return done("farewell")
	if item.get("observation", false): return GameState.has_flag("observe/"+station_id+"/"+item["id"])
	return GameState.has_flag(clue_key(item["id"]))

func _refresh_progress() -> void:
	UiKit.clear(checklist)
	var texts: Dictionary = story["text"]
	if GameState.is_completed(station_id):
		objective.text = texts["objective_done"]
		target_id = core_id()
	elif done(story["puzzle_step"]):
		objective.text = texts["objective_farewell"]
		target_id = core_id()
	elif done(story["visit_step"]):
		objective.text = texts["objective_puzzle"]
		target_id = core_id()
	elif clue_count() == interview_total():
		if not done("interviews"): GameState.set_flag("flow/"+station_id+"/interviews")
		objective.text = texts["objective_ready"] % [clue_count(),interview_total()]
		target_id = core_id()
	else:
		objective.text = texts["objective_visit"] % [clue_count(),interview_total()]
		if target_id == core_id() or _target_done():
			for item in story["interviews"]:
				if not GameState.has_flag(clue_key(item["id"])):
					target_id = item["id"]
					break
	for item in hotspots:
		var label: Label3D = item["label"]
		label.text = item["name"] + (" ✓" if hotspot_done(item) else "")
		if item["id"] == core_id(): continue
		var mark := "✓ " if hotspot_done(item) else "○ "
		var btn := Button.new()
		btn.text = mark + item["place"] + (" · " + item["name"] if not item.get("observation",false) else " · 风物")
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size",17)
		btn.add_theme_color_override("font_color",UiKit.MUTED if hotspot_done(item) else UiKit.PAPER)
		btn.add_theme_stylebox_override("normal",UiKit.style(Color.TRANSPARENT,Color.TRANSPARENT,4))
		btn.add_theme_stylebox_override("hover",UiKit.style(Color(0.3,0.35,0.21,0.7),UiKit.GOLD,4))
		var clue := ClueBook.entry(station_id, item["id"])
		btn.pressed.connect(open_clue.bind(item["id"]) if ClueBook.collected(clue) else select_target.bind(item["id"]))
		checklist.add_child(btn)
	_update_route()

func open_clue(clue_id: String, acquired := false) -> void:
	preload("res://ui/CityClues.gd").open(self, clue_id, acquired)

func _target_done() -> bool:
	for item in hotspots:
		if item["id"] == target_id: return hotspot_done(item)
	return true

func select_target(id: String) -> void:
	if dialogue != null or reward_panel != null: return
	if id == core_id() and clue_count() < interview_total() and not GameState.is_completed(station_id):
		GameUI.notify(story["text"]["blocked"])
		return
	target_id = id
	_update_route()

func _update_route(force: bool = false) -> void:
	route_guide.update(self, 0.0, force)

func _update_interaction_prompt(nearby: Dictionary) -> void:
	interaction_prompt.hide()
	if nearby.is_empty() or dialogue != null or reward_panel != null or (not done("arrival") and not GameState.is_completed(station_id)): return
	var point: Vector3 = nearby["position"] + Vector3(0, 1.0, 0)
	if camera.is_position_behind(point): return
	interaction_text.text = "E 观察" if nearby.get("observation", false) else "E 对话"
	if nearby["id"] == core_id() and clue_count() < interview_total() and not GameState.is_completed(station_id):
		interaction_text.text = story["text"]["core_locked"]
	interaction_prompt.reset_size()
	var screen := camera.unproject_position(point) + Vector2(30, -18)
	var viewport_size := get_viewport().get_visible_rect().size
	interaction_prompt.position = Vector2(clampf(screen.x, 12, viewport_size.x-interaction_prompt.size.x-12), clampf(screen.y, 12, viewport_size.y-interaction_prompt.size.y-100))
	interaction_prompt.show()

func near_hotspot() -> Dictionary:
	var found := {}
	var nearest := INF
	for item in hotspots:
		var pos: Vector3 = item["position"]
		var dist := Vector2(player.position.x - pos.x, player.position.z - pos.z).length()
		if dist > float(item["radius"]) or absf(player.position.y - pos.y) > 1.2: continue
		# 不可隔墙/隔渠/隔楼层对话；NPC自身不是视线阻挡。
		var ray := PhysicsRayQueryParameters3D.create(player.position + Vector3(0, 0.85, 0), pos + Vector3(0, 0.85, 0), 1)
		ray.exclude = [player.get_rid(), item["actor"].get_node("NpcCollision").get_rid()]
		if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): continue
		if dist < nearest:
			nearest = dist
			found = item
	return found

func can_interact() -> bool:
	return dialogue == null and not near_hotspot().is_empty()

func interact() -> void:
	if dialogue != null or reward_panel != null or SceneRouter.is_switching(): return
	if not done("arrival") and not GameState.is_completed(station_id):
		open_conversation(story["arrival"],"arrival")
		return
	var item := near_hotspot()
	if item.is_empty(): return
	if item.get("observation",false):
		open_conversation(item["dialogue"],"observe/"+item["id"])
	elif item["id"] != core_id():
		var id: String = item["dialogue"]
		if GameState.is_completed(station_id): id = item.get("completed_dialogue",id)
		elif hotspot_done(item): id = item.get("repeat",id)
		open_conversation(id,"clue/"+item["id"])
	elif GameState.is_completed(station_id):
		if story.has("core_repeat"): open_conversation(story["core_repeat"],"repeat")
		else: GameUI.notify(story["text"]["done_greeting"])
	elif clue_count() < interview_total(): GameUI.notify(story["text"]["blocked"])
	elif not done(story["visit_step"]): open_conversation(story["visit"],story["visit_step"])
	elif done(story["puzzle_step"]): open_conversation(story["farewell"],"farewell")
	else:
		player.enabled = false
		_sync_mouse_mode()
		adapter.resume_story.call_deferred()

func open_conversation(id: String, step: String) -> void:
	if dialogue != null or reward_panel != null or (SceneRouter.is_switching() and step != "arrival"): return
	if step == "arrival": arrival_screen.begin(self, station_id)
	GameUI.clear_notification()
	player.enabled = false
	player.velocity = Vector3.ZERO
	dragging = false
	hud.hide()
	guide_mesh.hide()
	var layer := CanvasLayer.new()
	layer.name = "CityConversation"
	layer.layer = 20
	add_child(layer)
	dialogue = load("res://scenes/DialogueScene.tscn").instantiate()
	dialogue.configure_inline(id)
	dialogue.dialogue_finished.connect(func(_id: String):
		var fresh_clue := step.begins_with("clue/") and not GameState.has_flag("clue/" + station_id + "/" + step.trim_prefix("clue/"))
		if step.begins_with("clue/"):
			var clue_id := step.trim_prefix("clue/")
			GameState.set_flag(clue_key(clue_id))

		elif step.begins_with("observe/"):
			GameState.set_flag("observe/"+station_id+"/"+step.trim_prefix("observe/"))
		elif step != "repeat":
			GameState.set_flag("flow/"+station_id+"/"+step)
		close_conversation(layer)
		_refresh_progress()
		if fresh_clue: open_clue(step.trim_prefix("clue/"), true)
		if step == "farewell" and done(story["puzzle_step"]) and clue_count() == interview_total() and done(story["visit_step"]):
			_collect_reward()
		elif step == story["visit_step"] and not done(story["puzzle_step"]):
			player.enabled = false
			_sync_mouse_mode()
			adapter.resume_story.call_deferred()
	)
	dialogue.dialogue_left.connect(func(): close_conversation(layer))
	layer.add_child(dialogue)
	_sync_mouse_mode()

func close_conversation(layer: CanvasLayer) -> void:
	dialogue = null
	layer.queue_free()
	arrival_screen.finish(self)
	player.enabled = true
	player.jump_needs_release = true
	hud.show()
	guide_mesh.show()
	_sync_mouse_mode()

func _show_reward() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	reward_panel = Control.new()
	reward_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(reward_panel)
	var journal = preload("res://ui/JourneyJournal.gd").new()
	journal.prepare(reward_panel, story["fragment"], func():
		_show_completion_choices(layer)
	)
	player.enabled = false
	_sync_mouse_mode()

func _close_reward(layer: CanvasLayer) -> void:
	layer.queue_free()
	reward_panel = null
	player.enabled = true
	player.jump_needs_release = true
	_sync_mouse_mode()

func _show_completion_choices(layer: CanvasLayer) -> void:
	UiKit.clear(reward_panel)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.08, 0.07, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	reward_panel.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	reward_panel.add_child(center)
	var card := UiKit.panel(true)
	card.custom_minimum_size = Vector2(700, 280)
	center.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	card.add_child(box)
	box.add_child(UiKit.label(story["text"].get("reward_next", "本城走访完成"), 28, UiKit.INK))
	preload("res://ui/CityCompletionChoices.gd").add_to(box, station_id, func(): _close_reward(layer))

func _process(delta: float) -> void:
	if player == null: return
	_sync_mouse_mode()
	control_help.text = "视角模式 · 鼠标转视角 · Tab 显示鼠标 · WASD 移动 · E 对话 · R 复位 · Esc 暂停" if mouse_look else "鼠标模式 · 点击任务 / 小地图引路 · Tab 返回视角 · Esc 暂停"
	player.heading = yaw
	var limits: Array = story.get("fall_bounds", story["bounds"])
	if player.position.y < -2 or player.position.x < limits[0] or player.position.x > limits[1] or player.position.z < limits[2] or player.position.z > limits[3]:
		player.position = last_safe + Vector3(0, 0.2, 0)
		player.velocity = Vector3.ZERO
		camera_initialized = false
	if player.is_on_floor() and player.position.y > -0.4:
		last_safe = player.position
	if dialogue == null:
		_update_camera()
	if dialogue == null and reward_panel == null:
		route_guide.update(self, delta)
	minimap.queue_redraw()
	if dialogue != null: return
	var nearby := near_hotspot()
	_update_interaction_prompt(nearby)
	guide_mesh.visible = route_guide.visible(self, nearby)
	if not done("arrival") and not GameState.is_completed(station_id):
		hint.text = "E · 听开场旁白，认领访查任务"
	elif not nearby.is_empty():
		if nearby["id"] == core_id():
			hint.text = story["text"]["core_farewell"] if done(story["puzzle_step"]) else (story["text"]["core_puzzle"] if done(story["visit_step"]) else "E · 拜访" + story["core"]["name"])
			if GameState.is_completed(station_id): hint.text = "E · 再访" + story["core"]["name"]
			if clue_count() < interview_total() and not GameState.is_completed(station_id): hint.text = "先完成走访 · %d/%d" % [clue_count(),interview_total()]
		elif nearby.get("observation",false):
			hint.text = "E · 观察" + nearby["name"]
		elif hotspot_done(nearby):
			hint.text = "E · 重温与" + nearby["name"] + "的对话"
		else:
			hint.text = "E · 与" + nearby["name"] + "交谈"
	else:
		for item in hotspots:
			if item["id"] == target_id:
				hint.text = route_guide.hint_text(item["place"])
		if GameState.is_completed(station_id): hint.text = story["text"]["footer_done"]

func _update_camera() -> void:
	if camera == null: return
	var focus := player.global_position + Vector3(0, 0.8, 0)
	var offset := Basis(Vector3.UP, yaw) * Vector3(0, sin(pitch) * distance, cos(pitch) * distance)
	# 球形扫掠为镜头近裁剪面留出空间；装饰和河道安全栏不缩镜头。
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.28
	query.shape = sphere
	query.collision_mask = 4
	query.transform = Transform3D(Basis.IDENTITY, focus)
	query.motion = offset
	var fractions := get_world_3d().direct_space_state.cast_motion(query)
	var fraction := 1.0 if fractions.is_empty() else maxf(0.04, fractions[0] - 0.02)
	var desired := focus + offset * fraction
	# 收近立即生效，恢复距离平滑，避免撞墙后突然拉远。
	if not camera_initialized or desired.distance_to(focus) < camera.position.distance_to(focus):
		camera.position = desired
	else:
		camera.position = camera.position.lerp(desired, 1.0 - exp(-14.0 * maxf(get_process_delta_time(), 0.001)))
	camera_initialized = true
	if camera.position.distance_to(focus) > 0.02: camera.look_at(focus, Vector3.UP)

func _unhandled_input(event: InputEvent) -> void:
	if dialogue != null or reward_panel != null or SceneRouter.is_switching(): return
	if event is InputEventMouseMotion: return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		yaw = float(spec["yaw"])
		pitch = float(spec["pitch"])
		distance = float(spec["distance"])
		camera_initialized = false
		get_viewport().set_input_as_handled()
		return
	super._unhandled_input(event)
	pitch = clampf(pitch, 0.38, 0.95)
	distance = clampf(distance, 7, 16)

func _input(event: InputEvent) -> void:
	# Tab切换鼠标与视角；叙事弹层自动释放光标。
	if player == null or dialogue != null or reward_panel != null or not player.enabled or get_tree().paused or SceneRouter.is_switching(): return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_TAB:
		_toggle_mouse_look()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and mouse_look and window_focused and dialogue == null and reward_panel == null and not get_tree().paused and not SceneRouter.is_switching():
		yaw -= event.screen_relative.x * 0.003 * GameSettings.camera_sensitivity
		pitch = clampf(pitch + event.screen_relative.y * 0.003 * GameSettings.camera_sensitivity, 0.38, 0.95)
		get_viewport().set_input_as_handled()

func _toggle_mouse_look() -> void:
	if player == null or not player.enabled or dialogue != null or reward_panel != null or get_tree().paused or SceneRouter.is_switching(): return
	mouse_look = not mouse_look
	if mouse_look:
		var focus_owner := get_viewport().gui_get_focus_owner()
		if focus_owner != null: focus_owner.release_focus()
	_sync_mouse_mode()

func _sync_mouse_mode() -> void:
	var capture: bool = mouse_look and window_focused and player != null and player.enabled and dialogue == null and reward_panel == null and not get_tree().paused and not SceneRouter.is_switching()
	var mode := Input.MOUSE_MODE_CAPTURED if capture else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != mode: Input.mouse_mode = mode

func controls_help() -> String:
	return "WASD 移动 · Shift 跑 · 空格 跳 · E 对话\n鼠标直接转视角 · 滚轮缩放 · R 恢复视角\nTab 显示鼠标，点击任务和小地图选择引路目标\n再按 Tab，恢复鼠标转视角\n对话：点击 / 空格补全文字，再按一次继续"

func _notification(what: int) -> void:
	super._notification(what)
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		window_focused = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		window_focused = true
	elif what == NOTIFICATION_PAUSED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
