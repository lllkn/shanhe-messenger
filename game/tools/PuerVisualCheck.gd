extends Control
## 贝叶关卡视觉回归：使用内存 MockGameState，不写玩家进度。
## 用法：Godot --path game --fixed-fps 60 res://tools/PuerVisualCheck.tscn

const OUT_DIR := "res://visual-previews/puer/after/"

var _scene: Node

func _ready() -> void:
	await _run()

func _run() -> void:
	_scene = load("res://scenes/puzzles/PuzzleScript.tscn").instantiate()
	add_child(_scene)
	var mock := PuzzleBase.MockGameState.new()
	_scene.add_child(mock)
	_scene._gs = mock
	await get_tree().create_timer(0.9).timeout
	await _shot("puer_01_intro.png")

	_scene._on_intro_start()
	await get_tree().create_timer(0.9).timeout
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
	for i in 100:
		await get_tree().create_timer(0.1).timeout
		if _scene._level == 2:
			break
	await get_tree().create_timer(1.2).timeout
	assert(_scene._level == 2, "打孔后必须进入穿绳阶段")
	await _shot("puer_06_level2.png")
	_scene._order = _scene._correct_order.duplicate()
	_scene._order.push_back(_scene._order.pop_front())
	_scene._reflow(0.0, true)

	# 直接过目（乱序）→ 第一张念不通的叶子掉地上
	_scene._on_verify()
	await get_tree().create_timer(4.0).timeout
	await _shot("puer_07_drop.png")

	assert(_scene._floor_order.size() == 1, "乱序验证应掉落一张叶子")
	var fallen_id: String = _scene._floor_order[0]
	var fallen: Control = _scene._floor_rows[fallen_id]
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	_scene._on_row_input(click, fallen)
	assert(_scene._drag_from_floor, "掉落贝叶必须使用拾回分支")
	fallen.position = Vector2(_scene.L2_X, _scene.L2_Y0 + 2 * _scene.L2_STEP)
	_scene._update_insert_marker(2)
	await get_tree().create_timer(0.3).timeout
	await _shot("puer_07a_drag.png")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	_scene._input(release)
	await get_tree().create_timer(0.4).timeout
	assert(_scene._floor_order.is_empty(), "拾回后地面应清空")
	assert(_scene._order.size() == 6, "拾回后六张经叶应在绳上")
	await _shot("puer_07b_recovered.png")
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

	assert(_scene._solved, "正确排序应触发誓约")
	_scene._complete()
	await get_tree().create_timer(2.8).timeout
	await _shot("puer_09_complete.png")
	assert(_scene._finished, "完成后应进入结算")
	print("PASS: 选叶、打孔、切关、落叶拾回、誓约和结算")
	print("quitting")
	get_tree().quit()

func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame

func _shot(shot_name: String) -> void:
	for i in 3:
		await get_tree().process_frame
		RenderingServer.force_draw()
	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT_DIR + shot_name)
	print("saved ", shot_name)
