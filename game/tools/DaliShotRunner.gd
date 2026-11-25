extends Control
## DaliShotRunner —— 大理 PuzzlePattern 截图跑测器（临时，用完即删）
## 用法：Godot --path . res://tools/DaliShotRunner.tscn -- --position -3000,100
## 强制离线模式：婆婆画走预设笔触，玩家画满 3 笔提交即过。
## 编排原则：状态驱动等待（不用盲等），关键节点断言后再截图（经验#18）。

const OUT_DIR := "user://technical-previews/"

var _scene: Node

func _ready() -> void:
	await _run()

func _run() -> void:
	_scene = load("res://scenes/puzzles/PuzzlePattern.tscn").instantiate()
	add_child(_scene)
	_scene._debug_force_offline()
	await _settle(4)
	await _shot("dali_01_intro.png")

	_scene._on_intro_start()

	# ---- 第 1 轮（婆婆画）：等选项亮起 ----
	await _wait_options()
	await get_tree().create_timer(0.4).timeout
	await _shot("dali_02_a_options.png")

	# 故意选错一次 → 疑惑表情 + 提示
	var wrong := ""
	for pid in _scene._option_ids:
		if pid != _scene._topic["id"]:
			wrong = pid
			break
	_scene._on_option(wrong)
	await get_tree().create_timer(0.9).timeout
	await _shot("dali_03_a_wrong.png")

	# 选对 → 进第 2 轮
	_scene._on_option(_scene._topic["id"])
	await _wait_round(2)

	# ---- 第 2、3 轮：等选项后直接选对 ----
	for r in [2, 3]:
		await _wait_options()
		_scene._on_option(_scene._topic["id"])
		if r < 3:
			await _wait_round(r + 1)

	# ---- 第 4 轮（玩家画）：等提交钮亮起 ----
	await _wait_phase_b()
	await get_tree().create_timer(0.4).timeout
	await _shot("dali_04_b_topic.png")

	_scene._debug_doodle()
	await get_tree().create_timer(0.3).timeout
	await _shot("dali_05_b_doodle.png")
	_scene._on_submit()
	await _wait_round(5)

	# ---- 第 5、6 轮玩家画快速过 ----
	for r in [5, 6]:
		await _wait_phase_b()
		_scene._debug_doodle()
		_scene._on_submit()
		if r < 6:
			await _wait_round(r + 1)

	# ---- 通关卡 ----
	await _wait_for(func() -> bool: return _scene._solved, 12.0)
	await get_tree().create_timer(1.0).timeout
	await _shot("dali_06_win.png")

	# 点「收下这份纹样档案」→ 结算页（基类 2 秒后出现）
	print("[runner] before accept: solved=", _scene._solved, " finished=", _scene._finished, " card_layer=", _scene._win_card_layer)
	_scene._debug_accept_win()
	print("[runner] after accept: finished=", _scene._finished)
	await _wait_for(func() -> bool: return _scene._win_layer != null, 8.0)
	print("[runner] win_layer=", _scene._win_layer)
	await get_tree().create_timer(1.2).timeout
	await _shot("dali_07_result.png")

	print("quitting solved=", _scene._solved, " success=", _scene._success)
	get_tree().quit()

func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame

func _wait_for(cond: Callable, timeout: float) -> void:
	var waited := 0.0
	while not cond.call() and waited < timeout:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1

func _wait_options() -> void:
	await _wait_for(func() -> bool: return _scene._options_root.get_child_count() > 0, 15.0)

func _wait_phase_b() -> void:
	await _wait_for(func() -> bool: return _scene._phase == "b" and _scene._submit_btn.visible and not _scene._submit_btn.disabled, 15.0)

func _wait_round(n: int) -> void:
	await _wait_for(func() -> bool: return _scene._rounds_played >= n or _scene._solved, 15.0)

func _shot(shot_name: String) -> void:
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT_DIR + shot_name)
	print("saved ", shot_name)
