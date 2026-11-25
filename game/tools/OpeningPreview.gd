extends Node
## 真窗口观看完整视频，捕获末帧、云幕和主页；-- --skip 可仅检查跳过文字流程。
const OUT := "res://visual-previews/opening/"
var _opening: Control
var _skip_mode := false
var _output: String

func _ready() -> void:
	get_tree().current_scene = null
	_skip_mode = "--skip" in OS.get_cmdline_user_args()
	_output = OUT + ("skip/" if _skip_mode else "full/")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output))
	SceneRouter.goto_path("res://scenes/OpeningScene.tscn", {}, "home")
	await get_tree().process_frame
	while SceneRouter.is_switching():
		await get_tree().process_frame
	_opening = get_tree().current_scene
	# 自动录证期间阻止窗口外来按键/点击干扰完整播放；正式启动保留全部输入。
	_opening.set_process_unhandled_key_input(false)
	_opening._skip.disabled = true
	GameUI.set_process_input(false)
	await get_tree().create_timer(1.0).timeout
	await _shot("01-video.png")
	if _skip_mode:
		_opening._skip.pressed.emit()
		await get_tree().create_timer(0.2).timeout
		await _shot("02-summary.png")
		(get_viewport().gui_get_focus_owner() as Button).pressed.emit()
	else:
		# Godot 原生 Theora 不支持 seek，从头播放验证 finished 信号与音画解码。
		while _opening._player.stream_position < 82.5 and _opening.phase == _opening.Phase.VIDEO:
			await get_tree().process_frame
		if _opening.phase != _opening.Phase.VIDEO:
			printerr("FULL PREVIEW FAILED: video did not reach final window shot")
			get_tree().quit(1)
			return
		await _shot("03-window.png")
		while _opening.phase == _opening.Phase.VIDEO:
			await get_tree().process_frame
	await get_tree().create_timer(0.75).timeout
	await _shot("04-covering.png")
	while _opening.phase == _opening.Phase.COVERING:
		await get_tree().process_frame
	await _shot("05-covered.png")
	await get_tree().create_timer(1.3).timeout
	await _shot("06-clouds-open.png")
	while _opening.phase != _opening.Phase.HOME:
		await get_tree().process_frame
	await _shot("07-home.png")
	print("OPENING PREVIEW: full pipeline completed; menu enabled=", not _opening._home._start_button.disabled)
	get_tree().quit()

func _shot(filename: String) -> void:
	await get_tree().process_frame
	RenderingServer.force_draw()
	get_viewport().get_texture().get_image().save_png(_output + filename)
	print("SHOT: ", filename, " phase=", _opening.phase, " video_position=", _opening._player.stream_position)
