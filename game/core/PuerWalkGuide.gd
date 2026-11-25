extends CityWalkGuide
## 保留共用物理采样与高度；普洱简化地面按真实道路中心线加权。
func build(owner_city: Node3D, bounds: Array) -> void:
	super.build(owner_city, bounds)
	var road_data: Dictionary = owner_city.story.get("roads", {})
	var half_width := float(owner_city.story.get("sampling", {}).get("road_half_width", 1.05))
	for x in grid.region.size.x:
		for z in grid.region.size.y:
			var id := Vector2i(x, z)
			if grid.is_point_solid(id): continue
			var p := origin + Vector2(x,z)*cell
			var paved := false
			for road in road_data.values():
				for i in range(1,road.size()):
					var a := Vector2(road[i-1][0],road[i-1][2])
					var b := Vector2(road[i][0],road[i][2])
					if p.distance_to(Geometry2D.get_closest_point_to_segment(p,a,b)) <= half_width:
						paved = true
			grid.set_point_weight_scale(id,1.0 if paved else 3.5)
