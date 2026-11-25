extends Node
## 验证四城真实输入、UI点击和弹层不会互相抢鼠标，使用独立存档。
var failures := 0
var checks := 0
var output := OS.get_environment("CITY_MOUSE_OUTPUT")

func check(ok: bool, message: String) -> void:
	checks += 1
	print("PASS: " if ok else "FAIL: ", message)
	if not ok: failures += 1

func frame() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

func key(code: int) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		get_viewport().push_input(event, true)
		await frame()

func click(button: Button) -> void:
	var pos := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	get_viewport().push_input(motion, true)
	await frame()
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = pos
		event.pressed = pressed
		get_viewport().push_input(event, true)
		await frame()

func motion() -> void:
	var event := InputEventMouseMotion.new()
	event.relative = Vector2(30, 10)
	event.screen_relative = event.relative
	get_viewport().push_input(event, true)
	await frame()

func shot(name: String) -> void:
	if output.is_empty(): return
	RenderingServer.force_draw()
	get_viewport().get_texture().get_image().save_png(output.path_join(name + ".png"))

func _ready() -> void:
	get_tree().current_scene = null
	var original_save: String = GameState.save_path
	GameState.save_path = "user://city-mouse-test.cfg"
	GameState.reset_game()
	GameState.unlocked.assign(["lijiang", "xianggelila", "dali", "puer"])
	for id in ["lijiang", "xianggelila", "dali", "puer"]:
		GameState.set_flag("flow/" + id + "/arrival")
		SceneRouter.goto_station(id)
		await frame()
		while SceneRouter.is_switching(): await frame()
		var city := get_tree().current_scene
		while not city.walk_guide.ready: await get_tree().physics_frame
		get_window().grab_focus()
		await get_tree().create_timer(0.1).timeout
		await frame()
		check(city.mouse_look and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED if city.window_focused else Input.mouse_mode == Input.MOUSE_MODE_VISIBLE), id + " 默认视角模式按窗口焦点捕获或释放鼠标")
		check(city.hud.find_child("MouseToggle", true, false) == null and city.control_help.text.begins_with("视角模式"), id + " 无金色切换按钮，保留文字提示")
		var yaw: float = city.yaw
		await motion()
		check(not is_equal_approx(yaw, city.yaw) if city.window_focused else is_equal_approx(yaw, city.yaw), id + " 真实鼠标输入仅在窗口聚焦时转视角")
		await key(KEY_TAB)
		check(not city.mouse_look and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, id + " Tab释放鼠标")
		check(city.control_help.text.begins_with("鼠标模式") and city.control_help.text.contains("Tab 返回视角"), id + " 文字提示同步")
		yaw = city.yaw
		await motion()
		check(is_equal_approx(yaw, city.yaw), id + " 鼠标模式不转视角")
		var target: String = city.hotspots[1]["id"]
		await click(city.checklist.get_child(1))
		check(city.target_id == target and not city.mouse_look, id + " 光标模式真实点击任务改变引路目标")
		check(city.control_help.get_parent().get_global_rect().encloses(city.control_help.get_global_rect()), id + " 模式说明无溢出")
		await shot(id + "-cursor")
		await key(KEY_TAB)
		check(city.mouse_look and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED if city.window_focused else Input.mouse_mode == Input.MOUSE_MODE_VISIBLE), id + " 再次Tab恢复视角偏好并按窗口焦点处理鼠标")
		check(get_viewport().gui_get_focus_owner() == null, id + " 切回视角释放UI焦点")
		await shot(id + "-look")
		await key(KEY_TAB)
		await key(KEY_ESCAPE)
		check(get_tree().paused and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, id + " Esc仍然暂停并显示鼠标")
		await key(KEY_TAB)
		check(not city.mouse_look, id + " 暂停期间Tab不改鼠标偏好")
		await key(KEY_ESCAPE)
		check(not get_tree().paused and not city.mouse_look and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, id + " 关闭暂停保留鼠标模式")
		city.open_conversation(city.story["arrival"], "arrival")
		await frame()
		check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, id + " 对话期间显示鼠标")
		await key(KEY_TAB)
		check(not city.mouse_look, id + " 对话期间Tab不抢回鼠标")
		city.dialogue._finish()
		await frame()
		check(not city.mouse_look and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, id + " 对话结束仍可用光标操作")
		await key(KEY_TAB)
		check(city.mouse_look and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED if city.window_focused else Input.mouse_mode == Input.MOUSE_MODE_VISIBLE), id + " 再次Tab恢复视角偏好并按窗口焦点处理鼠标")
	GameState.save_path = original_save
	GameState.load_game()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://city-mouse-test.cfg"))
	print("CITY_MOUSE_TEST checks=", checks, " failures=", failures)
	get_tree().quit(failures)
