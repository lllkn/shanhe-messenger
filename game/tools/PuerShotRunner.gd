extends Control
## PuerShotRunner —— 普洱 PuzzleScript 截图跑测器（临时，用完即删）
## 用法：Godot --path . res://tools/PuerShotRunner.tscn -- --position -3000,100

const OUT_DIR := "user://technical-previews/"

var _scene: Node

func _ready() -> void:
	await _run()

func _run() -> void:
	_scene = load("res://scenes/puzzles/PuzzleScript.tscn").instantiate()
	add_child(_scene)
	await _settle(4)
	await _shot("puer_01_intro.png")

	_scene._on_intro_start()
	await _settle(4)
	await _shot("puer_02_level1.png")

	# 故意点一张干扰叶，看抖动/提示
	var decoy := ""
	for lid in _scene._l1_cards:
		if not lid in _scene._volume_ids:
			decoy = lid
			break
	_scene._on_pick_leaf(decoy)
	await get_tree().create_timer(0.5).timeout
	await _shot("puer_03_wrong_leaf.png")

	# 挑齐本匣 6 张
	for vid in _scene._volume_ids:
		_scene._on_pick_leaf(vid)
		await get_tree().create_timer(0.18).timeout
	await get_tree().create_timer(2.6).timeout
	await _shot("puer_04_punch_ready.png")

	_scene._on_punch(0)
	await get_tree().create_timer(0.7).timeout
	await _shot("puer_05_punch1.png")
	_scene._on_punch(1)
	# 等真正的切关完成（level 变 2 且淡入结束），避免截到过渡半透明
	for i in 200:
		await get_tree().process_frame
		if _scene._level == 2:
			break
	await get_tree().create_timer(1.2).timeout
	await _shot("puer_06_level2.png")

	# 直接过目（乱序）→ 第一张念不通的叶子掉地上
	_scene._on_verify()
	await get_tree().create_timer(4.0).timeout
	await _shot("puer_07_drop.png")

	# 摆成正确顺序再过目 → 誓约演出
	_scene._busy = false
	_scene._verify_btn.disabled = false
	for lid in _scene._floor_rows.keys():
		var row: Control = _scene._floor_rows[lid]
		_scene._floor_rows.erase(lid)
		_scene._floor_order.erase(lid)
		_scene._l2_rows[lid] = row
	_scene._order = _scene._correct_order.duplicate()
	_scene._reflow(0.0, true)
	await get_tree().create_timer(0.5).timeout
	_scene._on_verify()
	await get_tree().create_timer(5.0).timeout
	await _shot("puer_08_oath.png")

	print("quitting")
	get_tree().quit()

func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame

func _shot(shot_name: String) -> void:
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT_DIR + shot_name)
	print("saved ", shot_name)
