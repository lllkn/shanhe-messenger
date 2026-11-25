extends "res://tests/test_dali_chain.gd"
func _ready() -> void:
	original_save=GameState.save_path
	GameState.save_path="user://dali-reward-regression.cfg"
	GameState.reset_game();GameState.unlocked.assign(["lijiang","xianggelila","dali"])
	SceneRouter.params={"station":"dali","defer_reward":true}
	var mock: Node=load("res://scenes/puzzles/PuzzlePattern.tscn").instantiate()
	add_child(mock)
	check(mock._gs!=GameState and not mock._defer_city_reward(),"F6内存mock不受城市defer参数影响")
	mock._solved=true;mock._complete()
	await get_tree().create_timer(2.2).timeout
	check(mock._finished and mock._gs.has_fragment("frag_zharan_pattern") and mock._win_layer!=null,"独立小游戏原奖励及结算页保留")
	check(not GameState.has_fragment("frag_zharan_pattern"),"mock结算不污染主线档")
	mock.queue_free();await get_tree().process_frame
	get_tree().current_scene=null
	SceneRouter.goto_puzzle("dali")
	await settle()
	var legacy:=get_tree().current_scene
	check(legacy._gs==GameState and not legacy._defer_city_reward(),"旧直接入口仍用原领奖方式")
	legacy._solved=true;legacy._complete()
	await get_tree().create_timer(2.2).timeout
	check(GameState.has_fragment("frag_zharan_pattern") and legacy._win_layer!=null,"旧入口结算真实发原碎片且保留原结算页")
	_restore_save();print("DALI_REWARD_REGRESSION checks=",checks," failures=",failures);get_tree().quit(failures)
