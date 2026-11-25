extends Node
func _ready() -> void:
	get_tree().current_scene = null
	# 预览使用独立临时存档，不改真实玩家进度。
	var actual: String = GameState.save_path
	GameState.save_path = "user://city-preview.cfg"
	GameState.unlocked.assign(["lijiang", "xianggelila", "dali", "puer", "gucheng"])
	var id := OS.get_environment("CITY_PREVIEW")
	if id.is_empty(): id = "lijiang"
	SceneRouter.goto_station(id)
	await get_tree().process_frame
	while SceneRouter.is_switching(): await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout
	var city := get_tree().current_scene
	if OS.get_cmdline_user_args().has("--shot"):
		RenderingServer.force_draw()
		var err := get_viewport().get_texture().get_image().save_png("res://../drafts/city-integration-2026-10-09/%s-spawn.png" % id)
		print("SHOT ", id, " error=", err)
		GameState.save_path = actual
		GameState.load_game()
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://city-preview.cfg"))
		get_tree().quit(err)
