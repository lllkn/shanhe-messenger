extends Node
## 真实四城路网验证：路线稳定、路标顶点固定、偏离重算、目标与完成状态。
var failures := 0
var checks := 0
var original_save := ""
var screenshots := OS.get_cmdline_user_args().has("--screenshots")
var output := OS.get_environment("CITY_GUIDE_OUTPUT")

func check(ok: bool, message: String) -> void:
	checks += 1
	print("PASS: " if ok else "FAIL: ", message)
	if not ok: failures += 1

func settle() -> void:
	await get_tree().process_frame
	while SceneRouter.is_switching(): await get_tree().process_frame
	await get_tree().process_frame

func vertices(city: Node3D) -> PackedVector3Array:
	if city.guide_mesh.mesh.get_surface_count() == 0: return PackedVector3Array()
	return city.guide_mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]

func sample(city: Node3D, pos: Vector3, delta: float = 0.16) -> void:
	city.player.position = pos
	city.route_guide.update(city, delta)

func deviation(city: Node3D) -> Vector3:
	var grid: AStarGrid2D = city.walk_guide.grid
	for x in grid.region.size.x:
		for z in grid.region.size.y:
			var id := Vector2i(x, z)
			if grid.is_point_solid(id): continue
			var p: Vector2 = city.walk_guide.origin + Vector2(x,z) * city.walk_guide.cell
			var point := Vector3(p.x, city.walk_guide.floor_heights[id] + 0.05, p.y)
			var distance: float = city.route_guide._project(point).y
			if distance > 2.3 and distance < 3.5 and not city.walk_guide.path(point, city.route_guide.destination).is_empty(): return point
	return Vector3.INF

func shot(city: Node3D, name: String) -> void:
	if not screenshots: return
	city.camera_initialized = false
	city._update_camera()
	# 保留游戏的镜头碰撞，只在截图被墙缩到人物身上时转到开阔角度。
	if city.camera.position.distance_to(city.player.position) < 4.0:
		var best_yaw: float = city.yaw
		var best_distance := 0.0
		for i in 12:
			city.yaw = float(i)*TAU/12.0
			city.camera_initialized = false
			city._update_camera()
			var camera_distance: float = city.camera.position.distance_to(city.player.position)
			if camera_distance > best_distance:
				best_distance = camera_distance
				best_yaw = city.yaw
		city.yaw = best_yaw
		city.camera_initialized = false
		city._update_camera()
	city.guide_mesh.visible = city.route_guide.visible(city, city.near_hotspot())
	city.hint.text = city.route_guide.hint_text(city.hotspots[0]["place"])
	city._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	GameUI.clear_notification()
	await get_tree().process_frame
	RenderingServer.force_draw()
	check(get_viewport().get_texture().get_image().save_png(output.path_join(name + ".png")) == OK, "截图 " + name)

func _ready() -> void:
	get_tree().current_scene = null
	original_save = GameState.save_path
	GameState.save_path = "user://city-guide-test.cfg"
	GameState.reset_game()
	GameState.unlocked.assign(["lijiang", "xianggelila", "dali", "puer"])
	for id in ["lijiang", "xianggelila", "dali", "puer"]:
		GameState.set_flag("flow/"+id+"/arrival")
		SceneRouter.goto_station(id)
		await settle()
		var city := get_tree().current_scene
		while not city.walk_guide.ready: await get_tree().physics_frame
		city.set_process(false)
		city.player.enabled = false
		var start: Vector3 = city.player.position
		city._update_route(true)
		var guide: CityRouteGuide = city.route_guide
		var canonical := guide.route.duplicate()
		var revision := guide.revision
		var original_vertices := vertices(city)
		check(canonical.size() > 1 and not original_vertices.is_empty(), id + " 真实街道生成方向箭头")
		check(city.guide_mesh.material_override.albedo_color == CityRouteGuide.GOLD, id + " 共用金色、大小、间距和材质")
		await shot(city, id + "-start")
		for i in 12:
			sample(city, start + Vector3(sin(i)*0.18, 0, cos(i)*0.18))
		check(guide.revision == revision and guide.route == canonical, id + " 原地晃动不重规划")
		sample(city, start + Vector3(0, 1.1, 0))
		check(guide.revision == revision, id + " 跳跃不重规划")
		var stable := true
		var anchored := true
		var previous := guide.remaining_distance
		var decreasing := true
		for i in range(1, canonical.size()):
			sample(city, canonical[i])
			stable = stable and guide.revision == revision and guide.route == canonical
			for vertex in vertices(city):
				if not original_vertices.has(vertex): anchored = false
			decreasing = decreasing and guide.remaining_distance <= previous + 0.01
			previous = guide.remaining_distance
		check(stable, id + " 沿整条路线前进不重规划")
		check(anchored, id + " 剩余箭头世界顶点固定不跳动")
		check(decreasing and city.guide_path.size() <= 2, id + " 小地图收起走过路段，沿路距离递减")
		sample(city, canonical[canonical.size()/2])
		check(guide.revision == revision and city.guide_path.size() > 2, id + " 原路返回可恢复路标与小地图")
		await shot(city, id + "-middle")
		var off := deviation(city)
		check(off != Vector3.INF, id + " 找到真实可走的岔路用于偏离测试")
		if off != Vector3.INF:
			# 短暂偏离又回来，不切换整条路径。
			sample(city, off, 0.3)
			sample(city, canonical[0], 0.16)
			check(guide.revision == revision, id + " 短暂偏离不重算")
			for i in 60: sample(city, off, 1.0/60.0)
			check(guide.revision == revision+1 and not city.guide_path.is_empty(), id + " 持续偏离后重算一次，仍到原目标")
			var after := guide.revision
			for i in 20: sample(city, off)
			check(guide.revision == after, id + " 重算后站立不连续重算")
		# 所有本城可选地点使用同一规则；核心目标先满足原有走访条件。
		for interview in city.story["interviews"]: GameState.set_flag("clue/"+id+"/"+interview["id"])
		for item in city.hotspots:
			sample(city, start)
			city.select_target(item["id"])
			check(guide.target == item["id"] and guide.route.size() > 1, id + " 可引路到 " + item["id"])
			var same := guide.revision
			city.select_target(item["id"])
			check(guide.revision == same, id + " 重选同目标不重排 " + item["id"])
		city.select_target(city.hotspots[0]["id"])
		var target: Dictionary = city.hotspots[0]
		sample(city, guide.route[-1])
		check(not guide.visible(city, target), id + " 到达目标收起引路")
		sample(city, target["position"] + Vector3(float(target["radius"])+0.2, 0, 0))
		check(not guide.visible(city, {}), id + " 到达边缘不闪烁")
		sample(city, start)
		check(guide.visible(city, {}), id + " 离开目标恢复引路")
		# 无路径时明确告知并清掉旧线；回到街道会恢复，不持续重试。
		city.player.position = Vector3(1000, 0, 1000)
		city._update_route(true)
		var failed_attempt := guide.revision
		for i in 20: sample(city, city.player.position)
		check(city.guide_path.is_empty() and vertices(city).is_empty() and guide.hint_text(target["place"]).contains("暂未找到") and guide.revision == failed_attempt, id + " 无路线反馈明确且站立不重试")
		for i in 8: sample(city, start)
		check(not city.guide_path.is_empty(), id + " 回到街道后恢复引路")
		city.open_conversation(city.story["arrival"], "repeat")
		check(not guide.visible(city, {}), id + " 对话期间隐藏引路")
		city.dialogue._leave()
		await get_tree().process_frame
		# 最后一项：完成城市后，世界和小地图都清掉引路。
		GameState.collect_fragment(city.story["fragment"])
		city._update_route()
		check(city.guide_path.is_empty() and city.guide_mesh.mesh.get_surface_count() == 0 and not guide.visible(city, {}), id + " 完成后清除世界和小地图引路")
	GameState.save_path = original_save
	GameState.load_game()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://city-guide-test.cfg"))
	print("CITY_GUIDE_TEST checks=", checks, " failures=", failures)
	get_tree().quit(failures)
