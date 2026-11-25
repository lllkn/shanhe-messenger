extends Node
var failures := 0
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", message)
	else:
		print("PASS: ", message)
func settle() -> void:
	await get_tree().process_frame
	while SceneRouter.is_switching():
		await get_tree().process_frame
	await get_tree().process_frame
func wait_physics(count: int = 35) -> void:
	for i in count:
		await get_tree().physics_frame
func key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
func finish_talk(city: Node3D) -> void:
	var guard := 0
	while city.dialogue != null and guard < 250:
		var stage = city.dialogue.get("lijiang_stage")
		if stage != null and stage.blocks_continue():
			await get_tree().process_frame
			stage.slider.grab_focus()
			key(KEY_END, true)
			await get_tree().process_frame
			key(KEY_END, false)
			await get_tree().process_frame
			if not stage.zoomed:
				var zoom_press := InputEventMouseButton.new()
				zoom_press.button_index = MOUSE_BUTTON_LEFT
				zoom_press.pressed = true
				zoom_press.position = stage.zoom_button.get_global_rect().get_center()
				get_viewport().push_input(zoom_press, true)
				await get_tree().process_frame
				zoom_press.pressed = false
				get_viewport().push_input(zoom_press, true)
				await get_tree().process_frame
			var press := InputEventMouseButton.new()
			press.button_index = MOUSE_BUTTON_LEFT
			press.pressed = true
			press.position = stage.confirm_button.get_global_rect().get_center()
			get_viewport().push_input(press,true)
			await get_tree().process_frame
			var release := InputEventMouseButton.new()
			release.button_index = MOUSE_BUTTON_LEFT
			release.position = press.position
			get_viewport().push_input(release,true)
			await get_tree().process_frame
			check(stage.photo_brightness >= 70 and stage.confirmed,"真实按键调亮、放大手机并点击展示照片")
			if not stage.confirmed:
				printerr("PHONE_CHECK brightness=",stage.photo_brightness," button=",stage.confirm_button.get_global_rect())
				return
		city.dialogue._continue()
		guard += 1
	await get_tree().process_frame
func _ready() -> void:
	get_tree().current_scene = null
	var actual_save: String = GameState.save_path
	GameState.save_path = "user://city-test.cfg"
	GameState.reset_game()
	SceneRouter.goto_map()
	await settle()
	var overview := get_tree().current_scene
	SceneRouter.goto_station("dali")
	check(get_tree().current_scene == overview and GameState.current_station.is_empty(), "锁定城市不能进入")
	# 真实长卷入口
	overview._canvas._markers[0].pressed.emit()
	overview._detail.get_child(-1).pressed.emit()
	await settle()
	check(SceneRouter.current_key == "city" and get_tree().current_scene.station_id == "lijiang", "走进丽江直接进入3D，不经过站点菜单")
	for st in GameState.stations:
		var id: String = st["id"]
		if not GameState.is_unlocked(id):
			GameState.unlocked.append(id)
		SceneRouter.goto_station(id)
		await settle()
		var city := get_tree().current_scene
		await wait_physics()
		await finish_talk(city)
		check(city.station_id == id and city.map_root != null and city.camera.current, id + " 地图、玩家、相机接入")
		check(Vector2(city.player.position.x, city.player.position.z).distance_to(Vector2(city.spawn_position.x, city.spawn_position.z)) < 0.15, id + " 位于指定出生点")
		check(city.player.is_on_floor() and city.player.position.y > -0.6, id + " 出生点真实落在地面碰撞上")
		check(GameState.get_fragment_count() == 0 and not GameState.is_puzzle_solved(id), id + " 进入地图不发碎片不完成手艺")
		check(not city.can_interact(), id + " 出生点不能远程启动故事")
		var start: Vector3 = city.player.position
		key(KEY_W, true)
		await wait_physics(12)
		key(KEY_W, false)
		await wait_physics(3)
		check(Vector2(city.player.position.x, city.player.position.z).distance_to(Vector2(start.x, start.z)) > 0.12, id + " WASD真实移动")
		var ray := PhysicsRayQueryParameters3D.create(city.player.position + Vector3(0, 3, 0), city.player.position + Vector3(0, -2, 0), 1)
		check(not city.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(), id + " 出生街道有实体碰撞")
		GameUI.open_pause()
		var stopped: Vector3 = city.player.position
		await get_tree().create_timer(0.1).timeout
		check(city.player.position == stopped and get_tree().paused, id + " 暂停冻结玩家")
		GameUI.close_modal()
		city.player.position.y = -4
		await wait_physics(4)
		check(city.player.position.y > -0.6, id + " 越界恢复安全位置")
		if OS.get_cmdline_user_args().has("--screenshots"):
			if is_instance_valid(GameUI._toast):
				GameUI._toast.queue_free()
			await wait_physics(10)
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://../drafts/city-integration-2026-10-09/%s-spawn.png" % id)
		city.player.position = city.spawn_position + Vector3(1, 0.2, 0)
		var location: Vector3 = city.player.position
		SceneRouter.goto_codex()
		await settle()
		get_tree().current_scene._back()
		await settle()
		city = get_tree().current_scene
		check(SceneRouter.current_key == "city" and city.station_id == id and city.player.position.distance_to(location) < 0.8, id + " 图鉴返回原城市原地点")
		if id in ["lijiang", "xianggelila", "dali", "puer"]:
			for item in city.story["interviews"]: GameState.set_flag("clue/"+id+"/" + item["id"])
			city._refresh_progress()
		var visit_step := ""
		if id in ["lijiang", "xianggelila", "dali", "puer"]:
			visit_step = city.story["visit_step"]
			# 通用外壳测试不假设每城门外都是+Z；真实实走另由各城链路测试负责。
			for j in 12:
				var angle := float(j)*TAU/12.0
				city.player.position = city.goal_position+Vector3(cos(angle)*1.3,0.1,sin(angle)*1.3)
				if city.can_interact(): break
		else:
			city.player.position = city.goal_position+Vector3(0,0.2,1)
		city.player.velocity = Vector3.ZERO
		check(city.can_interact(), id + " 目标锚点可交互")
		key(KEY_E, true)
		key(KEY_E, false)
		await settle()
		if id in ["lijiang", "xianggelila", "dali", "puer"]:
			check(city.dialogue != null, "地图地点按E触发本站场内对话")
			await finish_talk(city)
			await settle()
			check(SceneRouter.current_key.begins_with("puzzle_") and GameState.has_flag("flow/"+id+"/"+visit_step), "核心对话结束自动进入小游戏，完成步骤保留")
		if id != "gucheng":
			check(SceneRouter.current_key.begins_with("puzzle_"), id + " 地图内触发本站真实小游戏")
		if id == "gucheng":
			check(SceneRouter.current_key == "city" and city.dialogue != null and GameState.get_fragment_count() == 0, "古城按E进入线性对话，不进入拼锦")
			if city.dialogue != null: city.dialogue._leave()
			check(not GameState.is_completed("gucheng"), "古城交谈中断不提前完成")
			SceneRouter.goto_map()
			await settle()
			continue
		var puzzle := get_tree().current_scene
		puzzle._exit()
		await settle()
		check(SceneRouter.current_key == "city" and get_tree().current_scene.station_id == id and get_tree().current_scene.can_interact() and GameState.get_fragment_count() == 0, id + " 中途退出返回原地点不领奖")
		SceneRouter.goto_map()
		await settle()
		check(SceneRouter.current_key == "map", id + " 可以返回长卷")
	# 已有真实东巴小游戏解法验证奖励和地图返回。
	SceneRouter.goto_station("lijiang")
	await settle()
	var city := get_tree().current_scene
	city.player.position = city.goal_position + Vector3(0, 0.2, 1.0)
	city.interact()
	await settle()
	var puzzle := get_tree().current_scene
	puzzle._on_intro_start()
	puzzle._level = 2
	puzzle._l1_root.visible = false
	puzzle._l2_root.visible = true
	for pid in puzzle._page_correct_order:
		puzzle._slots[int(puzzle._page_correct_order[pid]) - 1]["page_id"] = pid
	puzzle._refresh_submit()
	puzzle._on_submit()
	await get_tree().create_timer(2.25).timeout
	check(GameState.has_flag("flow/lijiang/glyph") and not GameState.has_fragment("frag_dongba_tea"), "地图内小游戏真实通过，收尾前不领取碎片")
	puzzle._back_to_map()
	await settle()
	city = get_tree().current_scene
	await finish_talk(city)
	check(SceneRouter.current_key == "city" and GameState.has_fragment("frag_dongba_tea") and GameState.is_completed("lijiang"), "完成小游戏回原地图，收尾后获得碎片")
	GameState.save_path = actual_save
	GameState.load_game()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://city-test.cfg"))
	print("CITY_TEST checks=", checks, " failures=", failures)
	GameMusic.stop()
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(failures)
