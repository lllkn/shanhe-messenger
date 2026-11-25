extends Node
## 真实窗口缩放、设置保存迁移与五站鼠标转向回归；不改玩家设置或存档。
var failures := 0
var checks := 0
var evidence := OS.get_environment("SHANHE_EVIDENCE")

func check(ok: bool, message: String) -> void:
	checks += 1
	print("PASS: " if ok else "FAIL: ", message)
	if not ok: failures += 1

func frames() -> void:
	for i in 5: await get_tree().process_frame

func shot(name: String) -> void:
	if evidence.is_empty() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(evidence.path_join(name + ".png"))

func motion(city: Node, sensitivity: float, relative: Vector2) -> void:
	GameSettings.update("camera_sensitivity", sensitivity)
	city.yaw = 0.0
	city.pitch = 0.65
	var event := InputEventMouseMotion.new()
	event.relative = relative # Deliberately varies with content scale.
	event.screen_relative = Vector2(40, -20)
	city._input(event)
	check(is_equal_approx(city.yaw, -0.12 * sensitivity) and is_equal_approx(city.pitch, 0.65 - 0.06 * sensitivity), city.station_id + " 速度 %.2f 使用屏幕位移，水平和垂直同比调整" % sensitivity)

func button_with(text: String) -> Button:
	for b in GameUI._modal.find_children("*", "Button", true, false):
		if b.text.begins_with(text): return b
	return null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().current_scene = null
	var original_save: String = GameState.save_path
	var original_settings: String = GameSettings.save_path
	var original_settings_bytes := PackedByteArray()
	if FileAccess.file_exists(original_settings): original_settings_bytes = FileAccess.get_file_as_bytes(original_settings)
	var original_save_bytes := PackedByteArray()
	if FileAccess.file_exists(original_save): original_save_bytes = FileAccess.get_file_as_bytes(original_save)
	GameSettings.save_path = "user://display-controls-test.cfg"
	var legacy := ConfigFile.new()
	legacy.set_value("ui", "volume", 0.35)
	legacy.set_value("ui", "text_speed", 1.75)
	legacy.set_value("ui", "fullscreen", false)
	legacy.save(GameSettings.save_path)
	GameSettings.load_settings()
	check(GameSettings.camera_sensitivity == 0.5 and GameSettings.volume == 0.35 and GameSettings.text_speed == 1.75, "旧设置自动获得50%视角速度并保留音量和文字速度")
	GameSettings.update("camera_sensitivity", 0.8)
	GameSettings.camera_sensitivity = 0.5
	GameSettings.load_settings()
	check(is_equal_approx(GameSettings.camera_sensitivity, 0.8), "重新加载后视角速度保留")
	GameSettings.update("camera_sensitivity", -1)
	check(GameSettings.camera_sensitivity == 0.25, "最低速度限25%")
	GameSettings.update("camera_sensitivity", 10)
	check(GameSettings.camera_sensitivity == 2.0, "最高速度限200%")
	SceneRouter.goto("home")
	while SceneRouter.is_switching(): await frames()
	GameUI.open_settings()
	await frames()
	var slider: HSlider = GameUI._modal.find_child("CameraSensitivity", true, false)
	check(slider != null and slider.value == 2.0, "设置显示已保存的视角速度")
	slider.value = 0.65
	check(is_equal_approx(GameSettings.camera_sensitivity, 0.65), "拖动滑杆即时更新设置")
	button_with("恢复推荐").pressed.emit()
	check(slider.value == 0.5 and GameSettings.camera_sensitivity == 0.5, "恢复推荐按钮回到50%并保存")
	check(get_window().content_scale_aspect == Window.CONTENT_SCALE_ASPECT_KEEP, "工程启用等比缩放")
	var original_size := get_window().size
	for size in [Vector2i(1280,720), Vector2i(1280,800), Vector2i(1440,1080), Vector2i(1600,720)]:
		get_window().size = size
		await frames()
		var transform := get_viewport().get_final_transform()
		check(is_equal_approx(transform.x.length(), transform.y.length()), "窗口 %s 的水平和垂直缩放一致" % size)
		var panel: Control = slider.get_parent().get_parent()
		check(get_viewport().get_visible_rect().encloses(panel.get_global_rect()), "窗口 %s 设置面板和底部按钮完整可见" % size)
		await shot("settings-%dx%d" % [size.x,size.y])
	if DisplayServer.get_name() != "headless":
		button_with("全屏显示").pressed.emit()
		await get_tree().create_timer(0.5).timeout
		await frames()
		check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN, "设置按钮实际进入全屏")
		var transform := get_viewport().get_final_transform()
		print("FULLSCREEN_SCALE x=", transform.x.length(), " y=", transform.y.length(), " window=", get_window().size)
		# Keep rounds the content rectangle to integer pixels (e.g. 1653.75 -> 1653).
		check(absf(transform.x.length() - transform.y.length()) * 720.0 <= 1.0, "实际全屏后仍保持等比（允许边界1像素取整）")
		check(get_viewport().get_visible_rect().encloses(slider.get_parent().get_parent().get_global_rect()), "全屏设置面板完整可见")
		await shot("settings-fullscreen")
		button_with("全屏显示").pressed.emit()
		await get_tree().create_timer(0.3).timeout
		check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED, "设置按钮退出全屏")
	GameUI.close_modal()
	GameState.save_path = "user://display-controls-test-save.cfg"
	GameState.reset_game()
	GameState.unlocked.assign(["lijiang","xianggelila","dali","puer","gucheng"])
	for id in GameState.unlocked:
		GameState.flags["flow/"+id+"/arrival"] = true
		SceneRouter.goto_station(id)
		while SceneRouter.is_switching(): await frames()
		await frames()
		var city := get_tree().current_scene
		city.window_focused = true
		city.mouse_look = true
		city.set_process(false)
		city.player.set_physics_process(false)
		for sensitivity in [0.25, 0.5, 1.0, 2.0]:
			motion(city, sensitivity, Vector2(20,-10))
		motion(city, 0.5, Vector2(80,-40))
		var yaw: float = city.yaw
		GameUI.open_settings()
		var event := InputEventMouseMotion.new()
		event.screen_relative = Vector2(50,0)
		city._input(event)
		check(is_equal_approx(yaw,city.yaw), id + " 设置暂停时鼠标不误转视角")
		GameUI.close_modal()
		city.mouse_look = false
		city._input(event)
		check(is_equal_approx(yaw,city.yaw), id + " Tab光标模式不转视角")
	GameSettings.save_path = original_settings
	GameSettings.load_settings()
	get_window().size = original_size
	GameState.save_path = original_save
	GameState.load_game()
	check(original_settings_bytes == FileAccess.get_file_as_bytes(original_settings) if FileAccess.file_exists(original_settings) else original_settings_bytes.is_empty(), "玩家原设置逐字节不变")
	check(original_save_bytes == FileAccess.get_file_as_bytes(original_save) if FileAccess.file_exists(original_save) else original_save_bytes.is_empty(), "玩家原存档逐字节不变")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://display-controls-test.cfg"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://display-controls-test-save.cfg"))
	print("DISPLAY_CONTROLS_TEST checks=",checks," failures=",failures," renderer=",DisplayServer.get_name())
	get_tree().quit(failures)
