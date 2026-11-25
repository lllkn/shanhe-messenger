extends SceneTree
func _initialize() -> void:
	for id in ["dali"]:
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
			if id == "dali" and n.begins_with("B_00_") and n != "B_00_M_Path_Flagstone":
				continue
			if n == "B_02_D_Stone_Coping":
				continue # 薄沿岸压顶是装饰；防落水由实际渠线安全阻挡承担，桥面仍保留实体碰撞。
			if n.begins_with("B_05_") or n.contains("Leaf") or n.contains("TieDye_") or n.contains("HandmadePaper") or n.contains("BaiInk") or n.contains("BaiPaint"):
				continue
			if mesh.mesh == null:
				continue
			var shape := ConcavePolygonShape3D.new()
			shape.backface_collision = id == "puer"
			var faces: PackedVector3Array = mesh.mesh.get_faces()
			if n == "B_00_M_Path_Flagstone":
				var top_faces := PackedVector3Array()
				for i in range(0, faces.size(), 3):
					var normal := (faces[i+2] - faces[i]).cross(faces[i+1] - faces[i]).normalized()
					if normal.y > 0.5:
						top_faces.append_array(PackedVector3Array([faces[i], faces[i+1], faces[i+2]]))
				faces = top_faces
			shape.set_faces(faces)
			# 合批墙体用独立凸体，防止地面射线从墙内开始时把墙内误判为可走。
			var shapes: Array[Shape3D] = []
			if (n.begins_with("B_03_") or n.begins_with("B_07_")) and not n.contains("Roof_"):
				for points in components(faces):
					var solid := ConvexPolygonShape3D.new()
					solid.points = points
					shapes.append(solid)
			else:
				shapes.append(shape)
			var transform: Transform3D = mesh.transform
			var parent := mesh.get_parent()
			while parent is Node3D:
				transform = parent.transform * transform
				parent = parent.get_parent()
			for part in shapes:
				data.shapes.append(part)
				data.transforms.append(transform)
				data.names.append(n)
				if n.begins_with("B_03_") or n.begins_with("B_07_") or n.contains("Roof_"):
					camera_data.shapes.append(part)
					camera_data.transforms.append(transform)
					camera_data.names.append(n)
		var out := "camera_collision.res" if id == "puer" else "collision.res"
		var err := ResourceSaver.save(data, "res://assets/cities/%s/%s" % [id, out])
		print("BAKED ", id, " shapes=", data.shapes.size(), " error=", err)
		if id == "dali":
			var camera_error := ResourceSaver.save(camera_data, "res://assets/cities/dali/camera_collision.res")
			if camera_error != OK:
				quit(1)
				return
		map.free()
		if err != OK:
			quit(1)
			return
	quit()

func components(faces: PackedVector3Array) -> Array[PackedVector3Array]:
	var graph := {}
	for i in range(0, faces.size(), 3):
		var triangle := [faces[i], faces[i+1], faces[i+2]]
		for point in triangle:
			if not graph.has(point): graph[point] = []
			graph[point].append_array(triangle)
	var visited := {}
	var result: Array[PackedVector3Array] = []
	for point in graph:
		if visited.has(point): continue
		var stack := [point]
		var vertices := PackedVector3Array()
		while not stack.is_empty():
			var current: Vector3 = stack.pop_back()
			if visited.has(current): continue
			visited[current] = true
			vertices.append(current)
			for neighbor in graph[current]:
				if not visited.has(neighbor): stack.append(neighbor)
		if vertices.size() >= 4: result.append(vertices)
	return result
