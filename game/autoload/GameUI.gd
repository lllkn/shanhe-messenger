extends CanvasLayer
## 常驻功能层：暂停、设置、可恢复错误提示。输入不穿透弹层。
var _modal: Control
var _toast: PanelContainer
var _toast_generation := 0
var _previous_focus: Control

func _ready() -> void:
	layer = 80
	process_mode = Node.PROCESS_MODE_ALWAYS
	SceneRouter.navigation_failed.connect(notify)
	SceneRouter.scene_changed.connect(func(_path: String): close_modal())

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		if SceneRouter.is_switching():
			return
		if is_instance_valid(_modal):
			close_modal()
		else:
			for card in get_tree().get_nodes_in_group("open_clue_cards"):
				if not card.is_queued_for_deletion():
					card.close()
					get_viewport().set_input_as_handled()
					return
			open_pause()
		get_viewport().set_input_as_handled()

func _make_modal(title: String) -> VBoxContainer:
	close_modal()
	_previous_focus = get_viewport().gui_get_focus_owner()
	get_tree().paused = true
	_set_media_paused(true)
	_modal = ColorRect.new()
	(_modal as ColorRect).color = Color(0.03, 0.08, 0.07, 0.93)
	add_child(_modal)
	_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	_modal.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var p := UiKit.panel()
	p.custom_minimum_size.x = 580
	center.add_child(p)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	p.add_child(box)
	box.add_child(UiKit.label(title, 38, UiKit.GOLD))
	return box

func open_pause() -> void:
	var box := _make_modal("歇一歇，再启程")
	box.add_child(UiKit.label("旅程会自动记住已收集的碎片。", 26, UiKit.MUTED))
	var resume := UiKit.button("继续旅程", close_modal, true)
	box.add_child(resume)
	box.add_child(UiKit.button("游戏设置", open_settings))
	var scene := get_tree().current_scene
	if is_instance_valid(scene) and scene.has_method("controls_help"):
		box.add_child(UiKit.label(scene.controls_help(), 18, UiKit.PAPER))
	if is_instance_valid(scene) and scene.has_method("is_opening_active") and scene.is_opening_active():
		# 开场所有跳过入口使用同一文字简介，不经暂停菜单提前进入地图。
		if scene.can_skip_opening():
			box.add_child(UiKit.button("跳过影像 · 查看简介", func(): close_modal(); scene.skip_opening()))
	else:
		box.add_child(UiKit.button("返回旅程总览", func(): close_modal(); SceneRouter.goto_map()))
		box.add_child(UiKit.button("返回标题", func(): close_modal(); SceneRouter.goto("home")))
	resume.grab_focus()

func open_settings() -> void:
	var box := _make_modal("游戏设置")
	box.add_theme_constant_override("separation", 12)
	box.get_parent().add_theme_stylebox_override("panel", UiKit.surface("silk", 32))
	box.add_child(UiKit.label("音量", 28))
	var volume := UiKit.slider(0, 1, 0.05, GameSettings.volume)
	volume.value_changed.connect(func(v: float): GameSettings.update("volume", v))
	box.add_child(volume)
	box.add_child(UiKit.label("对话文字速度", 28))
	var speed := UiKit.slider(0.5, 3.0, 0.25, GameSettings.text_speed)
	speed.value_changed.connect(func(v: float): GameSettings.update("text_speed", v))
	box.add_child(speed)
	var camera_row := HBoxContainer.new()
	box.add_child(camera_row)
	var camera_label := UiKit.label("地图视角速度 · %d%%" % roundi(GameSettings.camera_sensitivity * 100), 24)
	camera_row.add_child(camera_label)
	var camera_speed := UiKit.slider(0.25, 2.0, 0.05, GameSettings.camera_sensitivity)
	camera_speed.name = "CameraSensitivity"
	camera_speed.value_changed.connect(func(v: float):
		GameSettings.update("camera_sensitivity", v)
		camera_label.text = "地图视角速度 · %d%%" % roundi(v * 100)
	)
	var reset_camera := UiKit.button("恢复推荐", func(): camera_speed.value = GameSettings.DEFAULT_CAMERA_SENSITIVITY)
	reset_camera.custom_minimum_size = Vector2(120, 36)
	reset_camera.add_theme_font_size_override("font_size", 20)
	camera_row.add_child(reset_camera)
	box.add_child(camera_speed)
	box.add_child(UiKit.label("向左更慢，向右更快；推荐 50%，即时生效。", 18, UiKit.MUTED))
	var full := UiKit.button("全屏显示 · " + ("开启" if GameSettings.fullscreen else "关闭"), func(): pass)
	full.pressed.connect(func():
		GameSettings.update("fullscreen", not GameSettings.fullscreen)
		full.text = "全屏显示 · " + ("开启" if GameSettings.fullscreen else "关闭")
	)
	box.add_child(full)
	var done := UiKit.button("保存并返回", close_modal, true)
	box.add_child(done)
	done.grab_focus()

func confirm_new_game() -> void:
	var box := _make_modal("重新启程")
	box.add_child(UiKit.label("重新开始会清空当前旅程与碎片。\n声音和显示设置会保留。", 28))
	box.add_child(UiKit.button("保留当前旅程", close_modal, true))
	box.add_child(UiKit.button("清空进度，重新开始", func():
		close_modal()
		GameState.reset_game()
		SceneRouter.goto_map()
	))

func close_modal() -> void:
	if is_instance_valid(_modal):
		remove_child(_modal)
		_modal.queue_free()
	_modal = null
	get_tree().paused = false
	_set_media_paused(false)
	if is_instance_valid(_previous_focus):
		_previous_focus.grab_focus()

func notify(message: String) -> void:
	_toast_generation += 1
	var generation := _toast_generation
	if is_instance_valid(_toast):
		_toast.queue_free()
	_toast = PanelContainer.new()
	# 复用地图提示条样式，短提示不使用大面板纹样与最小尺寸。
	_toast.add_theme_stylebox_override("panel", UiKit.style(UiKit.DEEP, UiKit.GOLD, 14))
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 先给换行标签宽度，防止首次在零宽度下计算出一字一行的最小高度。
	_toast.size = Vector2(maxf(240, get_viewport().get_visible_rect().size.x - 320), 64)
	add_child(_toast)
	var l := UiKit.label(message, 26)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.add_child(l)
	_toast.resized.connect(_position_toast)
	_toast.minimum_size_changed.connect(_fit_toast.call_deferred)
	_fit_toast.call_deferred()
	_position_toast()
	await get_tree().create_timer(4.0).timeout
	if generation == _toast_generation and is_instance_valid(_toast):
		_toast.queue_free()

func _position_toast() -> void:
	if is_instance_valid(_toast):
		_toast.position = Vector2(160, maxf(12, get_viewport().get_visible_rect().size.y - _toast.size.y - 100))

func _fit_toast() -> void:
	if is_instance_valid(_toast):
		_toast.size.y = _toast.get_combined_minimum_size().y
		_position_toast()

func clear_notification() -> void:
	_toast_generation += 1
	if is_instance_valid(_toast): _toast.queue_free()
	_toast = null

func _set_media_paused(value: bool) -> void:
	var scene := get_tree().current_scene
	if is_instance_valid(scene) and scene.has_method("set_game_paused"):
		scene.set_game_paused(value)
