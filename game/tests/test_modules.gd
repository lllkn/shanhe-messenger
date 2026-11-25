extends Node
var failures := 0
func check(ok: bool, message: String) -> void:
	if ok:
		print("PASS: ", message)
	else:
		failures += 1
		printerr("FAIL: ", message)

func _ready() -> void:
	var dye: Node = load("res://scenes/puzzles/PuzzleDye.tscn").instantiate()
	add_child(dye)
	check(dye._gs != GameState and dye.station_id == "xianggelila", "香格里拉独立入口与mock")
	dye._on_intro_start()
	dye._on_intro_start()
	check(dye._started, "说明页重复点击不会重复开局")
	dye._debug_fill_all()
	await get_tree().create_timer(2.0).timeout
	check(dye._level == 1 and dye._l1_done and dye._action_button.visible and dye._speech.visible, "填色完成后丹僧邀请进入下一关")
	dye._enter_level2()
	check(dye._level == 2 and dye._phase == "idle", "确认后进入染缸")
	dye._debug_commit("青")
	GameUI.open_pause()
	await get_tree().create_timer(1.5).timeout
	check(dye._phase == "fire", "暂停期间火候定时器冻结")
	GameUI.close_modal()
	await get_tree().create_timer(1.3).timeout
	check(dye._phase == "stir", "恢复后进入搅缸")
	var remaining: float = dye._stir_left
	GameUI.open_pause()
	await get_tree().create_timer(0.3).timeout
	check(is_equal_approx(remaining, dye._stir_left), "暂停期间搅缸倒计时冻结")
	GameUI.close_modal()
	for color in ["青", "赤", "黄", "白", "黑"]:
		if color != "青":
			dye._debug_commit(color)
			await get_tree().create_timer(1.3).timeout
		dye._debug_force_stir()
		await get_tree().create_timer(0.7).timeout
	await get_tree().create_timer(2.0).timeout
	check(dye._finished and dye._gs.has_fragment("frag_dye_five"), "染缸完整结算与内存奖励")
	dye.queue_free()
	await get_tree().process_frame
	var puer: Node = load("res://scenes/puzzles/PuzzleScript.tscn").instantiate()
	add_child(puer)
	puer._on_intro_start()
	for id in puer._volume_ids:
		puer._on_pick_leaf(id)
	await get_tree().create_timer(1.8).timeout
	puer._on_punch(0)
	await get_tree().create_timer(0.4).timeout
	puer._on_punch(1)
	for _i in 60:
		if puer._level == 2:
			break
		await get_tree().create_timer(0.05).timeout
	await get_tree().create_timer(0.5).timeout
	check(puer._level == 2, "普洱挑叶打孔后进入穿绳")
	puer._order = puer._correct_order.duplicate()
	puer._reflow(0.0, true)
	puer._on_verify()
	await get_tree().create_timer(6.0).timeout
	check(puer._solved and not puer._finished, "普洱验证完成进入誓约演出，尚未提前发奖")
	# 誓约由玩家确认后调用真实基类结算。
	puer._complete()
	await get_tree().create_timer(2.1).timeout
	check(puer._finished and puer._gs.has_fragment("frag_beiye_oath"), "普洱真实结算使用内存奖励")
	check(GameState.save_path == GameState.SAVE_PATH, "独立模块未切换主线存档")
	print("MODULE FAILURES: ", failures)
	get_tree().quit(failures)
