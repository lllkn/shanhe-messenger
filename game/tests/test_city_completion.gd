extends Node
## 四城真实完成页与三个出口；使用独立测试档。
var failures := 0
var checks := 0
var output := OS.get_environment("CITY_COMPLETION_OUTPUT")

func check(ok: bool, message: String) -> void:
	checks += 1
	print("PASS: " if ok else "FAIL: ", message)
	if not ok: failures += 1

func settle() -> void:
	await get_tree().process_frame
	while SceneRouter.is_switching(): await get_tree().process_frame
	await get_tree().process_frame

func city_ready() -> Node3D:
	await settle()
	var city := get_tree().current_scene
	while not city.walk_guide.ready: await get_tree().physics_frame
	return city

func click(button: Button) -> void:
	for frame_index in 4: await get_tree().process_frame
	var pos := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	get_viewport().push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = pos
		event.pressed = pressed
		get_viewport().push_input(event, true)
		await get_tree().process_frame

func choices(city: Node3D) -> Array[Node]:
	if city.reward_panel.find_child("CompletionChoices", true, false) == null:
		await click(city.reward_panel.find_children("*", "Button", true, false)[0])
	await get_tree().process_frame
	return city.reward_panel.find_children("*", "Button", true, false)

func journal_fits(root: Control) -> bool:
	var spread := root.find_child("JournalSpread", true, false) as Control
	if spread == null: return false
	var fits := get_viewport().get_visible_rect().encloses(spread.get_global_rect())
	for label in spread.find_children("*", "Label", true, false):
		if not label.get_parent().get_global_rect().encloses(label.get_global_rect()):
			print("JOURNAL_OVERFLOW label=", label.text, " rect=", label.get_global_rect(), " parent=", label.get_parent().get_global_rect())
		fits = fits and label.get_parent().get_global_rect().encloses(label.get_global_rect())
	for button in spread.find_children("*", "Button", true, false):
		if not spread.get_global_rect().encloses(button.get_global_rect()):
			print("JOURNAL_OVERFLOW button=", button.get_global_rect(), " spread=", spread.get_global_rect())
		fits = fits and spread.get_global_rect().encloses(button.get_global_rect())
	return fits

func shot(name: String) -> void:
	if output.is_empty(): return
	await get_tree().process_frame
	RenderingServer.force_draw()
	check(get_viewport().get_texture().get_image().save_png(output.path_join(name + ".png")) == OK, name + " 截图")

func _ready() -> void:
	get_tree().current_scene = null
	var original_save: String = GameState.save_path
	GameState.save_path = "user://city-completion-test.cfg"
	GameState.reset_game()
	GameState.unlocked.assign(["lijiang", "xianggelila", "dali", "puer"])
	var ids := ["lijiang", "xianggelila", "dali", "puer"]
	for index in ids.size():
		var id: String = ids[index]
		GameState.set_flag("flow/" + id + "/arrival")
		SceneRouter.goto_station(id)
		var city := await city_ready()
		for item in city.story["interviews"]:
			GameState.set_flag("clue/" + id + "/" + item["id"])
		GameState.set_flag("flow/" + id + "/" + str(city.story.get("visit_step", "visit")))
		GameState.set_flag("flow/" + id + "/" + str(city.story["puzzle_step"]))
		city.open_conversation(city.story["farewell"], "farewell")
		city.dialogue._finish()
		await get_tree().process_frame
		check(GameState.is_completed(id) and city.reward_panel != null, id + " 收尾触发奖励及完成页")
		check(city.reward_panel.find_child("JournalSpread", true, false) != null, id + " 收尾显示双页手记")
		var titles := preload("res://ui/JourneyJournal.gd").entry(city.story["fragment"])
		var title_seen := false
		for label in city.reward_panel.find_children("*", "Label", true, false):
			if label.text == titles["title"]: title_seen = true
		check(title_seen and journal_fits(city.reward_panel), id + " 对应手记完整可读")
		await shot(id + "-journal")
		var buttons := await choices(city)
		check(buttons.size() == 3, id + " 三个选项")
		if buttons.size() != 3: break
		check(buttons[0].text == "继续探索" and buttons[1].text == "去下一个地方" and buttons[2].text == "返回旅途长卷", id + " 文案与顺序一致")
		check(not city.player.enabled and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, id + " 完成页冻结移动并显示光标")
		var fits := true
		var viewport := get_viewport().get_visible_rect()
		for button in buttons:
			fits = fits and viewport.encloses(button.get_global_rect())
		check(fits, id + " 三个按钮均完整显示")
		if not output.is_empty():
			await get_tree().process_frame
			RenderingServer.force_draw()
			check(get_viewport().get_texture().get_image().save_png(output.path_join(id + ".png")) == OK, id + " 完成页截图")
		var position: Vector3 = city.player.position
		var yaw: float = city.yaw
		var count: int = GameState.get_fragment_count()
		await click(buttons[0])
		check(city.reward_panel == null and city.player.enabled, id + " 继续探索恢复移动")
		var mouse_restored := DisplayServer.get_name() == "headless" or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		check(mouse_restored and is_equal_approx(city.yaw, yaw) and city.player.position.distance_to(position) < 0.3, id + " 恢复鼠标视角并留在原处")
		city._show_reward()
		buttons = await choices(city)
		await click(buttons[2])
		await settle()
		check(SceneRouter.current_key == "map", id + " 返回旅途长卷")
		SceneRouter.goto_station(id)
		city = await city_ready()
		check(city.dialogue == null and city.reward_panel == null and GameState.get_fragment_count() == count, id + " 重返已完成地图不重复领奖")
		city._show_reward()
		buttons = await choices(city)
		await click(buttons[1])
		await settle()
		var next_id: String = "gucheng" if index == ids.size() - 1 else ids[index + 1]
		check(SceneRouter.current_key == "city" and SceneRouter.params.get("station", "") == next_id, id + " 直接前往 " + next_id)
		check(GameState.get_fragment_count() == count, id + " 导航不额外发碎片")
	# 图鉴同时验证未收集、已收集与重读，不让UI写入旅程状态。
	GameState.reset_game()
	GameState.collect_fragment("frag_dongba_tea")
	GameState.collect_fragment("frag_dye_five")
	SceneRouter.goto_codex()
	await settle()
	var codex := get_tree().current_scene
	await click(codex.tabs.get_node("Tab_fragments"))
	check(codex.find_children("frag_*", "PanelContainer", true, false).size() == 4, "信物页统一四张手记卡")
	check(codex.find_child("frag_zharan_pattern", true, false).find_children("*", "Button", true, false).is_empty(), "未收集卡不提供重读")
	codex._open_journal("frag_zharan_pattern")
	check(codex.journal_layer == null and GameState.get_fragment_count() == 2, "未收集手记不能通过界面解锁")
	await shot("codex-mixed")
	GameState.collect_fragment("frag_zharan_pattern")
	GameState.collect_fragment("frag_beiye_oath")
	SceneRouter.goto_codex()
	await settle()
	codex = get_tree().current_scene
	await click(codex.tabs.get_node("Tab_fragments"))
	await shot("codex-all")
	var saved := FileAccess.get_file_as_bytes(GameState.save_path)
	for fragment_id in ["frag_dongba_tea", "frag_dye_five", "frag_zharan_pattern", "frag_beiye_oath"]:
		var card := codex.find_child(fragment_id, true, false)
		var button: Button = card.find_children("*", "Button", true, false)[0]
		# 第二行先滚到可见处，随后用真实鼠标输入打开。
		var scroll: ScrollContainer = card.get_parent().get_parent().get_parent()
		scroll.ensure_control_visible(button)
		await click(button)
		check(codex.journal_layer != null, fragment_id + " 点击打开手记")
		if codex.journal_layer == null: break
		var journal_root: Control = codex.journal_layer.get_child(0)
		check(journal_fits(journal_root), fragment_id + " 重读双页完整显示")
		await shot(fragment_id + "-replay")
		await click(journal_root.find_children("*", "Button", true, false)[0])
		check(codex.journal_layer == null and GameState.get_fragment_count() == 4, fragment_id + " 合上返回且不重复领奖")
	check(FileAccess.get_file_as_bytes(GameState.save_path) == saved, "全部重读操作不修改存档")
	GameState.save_path = original_save
	GameState.load_game()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://city-completion-test.cfg"))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("CITY_COMPLETION_TEST checks=", checks, " failures=", failures)
	GameMusic.stop()
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(failures)
