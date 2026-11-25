extends Node
## 独立测试档；实际按钮、空格、E和W步行贯通终章，兼测四城衔接及存档。
var failures := 0
var checks := 0
var output := OS.get_environment("GUCHENG_EVIDENCE")
var original_save := ""
var original_bytes := PackedByteArray()

func check(ok: bool, message: String) -> void:
	checks += 1
	print("PASS: " if ok else "FAIL: ", message)
	if not ok: failures += 1

func frames(count: int = 3) -> void:
	for index in count: await get_tree().process_frame

func settle() -> void:
	await frames()
	while SceneRouter.is_switching(): await frames(1)
	await frames()

func ready_city() -> Node3D:
	await settle()
	var city := get_tree().current_scene
	while not city.walk_guide.ready: await get_tree().physics_frame
	await frames()
	return city

func key(code: int, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)

func press(code: int) -> void:
	key(code, true)
	await frames(1)
	key(code, false)
	await frames(1)

func click(control: Control) -> void:
	await frames(4)
	var pos := control.get_global_rect().get_center()
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = pos
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		get_viewport().push_input(event, true)
		await frames(1)

func shot(name: String) -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless": return
	await frames(2)
	RenderingServer.force_draw()
	check(get_viewport().get_texture().get_image().save_png(output.path_join(name + ".png")) == OK, name + " 截图")

func talk(city: Node3D) -> void:
	var count := 0
	while is_instance_valid(city) and city.dialogue != null and count < 100:
		await press(KEY_SPACE)
		count += 1
	check(count < 100, "空格正常读完整段对话")

func walk(city: Node3D) -> void:
	var path: PackedVector3Array = city.walk_guide.path(city.player.position, city.goal_position)
	check(path.size() > 1, "出生点至织坊存在实体可走路径")
	print("GUCHENG_PATH ", path)
	var stuck := false
	for waypoint in path:
		var guard := 0
		while Vector2(city.player.position.x - waypoint.x, city.player.position.z - waypoint.z).length() > 0.28 and guard < 100:
			var direction: Vector3 = waypoint - city.player.position
			city.yaw = atan2(-direction.x, -direction.z)
			city.player.heading = city.yaw
			key(KEY_W, true)
			await get_tree().physics_frame
			guard += 1
		if guard >= 100:
			print("GUCHENG_STUCK ", city.player.position, " -> ", waypoint)
			stuck = true
			break
	key(KEY_W, false)
	await frames()
	check(not stuck and city.can_interact(), "真实W键连续走到木老爷身旁，可按E交谈")

func _watchdog() -> void:
	await get_tree().create_timer(180).timeout
	printerr("GUCHENG_TEST_TIMEOUT")
	_cleanup(1)

func _cleanup(code: int) -> void:
	key(KEY_W, false)
	GameUI.close_modal()
	GameMusic.stop()
	GameState.save_path = original_save
	GameState.load_game()
	var current_bytes := FileAccess.get_file_as_bytes(original_save) if FileAccess.file_exists(original_save) else PackedByteArray()
	check(current_bytes == original_bytes, "正式玩家存档逐字节保持不变")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://gucheng-chain-test.cfg"))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("GUCHENG_CHAIN_TEST checks=", checks, " failures=", failures)
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(maxi(code, failures))

func _ready() -> void:
	get_tree().current_scene = null
	original_save = GameState.save_path
	if FileAccess.file_exists(original_save): original_bytes = FileAccess.get_file_as_bytes(original_save)
	GameState.save_path = "user://gucheng-chain-test.cfg"
	GameState.reset_game()
	_watchdog()
	SceneRouter.goto_station("gucheng")
	check(not SceneRouter.is_switching(), "普洱完成前不能提前进入古城")
	for fragment in ["frag_dongba_tea", "frag_dye_five", "frag_zharan_pattern", "frag_beiye_oath"]:
		GameState.collect_fragment(fragment)
	check(GameState.is_unlocked("gucheng") and not GameState.is_completed("gucheng"), "四城完成只解锁古城，不提前结局")
	# 从普洱的既有完成页真实点击下一站，检查手记与三个出口依旧可用。
	GameState.set_flag("flow/puer/arrival")
	SceneRouter.goto_station("puer")
	var puer := await ready_city()
	puer._show_reward()
	await click(puer.reward_panel.find_children("*", "Button", true, false)[0])
	var buttons: Array[Node] = puer.reward_panel.find_children("*", "Button", true, false)
	check(buttons.size() == 3, "普洱手记之后保留共用三个出口")
	await click(buttons[1])
	var city := await ready_city()
	check(city.station_id == "gucheng" and city.dialogue.dialogue_id == "gucheng_arrival", "普洱下一站先自动播放赴古城过渡")
	check(city.dialogue.lines[1]["text"].contains("播出"), "过渡先交代纪录片已经播出")
	check(city.hotspots.size() == 1 and city.story["interviews"].is_empty(), "只有木老爷一个任务点，无额外寻访")
	check(city.dialogue._text_label.get_theme_font_size("normal_font_size") == 36 and city.dialogue._name_label.text == "旁白", "复用36字号正文与旁白姓名卡")
	check(not city.player.enabled and city.arrival_screen.active, "过渡冻结移动并遮住加载中的地图")
	var transition_overflows := 0
	for index in city.dialogue.lines.size():
		city.dialogue._goto_line(index)
		city.dialogue._continue()
		await frames(3)
		if city.dialogue._text_label.get_content_height() > city.dialogue._text_label.size.y + 1: transition_overflows += 1
	check(transition_overflows == 0, "过渡全部4行正文完整显示无溢出")
	city.dialogue._goto_line(0)
	city.dialogue._continue()
	await shot("01-transition")
	city.dialogue._leave()
	await frames()
	check(not city.done("arrival") and not city.ending, "过渡中断不推进剧情")
	await press(KEY_E)
	await talk(city)
	check(city.done("arrival") and not city.arrival_screen.active and city.player.enabled, "完整过渡后恢复地图探索")
	check(not city.objective.text.contains("0 / 0") and city.target_id == "mulaoye", "目标直接指向织坊，没有空访谈计数")
	check(city.guide_path.size() > 1 and city.minimap != null, "共用金色引路及小地图已生成")
	city._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)
	await press(KEY_TAB)
	check(not city.mouse_look and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Tab切换鼠标模式")
	await press(KEY_TAB)
	check(city.mouse_look, "Tab恢复视角模式")
	await shot("02-map-route")
	await walk(city)
	check(city.near_hotspot().get("id", "") == "mulaoye", "织坊站位安全且视线可达")
	await press(KEY_R)
	check(is_equal_approx(city.yaw, float(city.spec["yaw"])), "R恢复本城默认镜头")
	await frames()
	await shot("03-workshop")
	var context: Dictionary = city.city_context()
	SceneRouter.goto_codex()
	await settle()
	get_tree().current_scene._back()
	city = await ready_city()
	check(city.player.position.distance_to(context["position"]) < 0.5 and is_equal_approx(city.yaw, context["yaw"]), "行囊返回保留原地点及视角")
	await press(KEY_E)
	check(city.dialogue != null and city.dialogue.dialogue_id == "gucheng_mulaoye_visit", "E开启木老爷终章对话")
	var portrait_stage: Control = city.dialogue.lijiang_stage
	check(portrait_stage.find_children("*", "SubViewport", true, false).is_empty(), "对话不创建3D人物肖像视口")
	check(not portrait_stage.npc.texture is ViewportTexture and portrait_stage.npc.texture.resource_path.ends_with("mulaoye-portrait-v01.png"), "木老爷使用二维卡通立绘")
	check(portrait_stage.protagonist.texture.resource_path.ends_with("protagonist-portrait-v01.png") and portrait_stage.xiaomu.texture.resource_path.ends_with("xiaomu-portrait-v01.png"), "女主和小木使用对应二维卡通立绘")
	for portrait in [portrait_stage.npc, portrait_stage.protagonist, portrait_stage.xiaomu]:
		var image: Image = portrait.texture.get_image()
		check(image != null and image.get_pixel(0, 0).a < 0.01 and image.get_pixel(image.get_width() - 1, image.get_height() - 1).a < 0.01, "立绘透明边角正确：" + portrait.texture.resource_path.get_file())
	city.dialogue._leave()
	await frames()
	check(not city.done("visit") and not GameState.is_completed("gucheng"), "织坊对话中断不保存结局，不发额外碎片")
	GameState.load_game()
	check(GameState.get_fragment_count() == 4 and city.done("arrival") and not city.done("visit"), "中断后重载存档保留四城及过渡成果")
	await press(KEY_E)
	var text_overflows := 0
	for index in city.dialogue.lines.size():
		city.dialogue._goto_line(index)
		city.dialogue._continue()
		await frames(3)
		var label: RichTextLabel = city.dialogue._text_label
		if label.get_content_height() > label.size.y + 1: text_overflows += 1
		if index == 8: check(not city.dialogue.lijiang_stage.xiaomu.visible, "小木进门前不提前出现")
		if index == 11:
			check(city.dialogue.lijiang_stage.xiaomu.visible and label.text == "我看见电视台的纪录片了，回来看看。", "小木出现并说出用户确认的纪录片对白")
			check(city.dialogue.lijiang_stage.xiaomu.modulate == Color.WHITE and city.dialogue.lijiang_stage.npc.modulate != Color.WHITE, "小木发言时立绘高亮、木老爷立绘压暗")
			await shot("04-xiaomu-returns")
		if index == 15:
			check(label.text == "坐吧，咱们慢慢来。", "最后一句对白逐字保留用户版本")
			check(city.dialogue.lijiang_stage.npc.modulate == Color.WHITE and city.dialogue.lijiang_stage.xiaomu.modulate != Color.WHITE, "木老爷发言时高亮切换正确")
			await shot("05-slowly-learn")
	check(text_overflows == 0, "织坊全部17行正文完整显示无溢出")
	GameUI.open_pause()
	check(get_tree().paused and not city.player.enabled, "剧情中暂停保持冻结")
	GameUI.close_modal()
	await press(KEY_SPACE)
	await frames()
	check(city.done("visit") and city.ending and SceneRouter.current_key == "city", "读完对话自动进入实时退镜，不进入小游戏")
	check(not GameState.is_completed("gucheng"), "镜头淡出前不提前标记终章完成")
	SceneRouter.goto_map()
	await settle()
	GameState.load_game()
	SceneRouter.goto_station("gucheng")
	city = await ready_city()
	check(city.ending and city.dialogue == null, "退镜中离开并读档，重进自动接续收尾")
	await shot("06-closing-shot")
	for index in 600:
		if SceneRouter.current_key == "finale" and not SceneRouter.is_switching(): break
		await get_tree().create_timer(0.02).timeout
	await settle()
	check(SceneRouter.current_key == "finale" and GameState.can_enter_finale(), "退镜淡出后进入片尾并完成五站")
	check(GameState.get_fragment_count() == 4 and GameState.has_flag("flow/gucheng/ending"), "终章保存完成且不新增碎片")
	await get_tree().create_timer(1.3).timeout
	await shot("07-finale")
	var finale := get_tree().current_scene
	var finish_buttons := finale.find_children("*", "Button", true, false)
	check(finish_buttons.size() == 3 and finish_buttons[0].text == "重温终章", "片尾提供重温与返回入口")
	await click(finish_buttons[0])
	city = await ready_city()
	check(city.dialogue != null and city.dialogue.dialogue_id == "gucheng_mulaoye_visit", "片尾重温直接回到织坊对白")
	city.dialogue._leave()
	await frames()
	var saved_count: int = GameState.completed.size()
	GameState.load_game()
	check(GameState.is_completed("gucheng") and GameState.get_fragment_count() == 4 and GameState.completed.size() == saved_count, "重温中断、读档不重复结算")
	SceneRouter.goto_map()
	await settle()
	SceneRouter.goto_station("gucheng")
	city = await ready_city()
	check(city.dialogue == null and city.player.enabled and not city.ending, "已完成终章重返古城可自由探索")
	check(city.closing_props != null and city.xiaomu_actor.get_node("CharacterVisual").has_meta("seated"), "重返织坊仍保留小木坐下的状态")
	GameState.flags.erase("flow/gucheng/visit")
	GameState.flags.erase("flow/gucheng/ending")
	GameState.flags.erase("flow/gucheng/arrival")
	SceneRouter.goto_map()
	await settle()
	SceneRouter.goto_station("gucheng")
	city = await ready_city()
	check(not GameState.is_completed("gucheng") and city.dialogue != null and GameState.get_fragment_count() == 4, "旧占位完成档迁移保留四城，实际体验新终章")
	_cleanup(0)
