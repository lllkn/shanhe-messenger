extends Control
## DaliOnlineRunner —— 大理 PuzzlePattern 在线 LLM 实测（临时工具）
## 用法：Godot --path . res://tools/DaliOnlineRunner.tscn -- --position -3000,100
## 前提：user://llm.cfg 已配智谱 key。验证两件事：
##   ① 婆婆画：笔触由 GLM-4V 现场生成（非预设兜底）
##   ② 玩家画：用题目预设笔触当"玩家的画"提交，GLM-4V 视觉应猜中

const OUT_DIR := "user://technical-previews/"

var _scene: Node

func _ready() -> void:
	await _run()

func _run() -> void:
	_scene = load("res://scenes/puzzles/PuzzlePattern.tscn").instantiate()
	add_child(_scene)
	await _settle(4)
	print("[online] offline_flag=", _scene._offline, "（false=已识别 key，在线模式）")
	_scene._on_intro_start()

	# ---- 第 1 轮（婆婆画 · LLM 现场生成笔触）----
	await _wait_for(func() -> bool: return _scene._options_root.get_child_count() > 0, 30.0)
	print("[online] A轮题目=", _scene._topic["name"], " 离线降级=", _scene._offline)
	print("[online] 婆婆说：", _scene._strip.text)
	await get_tree().create_timer(0.4).timeout
	await _shot("dali_online_01_a_llm_draw.png")
	_scene._on_option(_scene._topic["id"])
	await _wait_round(2)

	# 第 2、3 轮直接选对（笔触同样来自 LLM）
	for r in [2, 3]:
		await _wait_for(func() -> bool: return _scene._options_root.get_child_count() > 0, 30.0)
		_scene._on_option(_scene._topic["id"])
		if r < 3:
			await _wait_round(r + 1)

	# ---- 第 4 轮（玩家画 · GLM-4V 视觉猜）----
	await _wait_for(func() -> bool: return _scene._phase == "b" and _scene._submit_btn.visible and not _scene._submit_btn.disabled, 30.0)
	print("[online] B轮题目=", _scene._topic["name"])
	# 用题目预设笔触描一遍，模拟"玩家照着画得很好"
	_scene._player_strokes = _scene._scale_strokes(_scene._topic["strokes"]["strokes"])
	_scene._board.queue_redraw()
	await get_tree().create_timer(0.4).timeout
	await _shot("dali_online_02_b_player.png")
	_scene._on_submit()
	await _wait_for(func() -> bool: return not _scene._busy, 30.0)
	print("[online] 提交后婆婆说：", _scene._strip.text)
	print("[online] 成绩：success=", _scene._success, " results=", _scene._results)
	await get_tree().create_timer(0.3).timeout
	await _shot("dali_online_03_b_result.png")

	print("[online] quitting, 最终离线降级=", _scene._offline)
	get_tree().quit()

func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame

func _wait_for(cond: Callable, timeout: float) -> void:
	var waited := 0.0
	while not cond.call() and waited < timeout:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1

func _wait_round(n: int) -> void:
	await _wait_for(func() -> bool: return _scene._rounds_played >= n or _scene._solved, 30.0)

func _shot(shot_name: String) -> void:
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT_DIR + shot_name)
	print("saved ", shot_name)
