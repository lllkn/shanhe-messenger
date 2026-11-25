extends SceneTree
func _initialize() -> void:
	for id in ["lijiang", "xianggelila", "dali", "puer"]:
		var requested := OS.get_environment("BAKE_CITY")
		if not requested.is_empty() and id != requested:
			continue
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file("res://assets/cities/%s/map.glb" % id, state) != OK:
			quit(1)
			return
		var map := doc.generate_scene(state)
		root.add_child(map)
		var data: Resource = load("res://core/CityCollisionData.gd").new()
		var camera_data: Resource = load("res://core/CityCollisionData.gd").new()
		for mesh in map.find_children("*", "MeshInstance3D", true, false):
			var n := str(mesh.name)
			if n.begins_with("Dyn_") or n.begins_with("Waterwheel_") or n.begins_with("Boat_") or n.begins_with("GoalDoor_"):
				continue
			if n.contains("Water") or n.contains("water") or n.contains("Canal_Turquoise"):
				continue
			if id == "lijiang" and (n.begins_with("B_05_") or n.contains("Leaf") or n.contains("Goal_Cyan") or n.contains("Stall_TeaLeaves")):
				continue
			# 本城旧NPC合批隐藏后改由剧情演员显示；树冠、飘布不阻挡行走。
			if id == "xianggelila" and (n.begins_with("B_05_") or n.contains("Leaf") or n.contains("Meadow_Scrub") or n.contains("Flag_") or n.contains("Dye_White") or n.contains("Dye_Golden") or n.contains("Dye_Indigo") or n.contains("Dye_TibetanRed")):
				continue
			if id == "dali" and n.begins_with("B_00_") and n != "B_00_M_Path_Flagstone":
				continue
			if mesh.mesh == null:
				continue
			var shape := ConcavePolygonShape3D.new()
			shape.backface_collision = id == "puer"
			var faces: PackedVector3Array = mesh.mesh.get_faces()
			if id in ["lijiang", "xianggelila"] and (n.contains("Path_Flagstone") or n.contains("Earth_Olive") or n.contains("Town_RammedEarthFloor")):
				var top_faces := PackedVector3Array()
				for i in range(0, faces.size(), 3):
					var normal := (faces[i+2] - faces[i]).cross(faces[i+1] - faces[i]).normalized()
					if normal.y > 0.5:
						top_faces.append_array(PackedVector3Array([faces[i], faces[i+1], faces[i+2]]))
				faces = top_faces
			shape.set_faces(faces)
			data.shapes.append(shape)
			var transform: Transform3D = mesh.transform
			var parent := mesh.get_parent()
			while parent is Node3D:
				transform = parent.transform * transform
				parent = parent.get_parent()
			data.transforms.append(transform)
			data.names.append(n)
			if id == "lijiang" and (n.begins_with("B_03_") or n.begins_with("B_15_") or n.contains("Roof_Charcoal") or n.contains("Roof_AshGray")):
				camera_data.shapes.append(shape)
				camera_data.transforms.append(transform)
				camera_data.names.append(n)
			if id == "xianggelila" and (n.begins_with("B_03_") or n.begins_with("B_09_D_") or n.begins_with("B_09_M_Stone") or n.begins_with("B_08_D_")):
				camera_data.shapes.append(shape)
				camera_data.transforms.append(transform)
				camera_data.names.append(n)
		var out := "camera_collision.res" if id == "puer" else "collision.res"
		if id == "puer":
			# 行走仍使用map_data；镜头只避建筑，不被棕叶、茶山与装饰挤近。
			for i in data.names.size():
				var n: String = data.names[i]
				# B_04的cream/blue合批也包含矮楼墙面，不能只选屋顶和木材。
				if n.begins_with("B_03_") or (n.begins_with("B_04_") and not n.contains("leaf") and not n.contains("tea") and not n.contains("cloth")) or n.begins_with("B_08_"):
					camera_data.shapes.append(data.shapes[i])
					camera_data.transforms.append(data.transforms[i])
					camera_data.names.append(n)
		var output_data: Resource = camera_data if id == "puer" else data
		var err := ResourceSaver.save(output_data, "res://assets/cities/%s/%s" % [id, out])
		print("BAKED ", id, " shapes=", output_data.shapes.size(), " error=", err)
		if id in ["lijiang", "xianggelila"]:
			var camera_error := ResourceSaver.save(camera_data, "res://assets/cities/%s/camera_collision.res" % id)
			if camera_error != OK:
				quit(1)
				return
		map.free()
		if err != OK:
			quit(1)
			return
	quit()
