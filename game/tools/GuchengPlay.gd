extends Node
## 普洱完成后的独立终章试玩；不读写正式存档。
func _ready() -> void:
	get_tree().current_scene = null
	GameState.save_path = "user://gucheng-play.cfg"
	GameState.reset_game()
	for fragment in ["frag_dongba_tea", "frag_dye_five", "frag_zharan_pattern", "frag_beiye_oath"]:
		GameState.collect_fragment(fragment)
	SceneRouter.goto_station("gucheng")
