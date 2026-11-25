extends "res://tests/test_dali_chain.gd"
func _ready() -> void:
	get_tree().current_scene=null
	original_save=GameState.save_path
	GameState.save_path="user://dali-input.cfg"
	GameState.reset_game();GameState.unlocked.assign(["lijiang","xianggelila","dali"])
	SceneRouter.goto_puzzle("dali",{"defer_reward":true,"flow_step":"pattern"})
	await settle()
	var puzzle:=get_tree().current_scene
	puzzle._offline=true;puzzle._api_key="";puzzle._on_intro_start()
	for round in 6:
		var guard:=0
		while puzzle._busy and guard<1200:
			await get_tree().process_frame
			guard+=1
		check(guard<1200,"小游戏本轮准备完成 "+str(round+1))
		if puzzle._phase=="a":
			if round==0: await shot("05-popo-draw")
			var correct: int = puzzle._option_ids.find(puzzle._topic["id"])
			var cell: Control=puzzle._options_root.get_child(correct)
			var button: Button=cell.find_children("*","Button",true,false)[0]
			click(button.get_global_rect().get_center(),true)
			click(button.get_global_rect().get_center(),false)
		else:
			for stroke in 3:
				var a: Vector2=puzzle._board.global_position+Vector2(120+stroke*80,110+stroke*50)
				motion(a)
				await get_tree().process_frame
				click(a,true)
				await get_tree().process_frame
				for part in 5:
					motion(a+Vector2(part*22,part*12))
					await get_tree().process_frame
				click(a+Vector2(88,48),false)
				await get_tree().process_frame
				print("DRAW_LOCAL ",puzzle._board.get_local_mouse_position()," strokes=",puzzle._player_strokes.size()," phase=",puzzle._phase," busy=",puzzle._busy)
			check(puzzle._player_strokes.size()==3,"画布实际接收三笔 "+str(round+1))
			if round==3: await shot("06-player-draw")
			click(puzzle._submit_btn.get_global_rect().get_center(),true)
			click(puzzle._submit_btn.get_global_rect().get_center(),false)
		var prev: int=puzzle._rounds_played
		guard=0
		while not puzzle._finished and puzzle._rounds_played==prev and guard<600:
			await get_tree().process_frame; guard+=1
	check(puzzle._finished and puzzle._success==6,"真实完成原版双三轮小游戏")
	check(GameState.has_flag("flow/dali/pattern") and not GameState.has_fragment("frag_zharan_pattern") and not GameState.is_unlocked("puer"),"游戏通过只记pattern，收尾前无碎片无下一站")
	_restore_save();print("INPUT_TEST failures=",failures);get_tree().quit(failures)
