extends Node
## 不写玩家存档；检查媒体、暂停、跳过简介、云幕、主菜单和正常返回入口。
var _failures := 0

func _check(condition: bool, message: String) -> void:
	print("PASS: " if condition else "FAIL: ", message)
	if not condition:
		_failures += 1

func _settle() -> void:
	await get_tree().process_frame
	while SceneRouter.is_switching():
		await get_tree().process_frame
	await get_tree().process_frame

func _ready() -> void:
	get_tree().current_scene = null
	var progress_before := [GameState.fragments.duplicate(true), GameState.flags.duplicate(true), GameState.current_station]
	_check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/OpeningScene.tscn", "F5 主入口是开场")
	SceneRouter.goto_path("res://scenes/OpeningScene.tscn", {}, "home")
	await _settle()
	var opening := get_tree().current_scene
	_check(opening.phase == opening.Phase.VIDEO and opening._player.is_playing(), "真实 OGV 加载并自动播放")
	_check(opening._home._start_button.disabled and not opening._home._menu_root.visible, "开场期间菜单隐藏且不能提前点击")
	await get_tree().create_timer(0.4).timeout
	var position: float = opening._player.stream_position
	_check(position > 0.0, "视频时间实际推进")
	GameUI.open_pause()
	_check(get_tree().paused and opening._player.paused, "Esc 暂停同时暂停影像")
	var pause_buttons: Array[String] = []
	_collect_buttons(GameUI._modal, pause_buttons)
	_check("跳过影像 · 查看简介" in pause_buttons and not "返回旅程总览" in pause_buttons and not "返回标题" in pause_buttons, "开场暂停菜单的跳过也先读简介")
	await get_tree().create_timer(0.2).timeout
	_check(is_equal_approx(position, opening._player.stream_position), "暂停后影像时间冻结")
	GameUI.close_modal()
	_check(not opening._player.paused and not get_tree().paused, "继续播放恢复")
	opening._skip.pressed.emit()
	opening._request_skip()
	_check(opening.phase == opening.Phase.SUMMARY and opening._summary.visible and not opening._player.is_playing(), "重复跳过安全，停声音并展示剧情简介")
	var summary_button := get_viewport().gui_get_focus_owner() as Button
	_check(summary_button != null and summary_button.text == "了解了 · 进入主页面", "简介等待玩家明确继续")
	_check(opening._summary.get_global_rect().end.y <= 720, "简介在基准视口中")
	summary_button.pressed.emit()
	opening._begin_transition()
	_check(opening.phase == opening.Phase.COVERING and opening._curtain.visible, "继续后云幕开始遮盖")
	await get_tree().create_timer(0.2).timeout
	GameUI.open_pause()
	var amount: float = opening._cloud_material.get_shader_parameter("opening")
	await get_tree().create_timer(0.2).timeout
	_check(is_equal_approx(amount, opening._cloud_material.get_shader_parameter("opening")), "暂停期间云幕动画冻结")
	GameUI.close_modal()
	await get_tree().create_timer(1.3).timeout
	_check(opening.phase == opening.Phase.REVEALING and not opening._video_stage.visible and not opening._summary.visible, "完整云幕内替换为主页面")
	_check(opening._home._start_button.disabled, "云散过程中禁止菜单点击")
	await get_tree().create_timer(3.0).timeout
	_check(opening.phase == opening.Phase.HOME and not opening._curtain.visible and not opening._home._start_button.disabled, "云散完成，主菜单可操作")
	_check(opening._player.stream == null, "过场后释放视频解码资源")
	_check(progress_before == [GameState.fragments, GameState.flags, GameState.current_station], "开场流程不写入或清空旅程进度")
	opening._home._start_button.pressed.emit()
	await _settle()
	_check(get_tree().current_scene.name == "MapScene", "踏上古道进入原有地图")
	SceneRouter.goto("home")
	await _settle()
	_check(get_tree().current_scene.name == "Main", "返回标题直接到主页，不重复开场")
	SceneRouter.goto_path("res://scenes/OpeningScene.tscn", {}, "home")
	await _settle()
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.physical_keycode = KEY_SPACE
	space.pressed = true
	Input.parse_input_event(space)
	await get_tree().process_frame
	_check(get_tree().current_scene.phase == get_tree().current_scene.Phase.SUMMARY, "实际空格输入跳过影像并展示简介")
	space.pressed = false
	Input.parse_input_event(space)
	SceneRouter.goto("home")
	await _settle()
	# 可复用脚本的无流回退不会把玩家困在黑屏。
	var fallback: Control = load("res://scenes/OpeningScene.tscn").instantiate()
	fallback.video_stream = null
	add_child(fallback)
	_check(fallback.phase == fallback.Phase.SUMMARY, "无视频流时以同一简介继续")
	fallback.queue_free()
	GameMusic.stop()
	await get_tree().create_timer(0.15).timeout
	print("OPENING FAILURES: ", _failures)
	get_tree().quit(_failures)

func _collect_buttons(node: Node, result: Array[String]) -> void:
	if node is Button:
		result.append(node.text)
	for child in node.get_children():
		_collect_buttons(child, result)
