extends Node
var failures := 0
var checks := 0
var original_save := ""
func check(ok: bool, message: String) -> void:
	checks += 1
	print("PASS: " if ok else "FAIL: ", message)
	if not ok: failures += 1
func settle() -> void:
	await get_tree().process_frame
	while SceneRouter.is_switching(): await get_tree().process_frame
	await get_tree().process_frame
func physics(frames: int = 4) -> void:
	for i in frames: await get_tree().physics_frame
func key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
func mouse_motion(relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.relative = relative
	event.screen_relative = relative
	get_viewport().push_input(event, true)
func mouse_captured(city: Node3D) -> bool:
	# Dummy DisplayServer没有原生鼠标捕获，窗口版本另验证实际模式。
	return city.mouse_look and city.window_focused and (DisplayServer.get_name() == "headless" or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)
func city_ready() -> Node3D:
	await settle()
	var city := get_tree().current_scene
	while not city.walk_guide.ready: await get_tree().physics_frame
	await get_tree().process_frame
	return city
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
	if is_instance_valid(city) and city.reward_panel is ClueCard:
		city.reward_panel.close_button.pressed.emit()
		for frame_index in 4: await get_tree().process_frame
		if city.dialogue != null: await finish_talk(city)

func teleport(city: Node3D, pos: Vector3) -> void:
	city.player.position = pos + Vector3(0, 0.1, 0)
	city.player.velocity = Vector3.ZERO
	await physics(8)
func walk(city: Node3D, target: Vector3, message: String) -> void:
	var route: PackedVector3Array = city.walk_guide.path(city.player.position, target)
	check(not route.is_empty(), message + " 有物理可达引导路径")
	var stuck := false
	var start_time := Time.get_ticks_msec()
	key(KEY_W, true)
	for point in route:
		var frames := 0
		while Vector2(city.player.position.x - point.x, city.player.position.z - point.z).length() > 0.22 and frames < 100:
			var direction: Vector3 = point - city.player.position
			city.yaw = atan2(-direction.x, -direction.z)
			await get_tree().physics_frame
			frames += 1
		if frames >= 100:
			printerr("STUCK ", message, " at ", city.player.position, " wanted ", point)
			stuck = true
			break
	key(KEY_W, false)
	await physics(3)
	check(not stuck and city.player.position.distance_to(target) < 1.5, message + " 真实WASD连续步行抵达")
	print("WALK elapsed_ms=", Time.get_ticks_msec() - start_time, " points=", route.size())
func _ready() -> void:
	get_tree().current_scene = null
	original_save = GameState.save_path
	_watchdog()
	GameState.save_path = "user://lijiang-chain-test.cfg"
	GameState.reset_game()
	SceneRouter.goto_station("lijiang")
	var city := await city_ready()
	await physics(25)
	check(city.player.is_on_floor(), "出生点落地，无掉落或抖动")
	check(city.dialogue != null and city.dialogue.dialogue_id == "lijiang_arrival", "出生点自动播放指定开场旁白")
	check(not city.player.enabled and GameState.get_fragment_count() == 0, "旁白期间冻结移动，不发奖励")
	check(city.dialogue.lines[0]["text"] == "丽江到了，正好带着馆里的古锦照片，先去街上问问，看有没有人认得这些纹样。", "开场文本与用户稿一致")
	check(city.dialogue._name_chip.visible and city.dialogue._name_label.text == "旁白", "旁白显示旁白姓名卡")
	check(city.dialogue._text_label.get_theme_font_size("normal_font_size") == 36, "对话正文采用放大字号")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "旁白自动释放光标")
	var before_yaw: float = city.yaw
	mouse_motion(Vector2(50, 20))
	check(is_equal_approx(city.yaw, before_yaw), "对话时鼠标不转视角")
	city.dialogue.find_children("*", "Button", true, false)[0].grab_focus()
	await get_tree().process_frame
	key(KEY_SPACE, true)
	await get_tree().process_frame
	key(KEY_SPACE, false)
	await get_tree().process_frame
	check(city.dialogue != null and city.dialogue.line_idx == 0 and not city.dialogue._typing, "退出按钮有焦点时，空格仍补全文字")
	city.dialogue._leave()
	await get_tree().process_frame
	check(not city.done("arrival") and city.player.enabled, "关闭开场不记完成，可按E恢复")
	city.interact()
	key(KEY_SPACE, true)
	await get_tree().process_frame
	key(KEY_SPACE, false)
	await get_tree().process_frame
	key(KEY_SPACE, true)
	await physics(3)
	check(city.dialogue == null and city.done("arrival"), "第二次空格继续并完成开场")
	check(city.player.velocity.y <= 0 and city.player.is_on_floor(), "空格结束对话后保持按住不会误跳")
	key(KEY_SPACE, false)
	check(city.done("arrival") and city.clue_count() == 0, "认领任务后才进入访谈")
	# 自动运行窗口可能在后台，明确发送窗口激活通知验证捕获状态。
	city._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)
	await get_tree().process_frame
	check(mouse_captured(city), "探索自动进入鼠标直接转视角")
	before_yaw = city.yaw
	mouse_motion(Vector2(50, 20))
	check(is_equal_approx(city.yaw, before_yaw - 0.15 * GameSettings.camera_sensitivity), "无需鼠标按键，真实鼠标事件旋转视角")
	key(KEY_TAB, true)
	await get_tree().process_frame
	key(KEY_TAB, false)
	await get_tree().process_frame
	check(not city.mouse_look and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Tab显示光标供任务和小地图点击")
	before_yaw = city.yaw
	mouse_motion(Vector2(50, 20))
	check(is_equal_approx(city.yaw, before_yaw), "光标操作时鼠标不会转镜头")
	city.checklist.get_child(0).grab_focus()
	key(KEY_TAB, true)
	await get_tree().process_frame
	key(KEY_TAB, false)
	await get_tree().process_frame
	check(mouse_captured(city), "按钮有焦点时Tab仍能返回转视角")
	GameUI.open_pause()
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "暂停释放光标")
	GameUI.close_modal()
	await get_tree().process_frame
	check(mouse_captured(city), "继续旅程恢复鼠标转视角")
	city._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	before_yaw = city.yaw
	mouse_motion(Vector2(50, 20))
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and is_equal_approx(before_yaw, city.yaw), "窗口失焦释放光标且不转视角")
	city._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)
	await get_tree().process_frame
	check(mouse_captured(city), "窗口恢复激活后恢复探索鼠标模式")
	key(KEY_R, true)
	key(KEY_R, false)
	await get_tree().process_frame
	check(city.hotspots.size() == 4 and city.minimap.floor_texture != null, "四名NPC与真实物理小地图存在")
	check(city.distance == 12 and is_equal_approx(city.pitch, 0.70) and city.camera.fov == 50, "丽江专用主视角参数生效")
	check(city.camera.position.distance_to(city.player.position + Vector3(0, 0.8, 0)) > 11.0, "入口斜俯视镜头保持街道纵深，不被后墙挤近")
	var wheel := city.map_root.find_child("Waterwheel_axle", true, false) as Node3D
	var wheel_query := PhysicsPointQueryParameters3D.new()
	wheel_query.position = Vector3(wheel.global_position.x, 0.4, wheel.global_position.z)
	wheel_query.collision_mask = 1
	var wheel_blocked := false
	for hit in city.get_world_3d().direct_space_state.intersect_point(wheel_query):
		if hit["collider"].name == "TownBoundary": wheel_blocked = true
	check(wheel_blocked, "固定水车底座阻挡位于模型实际坐标")
	if OS.get_environment("LIJIANG_INPUT_ONLY") == "1":
		_restore_save()
		print("LIJIANG_INPUT_TEST checks=",checks," failures=",failures," renderer=",DisplayServer.get_name())
		get_tree().quit(failures)
		return
	# 提前拜访不可绕过访谈。
	await teleport(city, city.goal_position + Vector3(0, 0, 1.3))
	city.interact()
	check(city.dialogue == null and not city.done("dongba_visit"), "未齐三线索不能提前触发核心剧情")
	await teleport(city, city.spawn_position)
	# 实际走访银饰、小学生、客栈；中途结束/重复访谈不重复计数。
	for id in ["silver", "student", "inn"]:
		var item: Dictionary
		for point in city.hotspots:
			if point["id"] == id: item = point
		await walk(city, item["position"], "出生点/上一访谈 → " + item["name"])
		check(city.near_hotspot().get("id", "") == id, item["name"] + " 到位可按E交互")
		await get_tree().process_frame
		check(city.interaction_prompt.visible and city.interaction_text.text == "E 对话", item["name"] + " 人物旁显示E对话")
		check(city.interaction_prompt.size.x >= 110 and city.interaction_prompt.size.y <= 60, "人物旁交互提示保持横排可读")
		city.interact()
		check(not city.interaction_prompt.is_visible_in_tree(), "对话时隐藏地图交互提示")
		check(city.dialogue != null and city.dialogue.dialogue_id == item["dialogue"], item["name"] + " 播放正确对话")
		if city.dialogue == null:
			await teleport(city, item["position"] + Vector3(0, 0, 1.2))
			city.interact()
		if id == "silver":
			city.dialogue._continue()
			city.dialogue._leave()
			await get_tree().process_frame
			check(city.clue_count() == 0, "访谈读一半退出不发线索")
			city.interact()
		await finish_talk(city)
		var count: int = city.clue_count()
		check(GameState.has_flag("clue/lijiang/" + id), item["name"] + " 完整对话才发线索")
		city.interact()
		await finish_talk(city)
		check(city.clue_count() == count, item["name"] + " 重温不重复计数")
	check(city.clue_count() == 3 and city.done("interviews") and city.target_id == "dongba", "三线索齐全，引导自动转向东巴院")
	GameState.load_game()
	check(city.clue_count() == 3, "存档重载保留三处访谈")
	await walk(city, city.goal_position, "客栈 → 东巴院")
	city.interact()
	check(city.dialogue != null and city.dialogue.lines.size() == 33, "阿东巴完整核心对话33行接入")
	city.dialogue._leave()
	await get_tree().process_frame
	check(not city.done("dongba_visit"), "核心对话中途退出不跳过剧情")
	var position: Vector3 = city.player.position
	var camera_yaw: float = city.yaw
	city.interact()
	await finish_talk(city)
	check(GameState.has_flag("flow/lijiang/dongba_visit") and JourneyFlow.next_step("lijiang").get("id") == "glyph", "同意认字后开启小游戏")
	await settle()
	var puzzle := get_tree().current_scene
	check(SceneRouter.current_key == "puzzle_glyph" and SceneRouter.params.get("defer_reward", false), "核心对话结束自动进入真实小游戏，无需再按E")
	puzzle._exit()
	city = await city_ready()
	check(city.player.position.distance_to(position) < 0.3 and absf(city.yaw-camera_yaw) < 0.01, "小游戏退出回原地点、原视角")
	check(GameState.get_fragment_count() == 0 and not city.done("glyph"), "小游戏中途退出不记过关、不发碎片")
	city.interact()
	await settle()
	puzzle = get_tree().current_scene
	puzzle._on_intro_start()
	await get_tree().create_timer(0.7).timeout
	for i in 6:
		puzzle._on_pick(puzzle._pair_of_glyph[puzzle._current_glyph])
		await get_tree().create_timer(1.5).timeout
	await get_tree().create_timer(0.8).timeout
	check(puzzle._l1_result_layer != null and not puzzle._finished and GameState.get_fragment_count() == 0, "真实完成6对字卡，阶段结算不发奖励")
	puzzle._continue_to_level2()
	await get_tree().create_timer(0.8).timeout
	check(puzzle._level == 2, "进入残页归序第二关")
	for pid in puzzle._page_correct_order:
		var page: TextureRect = puzzle._pages[pid]
		page.position = puzzle._slots[int(puzzle._page_correct_order[pid]) - 1]["rect"].position
		puzzle._drop_page(page)
	puzzle._on_submit()
	await get_tree().create_timer(2.3).timeout
	check(puzzle._finished and GameState.has_flag("flow/lijiang/glyph"), "真实拖放残页、拼合通过，保存整理完成")
	check(GameState.get_fragment_count() == 0 and not GameState.is_unlocked("xianggelila"), "两关通过但收尾前不领碎片、不解锁下一站")
	puzzle._back_to_map()
	city = await city_ready()
	check(city.dialogue != null and city.dialogue.dialogue_id == "lijiang_dongba_farewell", "小游戏结束自动接阿东巴核对与丹增引线")
	city.dialogue._leave()
	await get_tree().process_frame
	check(GameState.get_fragment_count() == 0 and not city.done("farewell"), "收尾中途退出不领奖")
	SceneRouter.goto_map()
	await settle()
	SceneRouter.goto_station("lijiang")
	city = await city_ready()
	check(city.dialogue != null and city.done("glyph"), "重新进入保留小游戏成果并恢复未完成收尾")
	await finish_talk(city)
	check(GameState.has_fragment("frag_dongba_tea") and GameState.is_completed("lijiang") and GameState.is_unlocked("xianggelila"), "收尾结束领取碎片、完成丽江、解锁香格里拉")
	check(city.reward_panel != null and city.done("farewell"), "碎片与下一站提示卡出现")
	city.reward_panel.get_parent().queue_free()
	city.reward_panel = null
	city.player.enabled = true
	await get_tree().process_frame
	SceneRouter.goto_codex()
	await settle()
	get_tree().current_scene._back()
	city = await city_ready()
	check(city.dialogue == null and GameState.get_fragment_count() == 1, "图鉴返回不重复开场或发奖")
	# 三座桥逐一真实跨越，附物理侧向阻挡。
	for bridge in city.story["bridges"]:
		var middle: Vector3 = city.bridge_center(bridge)
		var segment: int = bridge["segment"]
		var a: Array = city.story["canal"][segment]
		var b: Array = city.story["canal"][segment+1]
		var tangent := Vector3(b[0]-a[0],0,b[1]-a[1]).normalized()
		var across := Vector3(-tangent.z,0,tangent.x)
		await teleport(city, middle - across * 3.8)
		await walk(city, middle + across * 3.8, "过桥 " + bridge["id"])
	# 普通水段不允许横穿，包括按住跳跃。
	var a: Array = city.story["canal"][3]
	var b: Array = city.story["canal"][4]
	var middle := Vector3((a[0]+b[0])*0.5,0,(a[1]+b[1])*0.5)
	var tangent := Vector3(b[0]-a[0],0,b[1]-a[1]).normalized()
	var across := Vector3(-tangent.z,0,tangent.x)
	await teleport(city, middle - across * 2.4)
	city.yaw = atan2(-across.x,-across.z)
	key(KEY_W,true)
	key(KEY_SPACE,true)
	await physics(85)
	key(KEY_W,false)
	key(KEY_SPACE,false)
	check((city.player.position-middle).dot(across) < -0.9, "水渠非桥段持续前行与跳跃均不能横穿")
	# 墙体不能穿透；镜头球体不能进入建筑。
	await teleport(city, Vector3(-14.5,0,-3.5))
	city.yaw = 0
	key(KEY_W,true)
	await physics(70)
	key(KEY_W,false)
	check(city.player.position.z > -4.9, "银饰店墙体阻挡连续前行")
	for angle in [0.0,1.3,3.14,-1.2]:
		city.yaw = angle
		city.pitch = 0.70
		city._update_camera()
		var query := PhysicsShapeQueryParameters3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 0.18
		query.shape = sphere
		query.collision_mask = 4
		query.transform = Transform3D(Basis.IDENTITY, city.camera.position)
		check(city.get_world_3d().direct_space_state.intersect_shape(query).is_empty(), "镜头避障 yaw="+str(angle))
	city.distance = 8
	key(KEY_R, true)
	key(KEY_R, false)
	await physics(2)
	check(is_equal_approx(city.yaw, float(city.spec["yaw"])) and is_equal_approx(city.pitch, float(city.spec["pitch"])) and city.distance == 12, "真实R输入恢复默认视角")
	await teleport(city, city.anchor_position("NPC_01_SilverShopSister") + Vector3(0, 0, -2.0))
	check(city.near_hotspot().get("id", "") != "silver", "距离够近但隔着店墙仍不能交互")
	await get_tree().process_frame
	check(not city.interaction_prompt.visible, "隔墙时不显示E对话提示")
	# 第二轮非推荐顺序，确认任务没有隐藏先后依赖。
	GameState.reset_game()
	SceneRouter.goto_station("lijiang")
	city = await city_ready()
	await finish_talk(city)
	for id in ["inn","student","silver"]:
		for item in city.hotspots:
			if item["id"] == id:
				await teleport(city,item["position"]+Vector3(0,0,1.2))
				city.interact()
				check(city.dialogue != null, "自由顺序访谈 " + id)
				await finish_talk(city)
	check(city.clue_count() == 3 and city.target_id == "dongba", "反向顺序同样完成三处访谈")
	# 已完成旧档直接显示完成，无重新收集要求。
	GameState.collect_fragment("frag_dongba_tea")
	SceneRouter.goto_station("lijiang")
	city = await city_ready()
	check(city.dialogue == null and GameState.is_completed("lijiang"), "已有丽江碎片的旧档兼容")
	_restore_save()
	print("LIJIANG_CHAIN_TEST checks=",checks," failures=",failures)
	get_tree().quit(failures)

func _restore_save() -> void:
	GameState.save_path = original_save
	GameState.load_game()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://lijiang-chain-test.cfg"))

func _watchdog() -> void:
	await get_tree().create_timer(150.0).timeout
	printerr("FAIL: 丽江检查超时，终止并恢复正式进度的只读载入")
	GameState.save_path = original_save
	GameState.load_game()
	get_tree().quit(1)
