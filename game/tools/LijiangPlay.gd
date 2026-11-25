extends Node
## 独立丽江新旅程，使用专用试玩档，保护正式玩家进度。
func _ready() -> void:
	get_tree().current_scene = null
	GameState.save_path = "user://lijiang-play.cfg"
	GameState.reset_game()
	SceneRouter.goto_station("lijiang")
