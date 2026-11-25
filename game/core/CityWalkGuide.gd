class_name CityWalkGuide
extends RefCounted
## 从真实物理地面采样路径；只提供引导，不替玩家移动。
var grid := AStarGrid2D.new()
var origin := Vector2(-29, -20)
var cell := 0.6
var city: Node3D
var ready := false
var ray_top := 0.8
var ray_bottom := -0.65
var road_names: Array = ["Path_Flagstone"]
var floor_heights: Dictionary = {}
var foot_clearance := 0.035
var floor_names: Array = []
var ground_exclusions: Array[RID] = []

func build(owner_city: Node3D, bounds: Array) -> void:
	city = owner_city
	var options: Dictionary = city.story.get("walk", {})
	ray_top = float(options.get("ray_top", 0.8))
	ray_bottom = float(options.get("ray_bottom", -0.65))
	road_names = options.get("road_names", ["Path_Flagstone"])
	foot_clearance = float(options.get("foot_clearance", 0.035))
	floor_names = options.get("floor_names", [])
	floor_heights.clear()
	ground_exclusions.clear()
	ground_exclusions.append(city.player.get_rid())
	for item in city.hotspots:
		ground_exclusions.append(item["actor"].get_node("NpcCollision").get_rid())
	origin = Vector2(bounds[0], bounds[2])
	grid.region = Rect2i(0, 0, ceili((bounds[1] - bounds[0]) / cell) + 1, ceili((bounds[3] - bounds[2]) / cell) + 1)
	grid.cell_size = Vector2(cell, cell)
	grid.offset = origin
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.update()
	var space := city.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.34
	capsule.height = 1.65
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = 1
	query.exclude = [city.player.get_rid()]
	for x in grid.region.size.x:
		for z in grid.region.size.y:
			var p := origin + Vector2(x, z) * cell
			var ray := PhysicsRayQueryParameters3D.create(Vector3(p.x, ray_top, p.y), Vector3(p.x, ray_bottom, p.y), 1)
			ray.exclude = ground_exclusions
			var floor_hit := space.intersect_ray(ray)
			var blocked: bool = floor_hit.is_empty() or floor_hit.normal.y < 0.72
			if not blocked and not floor_names.is_empty():
				var source_names: Array = floor_hit.collider.get_meta("shape_names", [])
				var source_index: int = floor_hit.get("shape", -1)
				var surface_ok := false
				if source_index >= 0 and source_index < source_names.size():
					for floor_name in floor_names:
						if str(source_names[source_index]).contains(str(floor_name)): surface_ok = true
				blocked = not surface_ok
			if not blocked:
				var clearance := foot_clearance
				for zone in options.get("step_zones", []):
					var box: Array=zone["bounds"]
					if p.x>=box[0] and p.x<=box[1] and p.y>=box[2] and p.y<=box[3]:clearance=float(zone["clearance"])
				query.transform = Transform3D(Basis.IDENTITY, floor_hit.position + Vector3(0, 0.825+clearance, 0))
				blocked = not space.intersect_shape(query, 1).is_empty()
			grid.set_point_solid(Vector2i(x, z), blocked)
			if not blocked:
				floor_heights[Vector2i(x, z)] = float(floor_hit.position.y)
				var names: Array = floor_hit.collider.get_meta("shape_names", [])
				var shape_index: int = floor_hit.get("shape", -1)
				var paved := false
				if shape_index >= 0 and shape_index < names.size():
					for road_name in road_names:
						if str(names[shape_index]).contains(str(road_name)): paved = true
				if not paved:
					grid.set_point_weight_scale(Vector2i(x, z), 3.5)
	ready = true

func nearest_open(p: Vector3) -> Vector2i:
	var wanted := Vector2i(roundi((p.x - origin.x) / cell), roundi((p.z - origin.y) / cell))
	var found := Vector2i(-1, -1)
	var best := INF
	for x in range(wanted.x - 4, wanted.x + 5):
		for z in range(wanted.y - 4, wanted.y + 5):
			var id := Vector2i(x, z)
			if grid.is_in_boundsv(id) and not grid.is_point_solid(id):
				var d := Vector2(id).distance_squared_to(Vector2(wanted))
				if d < best:
					best = d
					found = id
	return found

func path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var result := PackedVector3Array()
	if not ready:
		return result
	var start := nearest_open(from)
	var end := nearest_open(to)
	if start.x < 0 or end.x < 0:
		return result
	for p in grid.get_point_path(start, end):
		var ray := PhysicsRayQueryParameters3D.create(Vector3(p.x, ray_top, p.y), Vector3(p.x, ray_bottom, p.y), 1)
		ray.exclude = ground_exclusions
		var hit := city.get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty():
			result.append(hit.position + Vector3(0, 0.055, 0))
	return result
