extends "res://scenes/cities/NarrativeCity.gd"
## 丽江专属地形；剧情、镜头、输入、小地图共享配置驱动基类。
func _init() -> void:
	story_path = "res://data/lijiang_city.json"

func _character_model(id: String, height: float) -> Node3D:
	return preload("res://scenes/cities/CharacterModels.gd").create_visual("lijiang", id, height)

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
		var height: float = 1.75 if item["id"] == "dongba" else item.get("height", 1.65)
		var model := _character_model(item["id"], height)
		if model == null: continue
		var actor: Node3D = item["actor"]
		for child in actor.get_children():
			if child is MeshInstance3D: child.queue_free()
		actor.add_child(model)
		item["label"].position.y = height + 0.35

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

func _prepare_geometry() -> void:
	for mesh in map_root.find_children("B_05_*", "MeshInstance3D", true, false):
		mesh.visible = false

func _build_water_barriers() -> void:
	var body := StaticBody3D.new()
	body.name = "RiverSafety"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var river: Array = story["canal"]
	for i in river.size() - 1:
		var a := Vector3(river[i][0], 0, river[i][1])
		var b := Vector3(river[i+1][0], 0, river[i+1][1])
		var length := a.distance_to(b)
		var sections: Array[Vector2] = [Vector2(0, length)]
		for bridge in story["bridges"]:
			if bridge["segment"] == i:
				var middle: float = length * float(bridge["fraction"])
				sections = [Vector2(0, middle - 1.40), Vector2(middle + 1.40, length)]
		for section in sections:
			if section.y <= section.x: continue
			var center := a + (b - a).normalized() * ((section.x + section.y) * 0.5)
			_box(body, center + Vector3(0, 1.05, 0), Vector3(1.90, 2.30, section.y - section.x + 0.015), atan2(b.x - a.x, b.z - a.z))
	var edge := StaticBody3D.new()
	edge.name = "TownBoundary"
	add_child(edge)
	_box(edge, Vector3(-30, 1, 0), Vector3(0.5, 4, 48))
	_box(edge, Vector3(30, 1, 0), Vector3(0.5, 4, 48))
	_box(edge, Vector3(0, 1, -21.5), Vector3(60, 4, 0.5))
	_box(edge, Vector3(0, 1, 23.5), Vector3(60, 4, 0.5))
	# 水车活动件不适合逐片碰撞；用固定底座阻挡，镜头仍可看见水车。
	var wheel := map_root.find_child("Waterwheel_axle", true, false) as Node3D
	if wheel != null:
		_box(edge, Vector3(wheel.global_position.x, 0.4, wheel.global_position.z), Vector3(3.6, 0.9, 2.5))
