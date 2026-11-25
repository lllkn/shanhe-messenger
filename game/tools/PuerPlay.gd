extends Node
## 独立普洱新旅程；专用试玩档，不改正式玩家进度。
func _ready() -> void:
	get_tree().current_scene = null
	GameState.save_path = "user://puer-play.cfg"
	GameState.reset_game()
	GameState.unlocked.assign(["lijiang","xianggelila","dali","puer"])
	SceneRouter.goto_station("puer")
