extends Node
## 从切入的第一帧检查旁白遮挡，再验证结束、重入、中断和直接运行。
var checks := 0
var failures := 0
var original_save := ""
var watch_id := ""
var old_instance := 0
var watching := false
var frames := 0
var exposed := 0
var audit: Array[Dictionary] = []
var output := OS.get_environment("CITY_ARRIVAL_OUTPUT")
var screenshots := OS.get_cmdline_user_args().has("--screenshots")

func check(ok: bool, message: String) -> void:
	checks += 1
	print("PASS: " if ok else "FAIL: ", message)
	if not ok: failures += 1

func audit_frame() -> void:
	if not watching: return
	var city := get_tree().current_scene
	if city == null or not city is Node3D or city.get_instance_id() == old_instance: return
	if city.get("station_id") != watch_id: return
	frames += 1
	if city.visible or not city.arrival_screen.active or not city.arrival_screen.visible or city.dialogue == null or city.hud.visible or city.player.enabled:
		exposed += 1
		printerr("EXPOSED ", watch_id, " frame=", frames)

func watch(id: String) -> void:
	watch_id = id
	var previous := get_tree().current_scene
	old_instance = previous.get_instance_id() if previous != null else 0
	frames = 0
	exposed = 0
	watching = true

func settle() -> void:
	await get_tree().process_frame
	while SceneRouter.is_switching(): await get_tree().process_frame
	await get_tree().process_frame
	var city := get_tree().current_scene
	if city is Node3D:
		while not city.walk_guide.ready: await get_tree().physics_frame

func finish_talk(city: Node3D) -> void:
	# 逐行完成真实对白，不直接写开场标记。
	var limit := 0
	while city.dialogue != null and limit < 100:
		city.dialogue._continue()
		limit += 1
	check(city.dialogue == null, city.station_id + " 逐行读完旁白")
	await get_tree().process_frame

func shot(name: String) -> void:
	if not screenshots: return
	await get_tree().process_frame
	RenderingServer.force_draw()
	check(get_viewport().get_texture().get_image().save_png(output.path_join(name + ".png")) == OK, "截图 " + name)

func verify_intro(city: Node3D, label: String) -> void:
	audit_frame()
	check(frames > 0 and exposed == 0, label + " 从首帧到转场结束没有地图、HUD或可操作帧")
	check(city.arrival_screen.backdrop.get_child(0) is ColorRect and city.arrival_screen.backdrop.get_child(0).color.a == 1.0, label + " 旁白底色完全不透明")
	check(city.arrival_screen.backdrop.size == get_viewport().get_visible_rect().size, label + " 旁白背景覆盖整个视口")
	check(city.dialogue.dialogue_id == city.story["arrival"] and not city.done("arrival"), label + " 正确开场且未提前记为完成")
	audit.append({"city": city.station_id, "case": label, "frames": frames, "exposed_frames": exposed})

func _ready() -> void:
	get_tree().current_scene = null
	original_save = GameState.save_path
	GameState.save_path = "user://city-arrival-" + DisplayServer.get_name() + "-test.cfg"
	GameState.reset_game()
	GameState.unlocked.assign(["lijiang", "xianggelila", "dali", "puer"])
	get_tree().process_frame.connect(audit_frame)
	_watchdog()
	for id in ["lijiang", "xianggelila", "dali", "puer"]:
		watch(id)
		SceneRouter.goto_station(id)
		await settle()
		var city := get_tree().current_scene
		verify_intro(city, id + " 首次切入")
		var spawn: Vector3 = city.player.position
		for i in 5: await get_tree().physics_frame
		check(Vector2(city.player.position.x, city.player.position.z).distance_to(Vector2(spawn.x, spawn.z)) < 0.01, id + " 旁白期间角色保持原位")
		await shot(id + "-intro")
		watching = false
		await finish_talk(city)
		check(city.done("arrival") and city.visible and not city.arrival_screen.visible and city.hud.visible and city.player.enabled, id + " 读完后显示地图并恢复操作")
		check(not city.guide_path.is_empty() and city.guide_mesh.visible, id + " 读完后金色引路可用")
		await shot(id + "-map")
		SceneRouter.goto_station(id)
		await settle()
		city = get_tree().current_scene
		check(city.visible and city.dialogue == null and not city.arrival_screen.active and city.player.enabled, id + " 完成后再次进入直接显示地图")
		GameState.set_flag("flow/" + id + "/arrival", false)
		watch(id)
		SceneRouter.goto_station(id)
		await settle()
		city = get_tree().current_scene
		verify_intro(city, id + " 未完成存档重入")
		watching = false
		city.dialogue._leave()
		await get_tree().process_frame
		check(not city.done("arrival") and city.visible and city.player.enabled, id + " 中断不误记完成且恢复地图")
		city.interact()
		check(city.dialogue != null and not city.visible and city.arrival_screen.active and not city.hud.visible, id + " E重新阅读仍先遮住地图")
		await finish_talk(city)
		# 直接运行城市场景，没有SceneRouter的黑幕保护。
		SceneRouter.goto_map()
		await settle()
		GameState.set_flag("flow/" + id + "/arrival", false)
		SceneRouter.current_key = "home"
		SceneRouter.params = {"station": "stale-station"}
		watch(id)
		get_tree().change_scene_to_file(ContentDB.station(id)["map_scene"])
		await settle()
		city = get_tree().current_scene
		verify_intro(city, id + " 直接运行场景")
		watching = false
		await finish_talk(city)
		# 开场中离开整个城市，再进入应重新从旁白开始。
		GameState.set_flag("flow/" + id + "/arrival", false)
		SceneRouter.goto_station(id)
		await settle()
		SceneRouter.goto_map()
		await settle()
		check(not GameState.has_flag("flow/" + id + "/arrival"), id + " 旁白中离开整座城市不误记完成")
		watch(id)
		SceneRouter.goto_station(id)
		await settle()
		city = get_tree().current_scene
		verify_intro(city, id + " 离开后再进入")
		watching = false
		await finish_talk(city)
	if not output.is_empty():
		var file := FileAccess.open(output.path_join("frame-audit.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(audit, "  "))
	GameState.save_path = original_save
	GameState.load_game()
	print("CITY_ARRIVAL_TEST checks=", checks, " failures=", failures)
	get_tree().quit(1 if failures else 0)

func _watchdog() -> void:
	await get_tree().create_timer(150.0).timeout
	printerr("CITY_ARRIVAL_TEST TIMEOUT")
	GameState.save_path = original_save
	GameState.load_game()
	get_tree().quit(2)
