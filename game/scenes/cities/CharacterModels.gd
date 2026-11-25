extends RefCounted
## v02角色统一采用元数据里的实际高度与脚底，保留动作分件层级。
static func create_visual(city: String, id: String, height: float) -> Node3D:
	var directory := "res://assets/characters/%s/models/" % city
	var info := ContentDB.read_json(directory + "model-info-v02.json")
	var spec: Dictionary = info.get(id, {})
	if spec.is_empty():
		push_error("缺少人物v02元数据：" + city + "/" + id)
		return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(directory + "%s-v02.glb" % id, state) != OK: return null
	var model := doc.generate_scene(state)
	if model == null: return null
	model.name = "CharacterVisual"
	model.scale = Vector3.ONE * height / float(spec["height"])
	model.position.y = -float(spec["foot_y"]) * model.scale.y
	# 微小面部网格不投影，避免城市远距级联阴影在脸上产生自阴影斑点。
	# 发型、衣服与四肢继续投影，保留人物的地面轮廓。
	for part in model.find_children("*", "MeshInstance3D", true, false):
		if ["SculptedFace", "Ear", "Eye", "Iris", "Pupil", "Nose", "Lip", "Lid", "Brow", "Glasses"].any(func(tag): return tag in part.name):
			part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.set_script(load("res://scenes/cities/CharacterMotion.gd"))
	return model
