extends Node
## 原生窗口四城完整访谈、实际按钮点击、存档重载和行囊分类；独立存档。
var checks := 0
var failures := 0
var output := OS.get_environment("CLUE_EVIDENCE")
var original_save := ""

func check(ok: bool, message: String) -> void:
	checks += 1
	print("PASS: " if ok else "FAIL: ", message)
	if not ok: failures += 1

func settle(frames := 4) -> void:
	for i in frames: await get_tree().process_frame
	while SceneRouter.is_switching(): await get_tree().process_frame
	await get_tree().process_frame

func click(button: Control) -> void:
	await settle()
	var pos := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	get_viewport().push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = pos
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		get_viewport().push_input(event, true)
		await get_tree().process_frame
	await settle()

func key(code: int) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		get_viewport().push_input(event, true)
		await get_tree().process_frame
	await settle()

func finish_talk(city: Node) -> void:
	var guard := 0
	while city.dialogue != null and guard < 250:
		var dialogue: Control = city.dialogue
		var stage: Control = dialogue.lijiang_stage
		if not dialogue._typing and stage != null and stage.blocks_continue():
			if stage.slider != null:
				var rect: Rect2 = stage.slider.get_global_rect()
				var pos: Vector2 = rect.position + Vector2(rect.size.x * 0.9, rect.size.y * 0.5)
				for pressed in [true, false]:
					var event := InputEventMouseButton.new()
					event.position = pos
					event.button_index = MOUSE_BUTTON_LEFT
					event.pressed = pressed
					get_viewport().push_input(event, true)
				await settle()
			if stage.zoom_button != null and not stage.zoomed: await click(stage.zoom_button)
			await click(stage.confirm_button)
		else:
			dialogue._continue()
		await get_tree().process_frame
		guard += 1
	check(guard < 250, "访谈正常读到结束")
	await settle()

func fits(card: ClueCard) -> bool:
	var good := get_viewport().get_visible_rect().encloses(card.card.get_global_rect())
	for art in card.card.find_children("*", "TextureRect", true, false):
		good = good and card.card.get_global_rect().encloses(art.get_global_rect())
	for label in card.card.find_children("*", "Label", true, false):
		if not card.card.get_global_rect().encloses(label.get_global_rect()):
			print("OVERFLOW: ", label.text, " ", label.get_global_rect())
			good = false
	return good

func shot(file_name: String) -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless": return
	await settle()
	RenderingServer.force_draw()
	check(get_viewport().get_texture().get_image().save_png(output.path_join(file_name + ".png")) == OK, "截图 " + file_name)

func _ready() -> void:
	get_tree().current_scene = null
	original_save = GameState.save_path
	GameState.save_path = "user://clue-cards-test.cfg"
	GameState.reset_game()
	GameState.unlocked.assign(["lijiang", "xianggelila", "dali", "puer"])
	_watchdog()
	check(ClueBook.entries().size() == 12 and ClueBook.count() == 0, "四城12张线索，没有虚构已获得进度")
	for id in ClueBook.CITIES:
		GameState.set_flag("flow/" + id + "/arrival")
		SceneRouter.goto_station(id)
		await settle()
		var city := get_tree().current_scene
		while not city.walk_guide.ready: await get_tree().physics_frame
		await settle()
		await key(KEY_TAB)
		var interviews: Array = city.story["interviews"]
		await click(city.checklist.get_child(1))
		check(city.target_id == interviews[1]["id"] and city.reward_panel == null, id + " 未完成任务仍引路")
		city.open_clue(interviews[0]["id"])
		check(city.reward_panel == null, id + " 不允许重读未获得正文")
		city.open_conversation(interviews[0]["dialogue"], "clue/" + interviews[0]["id"])
		city.dialogue._leave()
		await settle()
		check(ClueBook.count(id) == 0 and city.reward_panel == null, id + " 中断访谈不发卡")
		for index in interviews.size():
			var interview: Dictionary = interviews[index]
			city.open_conversation(interview["dialogue"], "clue/" + interview["id"])
			await finish_talk(city)
			check(ClueBook.count(id) == index + 1 and city.reward_panel is ClueCard, id + "/" + interview["id"] + " 完整访谈后发对应卡")
			if not city.reward_panel is ClueCard: break
			check(not city.player.enabled and city.dialogue == null and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "卡片冻结地图并释放光标")
			check(fits(city.reward_panel), "卡片文字与按钮完整显示")
			await shot(id + "-" + interview["id"])
			await key(KEY_TAB)
			check(not city.mouse_look, "卡片期间Tab不抢鼠标")
			await click(city.reward_panel.close_button)
			if id == "puer" and index == 2:
				check(city.dialogue != null and city.dialogue.dialogue_id == "puer_interviews_end", "普洱总结在合上最后线索后开始")
				await finish_talk(city)
			check(city.reward_panel == null and city.player.enabled and not city.mouse_look, "关闭回到原鼠标模式")
			var target: String = city.target_id
			await click(city.checklist.get_child(index))
			if not (city.reward_panel is ClueCard and city.target_id == target): print("TASK_DEBUG index=",index," card=",city.reward_panel," target=",city.target_id," previous_target=",target," paused=",get_tree().paused," mouse_look=",city.mouse_look)
			check(city.reward_panel is ClueCard and city.target_id == target, "已完成的人物任务打开卡片且保留引路目标")
			await key(KEY_ESCAPE)
			check(city.reward_panel == null and not get_tree().paused, "Esc合上卡片，不叠暂停菜单")
			city.open_conversation(interview["repeat"], "repeat")
			await finish_talk(city)
			check(ClueBook.count(id) == index + 1 and city.reward_panel == null, "重访不重复发卡")
		await key(KEY_TAB)
		city.open_clue(interviews[0]["id"])
		await settle()
		await click(city.reward_panel.close_button)
		check(city.mouse_look and city.reward_panel == null and city.player.enabled and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED if city.window_focused else Input.mouse_mode == Input.MOUSE_MODE_VISIBLE), "合上卡片恢复视角偏好，失焦时释放鼠标")
		if city.mouse_look: await key(KEY_TAB)
		await shot(id + "-hud")
	check(ClueBook.count() == 12, "全部线索唯一收录")
	GameState.load_game()
	check(ClueBook.count() == 12, "重载原有存档保留全部收录")
	SceneRouter.goto_codex()
	await settle()
	var codex := get_tree().current_scene
	check(codex.selected_tab == "clues" and codex.content.get_child_count() == 8, "行囊默认显示四城线索分组")
	await shot("bag-all")
	await click(codex.filter_row.get_node("Filter_puer"))
	check(codex.selected_city == "puer" and codex.content.get_child_count() == 2, "城市筛选只显示该城三张")
	await shot("bag-puer")
	var card_button: Button = codex.content.get_child(1).get_child(1)
	card_button.grab_focus()
	await click(card_button)
	check(codex.clue_layer != null and codex.clue_layer.get_child(0) is ClueCard, "行囊点击打开同一线索")
	await key(KEY_ESCAPE)
	check(codex.clue_layer == null and get_viewport().gui_get_focus_owner() == card_button, "合上行囊卡恢复按钮焦点")
	await click(codex.tabs.get_node("Tab_fragments"))
	check(codex.selected_tab == "fragments" and codex.content.get_child(0).get_child_count() == 4, "信物手记保留独立分类")
	GameState.collect_fragment("frag_dongba_tea")
	codex._render()
	codex._open_journal("frag_dongba_tea")
	await settle()
	check(codex.journal_layer != null, "原有信物手记仍可重读")
	codex.journal_layer.queue_free()
	codex.journal_layer = null
	# 新旅程不显示旧正文，也不能从禁用卡进入。
	GameState.reset_game()
	codex.selected_tab = "clues"
	codex.selected_city = ""
	codex._render()
	await settle()
	var hidden := true
	for child in codex.content.get_children():
		if child is GridContainer:
			for button in child.get_children():
				hidden = hidden and button.disabled
				for label in button.find_children("*", "Label", true, false):
					for item in ClueBook.entries(): hidden = hidden and label.text != item["title"] and label.text != item["text"]
	check(hidden, "新旅程未获卡不显示标题正文且不可点开")
	await shot("bag-empty")
	_restore()
	print("CLUE_CARDS_TEST checks=", checks, " failures=", failures)
	get_tree().quit(failures)

func _restore() -> void:
	GameState.save_path = original_save
	GameState.load_game()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://clue-cards-test.cfg"))

func _watchdog() -> void:
	await get_tree().create_timer(180).timeout
	printerr("CLUE_CARDS_TEST timeout")
	_restore()
	get_tree().quit(99)
