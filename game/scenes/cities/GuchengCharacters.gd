extends RefCounted
## 复用四城v02分件网格、动作及材质；变体仅在当前实例生效。
static func create_visual(id: String, height: float = 1.65) -> Node3D:
	var source := {"protagonist": ["lijiang", "protagonist"], "mulaoye": ["lijiang", "dongba"], "xiaomu": ["xianggelila", "son"]}
	if not source.has(id): return null
	var pair: Array = source[id]
	var model := preload("res://scenes/cities/CharacterModels.gd").create_visual(pair[0], pair[1], height)
	if model == null: return null
	var hidden := ["Crown", "LetterCard", "CardMark", "Detail_Antique gold"] if id == "mulaoye" else []
	for part in model.find_children("*", "MeshInstance3D", true, false):
		for tag in hidden:
			if tag in part.name: part.hide()
		for surface in part.mesh.get_surface_count():
			var material := part.get_active_material(surface) as StandardMaterial3D
			if material == null: continue
			var color := Color.TRANSPARENT
			if id == "mulaoye" and "Deep jade robe" in material.resource_name: color = Color("665347")
			if id == "xiaomu" and "Coat" in part.name: color = Color("556c72")
			if id == "protagonist" and "Vest" in part.name: color = Color("46574c")
			if id == "protagonist" and "Coat" in part.name: color = Color("b8a779")
			if color.a > 0:
				var variant := material.duplicate() as StandardMaterial3D
				variant.albedo_texture = null
				variant.albedo_color = color
				part.set_surface_override_material(surface, variant)
	return model
