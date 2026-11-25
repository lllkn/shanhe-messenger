extends "res://scenes/cities/LijiangCity.gd"
## 当前古城几何与共用城市组件；终章只有一个目标与线性对话。
var ending := false
var xiaomu_actor: Node3D
var closing_props: Node3D

func _init() -> void:
	story_path = "res://data/gucheng_city.json"

func _ready() -> void:
	# 旧拼锦占位可能只记了站点完成；保留四城成果，新终章读完再完成。
	if GameState.is_completed("gucheng") and not GameState.has_flag("flow/gucheng/visit"):
		GameState.completed.erase("gucheng")
		GameState.save_game()
	await super._ready()
	if player == null: return
	if done("visit"): _prepare_learning_pose()
	if SceneRouter.params.get("replay_ending", false):
		open_conversation(story["visit"], "replay")
	elif done("visit") and not done("ending"):
		_finish_ending.call_deferred()

func _character_model(id: String, height: float) -> Node3D:
	return preload("res://scenes/cities/GuchengCharacters.gd").create_visual(id, height)

func _build_hotspots() -> void:
	super._build_hotspots()
	xiaomu_actor = Node3D.new()
	xiaomu_actor.name = "Xiaomu"
	xiaomu_actor.position = goal_position + Vector3(1.05, 0, 0)
	add_child(xiaomu_actor)
	xiaomu_actor.add_child(_character_model("xiaomu", 1.65))
	xiaomu_actor.visible = done("visit")

func _refresh_progress() -> void:
	UiKit.clear(checklist)
	target_id = core_id()
	objective.text = ui("complete_objective") if done("visit") else ui("initial_objective")
	for item in hotspots:
		item["label"].text = display_name(item) + (" ✓" if done("visit") else "")
	_update_route()

func hotspot_done(_item: Dictionary) -> bool:
	return done("visit")

func interact() -> void:
	if ending or dialogue != null or reward_panel != null or SceneRouter.is_switching(): return
	if not done("arrival"):
		open_conversation(story["arrival"], "arrival")
	elif not near_hotspot().is_empty():
		open_conversation(story["core"]["repeat"] if done("visit") else story["visit"], "repeat" if done("visit") else "visit")

func _conversation_completed(step: String) -> void:
	if step in ["visit", "replay"]:
		GameState.set_flag("flow/gucheng/workshop")
		_finish_ending.call_deferred()

func _show_map_characters(show_models: bool) -> void:
	super._show_map_characters(show_models)
	if xiaomu_actor != null: xiaomu_actor.visible = show_models and done("visit")

func _process(delta: float) -> void:
	if ending: return
	super._process(delta)
	if player == null: return
	if dialogue == null and reward_panel == null and done("arrival"):
		hint.text = ui("complete_hint") if done("visit") else (ui("core_hint") if not near_hotspot().is_empty() else route_guide.hint_text("木老爷的织坊"))

func _finish_ending() -> void:
	if ending: return
	ending = true
	player.enabled = false
	player.velocity = Vector3.ZERO
	_sync_mouse_mode()
	hud.hide()
	guide_mesh.hide()
	interaction_prompt.hide()
	arrival_screen.finish(self)
	_show_map_characters(true)
	xiaomu_actor.show()
	var old: Node3D = hotspots[0]["actor"]
	old.rotation.y = 0.18
	for child in old.get_children():
		if child is Label3D: child.hide()
	_prepare_learning_pose()
	player.position = goal_position + Vector3(2.6, 0, 2.2)
	var reporter: Node3D = player.get_node("CharacterVisual")
	reporter.set_process(false)
	reporter.rotation.y = -2.2
	for part in reporter.find_children("*Camera*", "MeshInstance3D", true, false):
		part.position.y += 0.42
	for limb in ["*Arm_L*", "*Arm_R*"]:
		var node := reporter.find_child(limb, true, false) as Node3D
		if node != null: node.rotation.x = -1.65
	var focus := goal_position + Vector3(0.55, 0.85, 0)
	var retreat := create_tween()
	retreat.tween_method(func(value: float):
		camera.position = focus + Vector3(2.0, 1.3, 5.3).lerp(Vector3(3.5, 2.5, 8.0), value)
		camera.look_at(focus)
	, 0.0, 1.0, 3.0)
	await retreat.finished
	var layer := CanvasLayer.new()
	layer.layer = 40
	add_child(layer)
	var black := ColorRect.new()
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	black.color = Color(0, 0, 0, 0)
	layer.add_child(black)
	var fade := create_tween()
	fade.tween_property(black, "color:a", 1.0, 1.8)
	await fade.finished
	GameState.set_flag("flow/gucheng/ending")
	GameState.complete_station(station_id)
	SceneRouter.goto_finale()

func _prepare_learning_pose() -> void:
	xiaomu_actor.rotation.y = -0.12
	var young: Node3D = xiaomu_actor.get_node("CharacterVisual")
	if not young.has_meta("seated"):
		young.position.y -= 0.38
		young.set_meta("seated", true)
	for limb in ["*Leg_L*", "*Leg_R*"]:
		var node := young.find_child(limb, true, false) as Node3D
		if node != null: node.rotation.x = -0.9
	_build_closing_props()

func _build_closing_props() -> void:
	if closing_props != null: return
	closing_props = Node3D.new()
	closing_props.name = "WorkshopFurniture"
	closing_props.position = goal_position + Vector3(1.05, 0, 0)
	add_child(closing_props)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("70533c")
	wood.roughness = 0.85
	for piece in [[Vector3(0, 0.48, 0), Vector3(0.65, 0.08, 0.55)], [Vector3(-0.24, 0.24, -0.18), Vector3(0.07, 0.48, 0.07)], [Vector3(0.24, 0.24, -0.18), Vector3(0.07, 0.48, 0.07)], [Vector3(-0.24, 0.24, 0.18), Vector3(0.07, 0.48, 0.07)], [Vector3(0.24, 0.24, 0.18), Vector3(0.07, 0.48, 0.07)], [Vector3(-0.62, 0.48, 0.78), Vector3(0.09, 0.96, 0.09)], [Vector3(0.62, 0.48, 0.78), Vector3(0.09, 0.96, 0.09)], [Vector3(0, 0.92, 0.78), Vector3(1.32, 0.09, 0.09)], [Vector3(0, 0.47, 0.78), Vector3(1.32, 0.09, 0.09)]]:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = piece[1]
		mesh.mesh = box
		mesh.position = piece[0]
		mesh.material_override = wood
		closing_props.add_child(mesh)
	var thread := StandardMaterial3D.new()
	thread.albedo_color = Color("c4b595")
	for index in 18:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.008, 0.4, 0.008)
		mesh.mesh = box
		mesh.position = Vector3(-0.5 + index * 0.0588, 0.7, 0.78)
		mesh.material_override = thread
		closing_props.add_child(mesh)
