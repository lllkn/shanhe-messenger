extends Node
## 新外壳与模块接入回归；使用独立测试存档，结束后恢复真实进度只读载入。
var _failures := 0
var _gs: Node

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: ", message)
	else:
		print("PASS: ", message)

func _settle() -> void:
	await get_tree().process_frame
	while SceneRouter.is_switching():
		await get_tree().process_frame
	await get_tree().process_frame

func _ready() -> void:
	# 路由不能释放测试驱动节点。
	get_tree().current_scene = null
	_gs = GameState
	var actual_path: String = _gs.save_path
	_gs.save_path = "user://shell-test.cfg"
	_gs.reset_game()
	SceneRouter.goto("home")
	await _settle()
	_check(get_tree().current_scene.name == "Main", "玩家标题入口可运行")
	SceneRouter.goto_map()
	await _settle()
	_check(get_tree().current_scene.name == "MapScene", "总览和5站渲染")
	var journey := get_tree().current_scene
	_check(journey._canvas != null and journey._canvas._markers.size() == 5, "长卷创建5个可操作站点")
	journey._canvas._markers[2].pressed.emit()
	await get_tree().process_frame
	_check(journey._selected == "dali" and journey._detail.get_child(-1).disabled and GameState.current_station.is_empty(), "锁定站点可预览，不能推进或进入")
	journey._canvas._markers[0].pressed.emit()
	await get_tree().process_frame
	_check(not journey._detail.get_child(-1).disabled and journey._detail.get_parent().get_global_rect().end.x <= 1280 and journey._detail.get_parent().get_global_rect().end.y <= 720, "已解锁入口可用，长卷详情完整显示")
	var previous: Dictionary = SceneRouter.params.duplicate(true)
	var old_scene := get_tree().current_scene
	var errors: Array = []
	SceneRouter.navigation_failed.connect(func(msg): errors.append(msg))
	SceneRouter.goto_path("res://scenes/missing.tscn", {"station": "dali"})
	await _settle()
	_check(get_tree().current_scene == old_scene and SceneRouter.params == previous and errors.size() == 1, "缺失场景留在原页，参数不污染")
	SceneRouter.goto_station("dali")
	_check(GameState.current_station.is_empty(), "锁定站点不能进入")
	# 丽江完整新链路由LijiangChainTest实测；此处独立回归旧对话及外壳。
	for step in ["arrival", "interviews", "dongba_visit"]:
		GameState.set_flag("flow/lijiang/" + step)
	SceneRouter.goto_station("lijiang")
	await _settle()
	_check(SceneRouter.current_key == "city" and get_tree().current_scene.player != null, "站点入口进入真实3D地图")
	SceneRouter.goto_dialogue("sample_lijiang", {"station":"lijiang", "flow_step":"legacy_sample", "city_context":get_tree().current_scene.city_context()})
	await _settle()
	var dialogue := get_tree().current_scene
	_check(dialogue.name == "DialogueScene" and dialogue.line_idx == 0, "数据流程进入丽江对话")
	var guard := 0
	while not dialogue._finished and guard < 60:
		if dialogue._has_choices():
			dialogue._choose(0)
		else:
			dialogue._continue()
		guard += 1
	await _settle()
	_check(SceneRouter.current_key == "city" and GameState.has_flag("flow/lijiang/legacy_sample"), "对话完成返回城市并记步骤")
	_check(GameState.has_flag("gift_bookmark"), "对话选项动作记录")
	JourneyFlow.begin("lijiang")
	await _settle()
	var puzzle := get_tree().current_scene
	_check(puzzle.name == "PuzzleGlyph" and puzzle.station_id == "lijiang", "下一流程进入真实小游戏")
	GameUI.open_pause()
	_check(get_tree().paused, "全局暂停生效")
	var tick: float = puzzle._countdown
	await get_tree().create_timer(0.15).timeout
	_check(is_equal_approx(puzzle._countdown, tick), "暂停中小游戏计时冻结")
	GameUI.close_modal()
	_check(not get_tree().paused, "继续恢复游戏")
	puzzle._exit()
	await _settle()
	_check(GameState.get_fragment_count() == 0 and not GameState.is_completed("lijiang"), "中途退出不发奖励")
	# 通过基类真实结算入口，避免只测试手写的状态赋值。
	SceneRouter.goto_puzzle("lijiang", {"flow_step": "glyph"})
	await _settle()
	puzzle = get_tree().current_scene
	puzzle._on_intro_start()
	puzzle._level = 2
	puzzle._l1_root.visible = false
	puzzle._l2_root.visible = true
	for pid in puzzle._page_correct_order:
		puzzle._slots[int(puzzle._page_correct_order[pid]) - 1]["page_id"] = pid
	puzzle._refresh_submit()
	puzzle._on_submit()
	await get_tree().create_timer(2.25).timeout
	_check(GameState.has_fragment("frag_dongba_tea") and GameState.is_unlocked("xianggelila"), "结算正确发奖励并解锁下一站")
	puzzle._back_to_map()
	await _settle()
	_check(SceneRouter.current_key == "city", "主线结算回到本站地图")
	GameState.collect_fragment("unknown_fragment")
	_check(GameState.get_fragment_count() == 1, "拒绝未注册的奖励ID")
	# 碎片归属独立于current_station。
	GameState.collect_fragment("frag_dye_five")
	_check(GameState.is_completed("xianggelila") and GameState.is_unlocked("dali"), "按碎片所属站点结算")
	GameState.collect_fragment("frag_beiye_oath")
	_check(not GameState.has_fragment("frag_beiye_oath"), "未解锁站点不提前获奖")
	GameState.mark_puzzle_solved("dali")
	_check(not GameState.is_completed("dali"), "未集齐本站碎片不误标完成")
	GameState.collect_fragment("frag_zharan_pattern")
	GameState.collect_fragment("frag_beiye_oath")
	GameState.mark_puzzle_solved("gucheng")
	_check(GameState.can_enter_finale() and GameState.evaluate_ending() == "kaiguan", "终章状态与现有结局契约兼容")
	GameState.load_game()
	_check(GameState.get_fragment_count() == 4 and GameState.can_enter_finale(), "独立存档重载保持进度")
	SceneRouter.goto_codex()
	await _settle()
	_check(get_tree().current_scene.name == "CodexScene", "图鉴呈现已收集信物")
	SceneRouter.goto_cine("example", {"station": "lijiang", "flow_step": "test-video"})
	await _settle()
	_check(get_tree().current_scene.name == "CineScene" and not GameState.has_flag("flow/lijiang/test-video"), "缺失视频不推进旅程")
	SceneRouter.goto_dialogue("missing")
	await _settle()
	dialogue = get_tree().current_scene
	dialogue._continue()
	_check(dialogue._finished and dialogue.line_idx == -1, "缺失对话可安全退出，不越界")
	# F6实例必须保留自己的station和mock，不能继承残留路由参数。
	SceneRouter.params = {"station": "lijiang"}
	var standalone: Node = load("res://scenes/puzzles/PuzzleScript.tscn").instantiate()
	add_child(standalone)
	_check(standalone.station_id == "puer" and standalone._gs != GameState, "独立小游戏使用内存状态，不污染主线")
	standalone.queue_free()
	GameUI.close_modal()
	_gs.save_path = actual_path
	_gs.load_game()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://shell-test.cfg"))
	print("SHELL FAILURES: ", _failures)
	get_tree().quit(_failures)
