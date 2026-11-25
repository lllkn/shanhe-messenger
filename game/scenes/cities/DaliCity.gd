extends "res://scenes/cities/CityStory.gd"
## 大理独立数据与锚点适配，不继承丽江专用逻辑。
var follow_camera := preload("res://scenes/cities/DaliFollowCamera.gd").new()

func _update_camera() -> void:
	if camera == null: return
	follow_camera.update(camera, player, yaw, pitch, distance, get_process_delta_time(), not camera_initialized)
	camera_initialized = true

func _init() -> void:
	story_path = "res://data/dali_city.json"

func _character_model(id: String) -> Node3D:
	var heights := {"protagonist": 1.65, "vendor": 1.65, "youngster": 1.60, "granny": 1.48, "popo": 1.48}
	return preload("res://scenes/cities/CharacterModels.gd").create_visual("dali", id, heights.get(id, 1.65))

func _build_player() -> void:
	super._build_player()
	var model := _character_model("protagonist")
	if model == null: return
	for child in player.get_children():
		if child is MeshInstance3D: child.queue_free()
	player.add_child(model)

func _build_hotspots() -> void:
	super._build_hotspots()
	for item in hotspots:
		if item.get("observation", false): continue
		var model := _character_model(item["id"])
		if model == null: continue
		var actor: Node3D = item["actor"]
		for child in actor.get_children():
			if child is MeshInstance3D: child.queue_free()
		actor.add_child(model)
		model.rotation.y = float(item.get("facing", 0.0))
		var body: StaticBody3D = actor.get_node("NpcCollision")
		# 旧语义锚点Y=0.1；在同一X/Z实测地面，人物/标签/交互/路线共享脚底。
		var ray := PhysicsRayQueryParameters3D.create(actor.position + Vector3(0, 0.5, 0), actor.position - Vector3(0, 0.7, 0), 1)
		ray.exclude = [body.get_rid(), player.get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty():
			actor.position.y = hit.position.y
			item["position"] = actor.position
		var height: float = item.get("height", 1.65)
		item["label"].position.y = height + 0.35
		var collider: CollisionShape3D = body.get_child(0)
		collider.shape = collider.shape.duplicate()
		collider.shape.size = Vector3(0.70, height, 0.55)
		collider.position.y = height * 0.5

func open_conversation(id: String, step: String) -> void:
	super.open_conversation(id, step)
	if dialogue != null: _show_map_characters(false)

func close_conversation(layer: CanvasLayer) -> void:
	super.close_conversation(layer)
	_show_map_characters(true)

func _show_map_characters(show_models: bool) -> void:
	var visual := player.get_node_or_null("CharacterVisual") as Node3D
	if visual != null: visual.visible = show_models
	for item in hotspots: item["actor"].visible = show_models
