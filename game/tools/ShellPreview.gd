extends Node
## 窗口模式截图，使用独立进度文件，截图结束恢复玩家进度。
const OUT := "res://visual-previews/shell/"
func _ready() -> void:
	get_tree().current_scene = null
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var original := GameState.save_path
	GameState.save_path = "user://shell-preview.cfg"
	GameState.reset_game()
	SceneRouter.goto("home")
	await _shot("01-home.png")
	SceneRouter.goto_map()
	await _shot("02-journey.png")
	get_tree().current_scene._canvas._markers[2].pressed.emit()
	await _shot("02b-locked-station.png")
	SceneRouter.goto_station("lijiang")
	await _shot("03-station.png")
	JourneyFlow.begin("lijiang")
	await get_tree().process_frame
	while SceneRouter.is_switching():
		await get_tree().process_frame
	get_tree().current_scene._continue()
	await _shot("04-dialogue.png")
	var dlg := get_tree().current_scene
	dlg._goto_line(3)
	dlg._continue()
	await _shot("05-choices.png")
	GameUI.open_pause()
	await _shot("06-pause.png")
	GameUI.open_settings()
	await _shot("07-settings.png")
	GameUI.close_modal()
	GameState.collect_fragment("frag_dongba_tea")
	SceneRouter.goto_codex()
	await _shot("08-codex.png")
	SceneRouter.goto_cine("example")
	await _shot("09-video-missing.png")
	for entry in [["Glyph", "10-glyph-intro.png"], ["Dye", "11-dye-intro.png"], ["Script", "12-puer-intro.png"]]:
		var puzzle: Node = load("res://scenes/puzzles/Puzzle" + entry[0] + ".tscn").instantiate()
		add_child(puzzle)
		await _shot(entry[1])
		puzzle.queue_free()
		await get_tree().process_frame
	GameState.save_path = original
	GameState.load_game()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://shell-preview.cfg"))
	get_tree().quit()

func _shot(name: String) -> void:
	await get_tree().process_frame
	while SceneRouter.is_switching():
		await get_tree().process_frame
	await get_tree().create_timer(0.65).timeout
	RenderingServer.force_draw()
	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT + name)
	print("SHOT: ", name)
