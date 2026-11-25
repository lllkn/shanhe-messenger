extends "res://scenes/cities/NarrativeCity.gd"
## 香格里拉故事与地形使用本城数据，不继承丽江专用节点与标记。
func _init() -> void:
	story_path = "res://data/xianggelila_city.json"

func _prepare_geometry() -> void:
	for mesh in map_root.find_children("B_05_*", "MeshInstance3D", true, false):
		mesh.visible = false
	# 院内以现有染坊背景叙事，交谈点位在西侧门外，门扇保持可见。
	for mesh in map_root.find_children("NPC_*", "MeshInstance3D", true, false):
		mesh.hide()

func _character_model(id: String, height: float) -> Node3D:
	return preload("res://scenes/cities/CharacterModels.gd").create_visual("xianggelila", id, height)

func _build_player() -> void:
	super._build_player()
	var model := _character_model("protagonist", 1.65)
	if model == null: return
	for child in player.get_children():
		if child is MeshInstance3D: child.queue_free()
	player.add_child(model)

func _build_hotspots() -> void:
	super._build_hotspots()
	for item in hotspots:
		var height: float = item.get("height", 1.65)
		var model := _character_model(item["id"], height)
		if model == null: continue
		var actor: Node3D = item["actor"]
		for child in actor.get_children():
			if child is MeshInstance3D: child.queue_free()
		actor.add_child(model)
		model.rotation.y = deg_to_rad(item.get("facing_degrees", 0.0))
		item["label"].position.y = height + 0.35
		# 原锚点高于石板；落地修正只作用视觉，碰撞和交互继续使用原安全点。
		var at: Vector3 = item["position"]
		var query := PhysicsRayQueryParameters3D.create(at + Vector3(0,0.3,0), at-Vector3(0,1.2,0),1)
		query.exclude = [player.get_rid(), actor.get_node("NpcCollision").get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty(): model.position.y += hit.position.y-at.y

func open_conversation(id: String, step: String) -> void:
	super.open_conversation(id, step)
	if dialogue != null: _show_map_characters(false)

func close_conversation(layer: CanvasLayer) -> void:
	super.close_conversation(layer)
	_show_map_characters(true)

func _show_map_characters(show_models: bool) -> void:
	var visual := player.get_node_or_null("CharacterVisual") as Node3D
	if visual != null: visual.visible = show_models
	for item in hotspots:
		item["actor"].visible = show_models
