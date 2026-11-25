extends Node
## 专用试玩存档，保护玩家主线进度。
func _ready() -> void:
	get_tree().current_scene = null
	GameState.save_path = "user://xianggelila-play.cfg"
	GameState.reset_game()
	GameState.collect_fragment("frag_dongba_tea")
	SceneRouter.goto_station("xianggelila")
