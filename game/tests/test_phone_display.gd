extends Node
## 共用照片舞台专项：真实GUI点击、完整对话门槛及三城全部照片范围。
var failures := 0
var checks := 0
var emissions := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	print("PASS: " if ok else "FAIL: ", message)
	if not ok: failures += 1

func frames() -> void:
	for i in 3: await get_tree().process_frame

func click(control: Control) -> void:
	var at := control.get_global_rect().get_center()
	var event := InputEventMouseButton.new()
	event.position = at
	event.global_position = at
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	get_viewport().push_input(event, true)
	await get_tree().process_frame
	event.pressed = false
	get_viewport().push_input(event, true)
	await frames()

func talk_for(id: String) -> Control:
	var talk: Control = load("res://scenes/DialogueScene.tscn").instantiate()
	talk.configure_inline(id)
	add_child(talk)
	await frames()
	return talk

func shot(name: String) -> void:
	var dir := OS.get_environment("PHONE_DISPLAY_SHOTS")
	if dir.is_empty() or DisplayServer.get_name() == "headless": return
	RenderingServer.force_draw()
	check(get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png")) == OK, "截图 " + name)

func _ready() -> void:
	var talk: Control = await talk_for("lijiang_dongba_visit")
	var stage: Control = talk.lijiang_stage
	stage.photo_ready.connect(func(): emissions += 1)
	talk._goto_line(8)
	talk._continue() # 补全本句；之后所有推进都通过真实正文点击。
	await frames()
	check(stage.phone.visible and stage.settings_panel.visible and stage.confirm_button.disabled, "丽江初始暗屏禁用展示")
	await click(stage.confirm_button)
	stage.confirm_photo() # 同时验证回调不能绕过禁用按钮。
	await click(talk._body_slot)
	check(not stage.confirmed and emissions == 0 and talk.line_idx == 8, "未调整点击展示或正文均不能放行")
	await click(stage.zoom_button)
	await click(stage.confirm_button)
	stage.confirm_photo()
	check(stage.zoomed and stage.confirm_button.disabled and not stage.confirmed, "仅放大仍不能展示")
	stage.slider.value = 69
	stage.confirm_photo()
	check(stage.confirm_button.disabled and not stage.confirmed, "69%亮度且已放大仍不能展示")
	stage.slider.value = 70
	check(not stage.confirm_button.disabled, "70%亮度且已放大启用展示")
	await click(stage.zoom_button)
	stage.confirm_photo()
	await click(talk._body_slot)
	check(stage.confirm_button.disabled and not stage.confirmed and talk.line_idx == 8, "取消放大立即重新锁定")
	# 使用实际滑杆点击完成调亮。
	var rect: Rect2 = stage.slider.get_global_rect()
	var at := rect.position + rect.size * Vector2(0.87, 0.5)
	var event := InputEventMouseButton.new()
	event.position = at
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	get_viewport().push_input(event, true)
	await get_tree().process_frame
	event.pressed = false
	get_viewport().push_input(event, true)
	await frames()
	check(stage.photo_brightness > 75 and stage.confirm_button.disabled, "实际滑杆调亮后仍需放大")
	await click(stage.zoom_button)
	check(stage.zoomed and stage.screen.scale == Vector2(2.5, 2.5) and not stage.confirm_button.disabled, "实际放大按钮满足展示条件")
	await shot("lijiang-ready")
	stage.confirm_button.grab_focus()
	await click(stage.confirm_button)
	check(stage.confirmed and emissions == 1 and not stage.blocks_continue() and talk.line_idx == 8, "展示成功发一次信号且不跳句")
	check(not stage.settings_panel.visible and not stage.slider.is_visible_in_tree() and not stage.zoom_button.is_visible_in_tree(), "确认后整个调整栏隐藏")
	check(stage.screen.modulate == Color.WHITE and stage.screen.scale == Vector2.ONE and stage.phone.position.x == 547.5, "确认后只保留居中的清晰完整照片")
	check(get_viewport().gui_get_focus_owner() == null, "隐藏调整栏释放焦点")
	stage.confirm_photo()
	stage.confirm_button.pressed.emit()
	stage._set_brightness(10)
	stage._toggle_zoom()
	check(emissions == 1 and stage.screen.modulate == Color.WHITE and stage.screen.scale == Vector2.ONE, "重复确认和过期调整事件不改变展示状态")
	await shot("lijiang-display")
	await click(talk._body_slot)
	check(talk.line_idx == 9, "展示后正文点击正常推进一句")
	talk._goto_line(15)
	check(not stage.phone.visible, "收好手机后隐藏照片")
	talk.queue_free()
	await frames()
	talk = await talk_for("lijiang_dongba_visit")
	talk._goto_line(8)
	stage = talk.lijiang_stage
	check(not stage.confirmed and not stage.zoomed and stage.photo_brightness == 35 and stage.blocks_continue(), "中断重开丽江重新要求调整")
	talk.queue_free()
	await frames()
	for path in ["res://ui/XianggelilaDialogueStage.gd", "res://ui/DaliDialogueStage.gd", "res://ui/PuerDialogueStage.gd"]:
		var script: Script = load(path)
		for id in script.PORTRAITS:
			talk = await talk_for(id)
			stage = talk.lijiang_stage
			var spans: Array = stage.config.get("phone_lines", [])
			var valid := true
			for index in talk.lines.size():
				talk._goto_line(index)
				talk._continue()
				valid = valid and not stage.blocks_continue()
				if stage.phone == null: continue
				valid = valid and stage.phone.visible == (index >= spans[0] and index <= spans[1])
				valid = valid and stage.settings_panel == null and stage.slider == null and stage.confirm_button == null and stage.zoom_button == null
				valid = valid and stage.screen.modulate == Color.WHITE and stage.screen.scale == Vector2.ONE
				if index == spans[0]:
					await frames()
					if id in ["xianggelila_danzeng_visit", "dali_popo_visit", "puer_yanxiang_visit"]: await shot(id)
					await click(talk._body_slot)
					valid = valid and talk.line_idx == index + 1
			check(valid, id + "照片范围正确、清晰完整、无控件及继续门槛")
			talk.queue_free()
			await frames()
	print("PHONE_DISPLAY_TEST checks=", checks, " failures=", failures, " renderer=", DisplayServer.get_name())
	get_tree().quit(failures)
