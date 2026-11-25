class_name CityRouteGuide
extends RefCounted
## 四城共用引路：保留整条路线，沿路只更新进度，持续偏离才重规划。
const GOLD := Color(1.0, 0.80, 0.31, 0.93)
const SPACING := 1.3
const OFF_ROUTE_DISTANCE := 1.8
const OFF_ROUTE_DELAY := 0.75
const RETRY_DELAY := 1.0
var route := PackedVector3Array()
var lengths := PackedFloat32Array()
var progress := 0.0
var remaining_distance := 0.0
var revision := 0
var target := ""
var destination := Vector3.INF
var off_route_time := 0.0
var retry_time := 0.0
var sample_time := 0.0
var last_attempt := Vector3.INF
var arrived := false
var markers: Array[PackedVector3Array] = []
var marker_distances := PackedFloat32Array()
var visible_from := -1

func create_mesh() -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = "WalkRoute"
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = GOLD
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var surface_pass := ShaderMaterial.new()
	surface_pass.shader = preload("res://core/CityRouteSurface.gdshader")
	surface_pass.set_shader_parameter("guide_color", GOLD)
	surface_pass.render_priority = 1
	material.next_pass = surface_pass
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance

func update(city: Node3D, delta: float = 0.0, force: bool = false) -> void:
	if city.guide_mesh == null or not city.walk_guide.ready: return
	var item: Dictionary = {}
	for hotspot in city.hotspots:
		if hotspot["id"] == city.target_id:
			item = hotspot
			break
	if GameState.is_completed(city.station_id) or item.is_empty():
		if not route.is_empty() or target != "":
			_clear(city)
		return
	var changed: bool = target != city.target_id or destination != item["position"]
	retry_time = maxf(0.0, retry_time - delta)
	sample_time += delta
	if changed or force:
		target = city.target_id
		destination = item["position"]
		arrived = false
		_plan(city)
	elif delta > 0.0 and sample_time < 0.15:
		return
	var elapsed := sample_time
	sample_time = 0.0
	if route.is_empty():
		# 无路时不以每帧重试；移动到新位置后再尝试。
		if retry_time <= 0.0 and _flat(city.player.position - last_attempt).length() > 0.6:
			_plan(city)
		return
	var projection := _project(city.player.position)
	if projection.y > OFF_ROUTE_DISTANCE:
		off_route_time += elapsed
		if off_route_time >= OFF_ROUTE_DELAY and retry_time <= 0.0:
			_plan(city)
			if route.is_empty(): return
			projection = _project(city.player.position)
	else:
		off_route_time = 0.0
	progress = projection.x
	remaining_distance = maxf(0.0, lengths[-1] - progress)
	remaining_distance += _flat(route[-1] - destination).length()
	# 小地图收起走过的路线；世界中的剩余箭头仍使用原来的顶点。
	var remaining := PackedVector3Array([_point(progress)])
	for i in range(1, route.size()):
		if lengths[i] > progress + 0.01: remaining.append(route[i])
	city.guide_path = remaining
	_draw_remaining(city)
	city.minimap.queue_redraw()

func _plan(city: Node3D) -> void:
	last_attempt = city.player.position
	route = city.walk_guide.path(city.player.position, destination)
	lengths = PackedFloat32Array([0.0])
	for i in range(1, route.size()):
		lengths.append(lengths[-1] + _flat(route[i] - route[i-1]).length())
	progress = 0.0
	off_route_time = 0.0
	retry_time = RETRY_DELAY
	revision += 1
	markers.clear()
	marker_distances.clear()
	visible_from = -1
	# 从终点倒排，路标固定在保留的整条路径上。
	if route.size() > 1:
		var at := lengths[-1] - 0.85
		while at > 0.5:
			var center := _point(at) + Vector3(0, 0.035, 0)
			var forward := (_point(minf(at + 0.25, lengths[-1])) - _point(maxf(0.0, at - 0.25))).normalized()
			var side := forward.cross(Vector3.UP).normalized()
			var tip := center + forward * 0.32
			var rear := center - forward * 0.14
			var arrow := PackedVector3Array([tip, rear-side*0.24, center-forward*0.02, tip, center-forward*0.02, rear+side*0.24])
			var outlined := PackedVector3Array()
			# 静态深色细边，浅石板路和草地上都能认清箭头。
			for vertex in arrow:
				var offset := vertex - center
				outlined.append(center + Vector3(offset.x*1.22, offset.y-0.006, offset.z*1.22))
			outlined.append_array(arrow)
			markers.push_front(outlined)
			marker_distances.insert(0, at)
			at -= SPACING
	city.guide_path = route.duplicate()
	if route.is_empty():
		remaining_distance = 0.0
		city.guide_mesh.mesh = ImmediateMesh.new()
		city.minimap.queue_redraw()

func _project(position: Vector3) -> Vector2:
	var closest := INF
	var at := 0.0
	for i in range(1, route.size()):
		var a := _flat(route[i-1])
		var b := _flat(route[i])
		var segment := b - a
		var fraction := clampf((_flat(position)-a).dot(segment) / maxf(segment.length_squared(), 0.0001), 0.0, 1.0)
		var distance := _flat(position).distance_to(a.lerp(b, fraction))
		# 跨桥和台阶使用本段高度，跳跃不会触发重规划。
		if absf(position.y - lerpf(route[i-1].y, route[i].y, fraction)) > 1.8: continue
		if distance < closest:
			closest = distance
			at = lerpf(lengths[i-1], lengths[i], fraction)
	if route.size() == 1:
		closest = _flat(position-route[0]).length()
	return Vector2(at, closest)

func _point(at: float) -> Vector3:
	for i in range(1, lengths.size()):
		if at <= lengths[i]:
			return route[i-1].lerp(route[i], (at-lengths[i-1]) / maxf(0.001, lengths[i]-lengths[i-1]))
	return route[-1]

func _draw_remaining(city: Node3D) -> void:
	var first := 0
	while first < markers.size() and marker_distances[first] < progress + 0.65:
		first += 1
	if first == visible_from: return
	visible_from = first
	var mesh := ImmediateMesh.new()
	if first < markers.size():
		mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in range(first, markers.size()):
			for j in markers[i].size():
				mesh.surface_set_color(Color(0.14, 0.14, 0.14) if j < 6 else Color.WHITE)
				mesh.surface_add_vertex(markers[i][j])
		mesh.surface_end()
	city.guide_mesh.mesh = mesh

func visible(city: Node3D, nearby: Dictionary) -> bool:
	if GameState.is_completed(city.station_id) or city.dialogue != null or city.reward_panel != null or route.is_empty(): return false
	if nearby.get("id", "") == target:
		arrived = true
	elif arrived:
		for item in city.hotspots:
			if item["id"] == target:
				if _flat(city.player.position - destination).length() > float(item["radius"]) + 0.6:
					arrived = false
	return not arrived

func hint_text(place: String) -> String:
	if route.is_empty(): return "暂未找到可走路线 → %s · 移回街道后继续引路" % place
	if arrived: return "已到达 %s · 靠近人物按 E 交谈" % place
	return "跟随金色路标 → %s · 沿路约 %.0f 米" % [place, remaining_distance]

func _clear(city: Node3D) -> void:
	route.clear()
	lengths.clear()
	markers.clear()
	marker_distances.clear()
	city.guide_path.clear()
	city.guide_mesh.mesh = ImmediateMesh.new()
	target = ""
	destination = Vector3.INF
	remaining_distance = 0.0
	arrived = false
	city.minimap.queue_redraw()

func _flat(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)
