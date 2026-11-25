extends Node
## 大理独立新旅程，使用专用试玩档，不覆盖正式玩家存档。
func _ready() -> void:
	get_tree().current_scene = null
	GameState.save_path = "user://dali-play.cfg"
	if OS.get_cmdline_user_args().has("--resume-preview") and FileAccess.file_exists(GameState.save_path):
		GameState.load_game()
	else:
		GameState.reset_game()
		GameState.unlocked.assign(["lijiang", "xianggelila", "dali"])
	SceneRouter.goto_station("dali")
