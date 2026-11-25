extends Node
## 在实际行囊中改变窗口、滚动和重读，检查比例及图文位置；使用独立存档。
var checks := 0
var failures := 0
var original_save := ""
var output := OS.get_environment("CLUE_LAYOUT_EVIDENCE")

func check(ok: bool, message: String) -> void:
	checks += 1
	print("PASS: " if ok else "FAIL: ", message)
	if not ok: failures += 1

func settle() -> void:
	for i in 8: await get_tree().process_frame
	while SceneRouter.is_switching(): await get_tree().process_frame
	for i in 4: await get_tree().process_frame

func click(button: Button) -> void:
	get_window().grab_focus()
	await get_tree().create_timer(0.1).timeout
	await settle()
	var point := button.get_global_rect().get_center()
	get_viewport().warp_mouse(point)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	get_viewport().push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = pressed
		get_viewport().push_input(event, true)
		await get_tree().process_frame
	await settle()

func shot(file_name: String) -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless": return
	await settle()
	RenderingServer.force_draw()
	check(get_viewport().get_texture().get_image().save_png(output.path_join(file_name + ".png")) == OK, file_name + " 截图")

func label_for(root: Control, text: String) -> Label:
	for label in root.find_children("*", "Label", true, false):
		if label.text == text: return label
	return null

func _ready() -> void:
	get_tree().current_scene = null
	original_save = GameState.save_path
	GameState.save_path = "user://clue-inventory-layout-test.cfg"
	GameState.reset_game()
	for item in ClueBook.entries(): GameState.set_flag("clue/" + item["key"])
	SceneRouter.goto("codex")
	await settle()
	var codex := get_tree().current_scene
	for dimensions in [Vector2i(1280,720), Vector2i(1600,900), Vector2i(1280,900)]:
		get_window().content_scale_size = dimensions
		get_window().size = dimensions
		await settle()
		check(get_viewport().get_visible_rect().size.is_equal_approx(Vector2(dimensions)), "实际窗口 " + str(dimensions))
		var total := 0
		for group in codex.content.get_children():
			if not group is GridContainer: continue
			for button in group.get_children():
				total += 1
				var face: Control = button.get_node("CluePaper")
				check(is_equal_approx(button.size.x / button.size.y, 940.0 / 558.0), button.name + " 缩略卡与详情比例一致")
				check(is_equal_approx(face.scale.x, face.scale.y) and (face.size * face.scale).is_equal_approx(button.size), "底图和内容等比覆盖卡片")
				var contained := true
				for node in face.find_children("*", "Control", true, false):
					contained = contained and button.get_global_rect().grow(1).encloses(node.get_global_rect())
				check(contained, "人物、正文、页脚均在卡片内")
		check(total == 12, "四城12张仍完整收录")
		var sample: Button = codex.content.get_child(1).get_child(1)
		var sample_face: Control = sample.get_node("CluePaper")
		var item := ClueBook.entry("lijiang", "student")
		var title := label_for(sample_face, item["title"])
		var normalized_title := (title.get_global_rect().position - sample.get_global_rect().position) / sample.size
		await shot("inventory-%dx%d" % [dimensions.x, dimensions.y])
		await click(sample)
		check(codex.clue_layer != null, "等比缩放后真实点击仍能重读")
		if codex.clue_layer == null: break
		var detail: ClueCard = codex.clue_layer.get_child(0)
		var detail_title := label_for(detail.card, item["title"])
		var normalized_detail := (detail_title.get_global_rect().position - detail.card.get_global_rect().position) / detail.card.get_global_rect().size
		check(normalized_title.distance_to(normalized_detail) < 0.001, "缩略卡和大卡标题相对位置一致")
		var thumbnail_body := label_for(sample_face, item["text"])
		var detail_body := label_for(detail.card, item["text"])
		var thumb_pos := (thumbnail_body.get_global_rect().position - sample.get_global_rect().position) / sample.size
		var detail_pos := (detail_body.get_global_rect().position - detail.card.get_global_rect().position) / detail.card.get_global_rect().size
		check(thumb_pos.distance_to(detail_pos) < 0.001, "缩略卡和大卡正文相对位置一致")
		await shot("detail-%dx%d" % [dimensions.x, dimensions.y])
		await click(detail.close_button)
		check(codex.clue_layer == null and get_viewport().gui_get_focus_owner() == sample, "关闭返回同一卡片焦点")
	# 第三张换到下一行后，滚动仍能点击。
	await click(codex.filter_row.get_node("Filter_puer"))
	var scroll: ScrollContainer = codex.content.get_parent()
	var last: Button = codex.content.get_child(1).get_child(2)
	scroll.ensure_control_visible(last)
	await settle()
	await shot("inventory-puer-scrolled")
	await click(last)
	check(codex.clue_layer != null and codex.clue_layer.get_child(0).entry_key == "puer/novice", "滚动后第三张卡仍打开对应线索")
	if codex.clue_layer != null: await click(codex.clue_layer.get_child(0).close_button)
	GameState.reset_game()
	codex._render()
	await settle()
	var locked: Button = codex.content.get_child(1).get_child(0)
	check(locked.disabled and label_for(locked, "尚未收录") != null, "未获得卡保持锁定展示")
	GameState.save_path = original_save
	GameState.load_game()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://clue-inventory-layout-test.cfg"))
	print("CLUE_INVENTORY_LAYOUT_TEST checks=", checks, " failures=", failures)
	get_tree().quit(failures)
