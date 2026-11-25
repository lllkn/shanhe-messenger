extends "res://scenes/cities/NarrativeCity.gd"
## 普洱仅适配既有人物、道路加权和誓约领奖页；输入、镜头、对话与小地图共用。
var follow_camera_safety := preload("res://scenes/cities/FollowCameraSafety.gd").new()

func _update_camera() -> void:
	if camera == null or player == null: return
	follow_camera_safety.update(camera,player,yaw,pitch,distance,get_process_delta_time(),not camera_initialized)
	camera_initialized = true

func _init() -> void:
	story_path = "res://data/puer_city.json"
	walk_guide = preload("res://core/PuerWalkGuide.gd").new()

func _ready() -> void:
	await super._ready()
	if player != null and done("farewell") and not GameState.is_completed(station_id):
		_collect_reward()

func _character_model(id: String, height: float) -> Node3D:
	return preload("res://scenes/cities/CharacterModels.gd").create_visual("puer", id, height)

func _build_player() -> void:
	super._build_player()
	var model := _character_model("protagonist", 1.65)
	if model == null: return
	for child in player.get_children():
		if child is MeshInstance3D: child.queue_free()
	player.add_child(model)

func _build_hotspots() -> void:
	# 保留旧地图演员节点，只隐藏原视觉部件；热点/碰撞/标签仍共用安全锚点。
	for item in story["interviews"]:
		var actor := map_root.find_child(item.get("existing_actor", "__none__"), true, false) as Node3D
		if actor != null: actor.hide()
	super._build_hotspots()
	for item in hotspots:
		var height: float = item.get("height", 1.65)
		var model := _character_model(item["id"], height)
		if model == null: continue
		var actor: Node3D = item["actor"]
		for child in actor.get_children():
			if child is MeshInstance3D: child.queue_free()
		actor.add_child(model)
		item["label"].position.y = height + 0.35

func _show_map_characters(show_models: bool) -> void:
	var visual := player.get_node_or_null("CharacterVisual") as Node3D
	if visual != null: visual.visible = show_models
	for item in hotspots:
		item["actor"].visible = show_models

func close_conversation(layer: CanvasLayer) -> void:
	super.close_conversation(layer)
	_show_map_characters(true)

func open_conversation(id: String, step: String) -> void:
	if dialogue != null or (SceneRouter.is_switching() and step != "arrival"): return
	super.open_conversation(id, step)
	if dialogue == null: return
	_show_map_characters(false)

func _collect_reward() -> void:
	if not done("farewell") or not done(story["puzzle_step"]) or not done(story["visit_step"]) or clue_count() != story["interviews"].size(): return
	GameState.collect_fragment(story["fragment"])
	_refresh_progress()
	_show_reward()

func _show_reward() -> void:
	GameUI.clear_notification()
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
