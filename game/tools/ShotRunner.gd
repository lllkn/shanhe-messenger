extends Control
## ShotRunner —— 临时截图跑测器（用完即删）
## 真实窗口跑目标小游戏，自动截图各阶段画面。
##
## 用法（窗口模式，headless 下图为空）：
##   Godot --path . res://tools/ShotRunner.tscn                      # 默认丽江 PuzzleGlyph
##   Godot --path . res://tools/ShotRunner.tscn -- --target=dye      # 香格里拉 PuzzleDye

const OUT_DIR := "user://technical-previews/"

var _scene: Node
var _target := "glyph"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--target="):
			_target = a.split("=")[1]
	if _target == "dye":
		await _run_dye()
	elif _target == "dye_smoke":
		await _run_dye_smoke()
	else:
		await _run_glyph()
	print("quitting, target=", _target)
	get_tree().quit()

func _run_glyph() -> void:
	_scene = load("res://scenes/puzzles/PuzzleGlyph.tscn").instantiate()
	add_child(_scene)
	await _settle(3)
	await _shot("shot_intro.png")
	_scene._on_intro_start()
	await get_tree().create_timer(1.6).timeout
	await _shot("shot_level1.png")
	for i in 6:
		var correct: String = _scene._pair_of_glyph[_scene._current_glyph]
		_scene._on_pick(correct)
		await get_tree().create_timer(1.5).timeout
	await get_tree().create_timer(1.0).timeout
	await _shot("shot_level1_result.png")
	_scene._continue_to_level2()
	await get_tree().create_timer(0.7).timeout
	await _shot("shot_level2.png")

func _run_dye() -> void:
	_scene = load("res://scenes/puzzles/PuzzleDye.tscn").instantiate()
	add_child(_scene)
	await _settle(3)
	await _shot("dye_intro.png")
	_scene._on_intro_start()
	await _settle(2)
	await _shot("dye_fill_start.png")
	# 涂到一半：外瓣/中瓣/涟漪/莲蓬已补，内瓣与莲子还是褪色态
	_scene._debug_fill_first(24)
	await get_tree().create_timer(0.5).timeout
	await _shot("dye_fill_mid.png")
	# 全涂完 → 完成演出（描金时刻）→ 进第二关
	_scene._debug_fill_all()
	await get_tree().create_timer(1.5).timeout
	await _shot("dye_fill_done.png")
	_scene._enter_level2()
	await get_tree().create_timer(2.2).timeout
	await _shot("dye_level2.png")
	# 下第一味（青）→ 看火 → 搅缸中
	_scene._debug_commit("青")
	await get_tree().create_timer(1.8).timeout
	await _shot("dye_stir.png")
	_scene._debug_force_stir()
	await get_tree().create_timer(0.8).timeout
	await _shot("dye_stir_done.png")
	# 连错 3 次看口诀点亮
	for i in 3:
		_scene._debug_commit("黑")
		await get_tree().create_timer(1.6).timeout
	await _shot("dye_hint3.png")

func _run_dye_smoke() -> void:
	_scene = load("res://scenes/puzzles/PuzzleDye.tscn").instantiate()
	add_child(_scene)
	await _settle(3)
	_scene._on_intro_start()
	var ids: Array = _scene._region_order
	# 正确填一块 → 撤销 → 换错色点一块（应静默无效）
	_scene._select_no(1)
	var c0: Vector2 = _scene._region_labels[ids[0]].position + Vector2(14, 12)
	_scene._try_fill_at(c0)
	await _settle(2)
	print("smoke: 填 1 块后 filled=", _scene._filled.size())
	_scene._undo()
	await _settle(2)
	_scene._select_no(5)
	var c1: Vector2 = _scene._region_labels[ids[1]].position + Vector2(14, 12)
	_scene._try_fill_at(c1)
	await _settle(2)
	print("smoke: 撤销+错色后 filled=", _scene._filled.size(), "（应为 0）")
	# 连错 3 次同一块 → 安静提示
	for i in 3:
		_scene._try_fill_at(c1)
	await _settle(2)
	print("smoke: 连错 3 次未改变 filled=", _scene._filled.size(), "（应仍为 0）")
	# 全填 → 第二关 → 五道工序全过
	_scene._debug_fill_all()
	await get_tree().create_timer(3.6).timeout
	_scene._enter_level2()
	print("smoke: level=", _scene._level, "（应为 2）")
	for color in ["青", "赤", "黄", "白", "黑"]:
		_scene._debug_commit(color)
		await get_tree().create_timer(1.7).timeout
		_scene._debug_force_stir()
		await get_tree().create_timer(1.3).timeout
	await get_tree().create_timer(2.0).timeout
	await _shot("dye_smoke_win.png")
	print("smoke: 五道完成=", _scene._l2_all_done, " check_win=", _scene._check_win())

## 造一个「左键按下」的输入事件（用于走真实的输入处理路径）
func _mouse_click() -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	return ev

func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT_DIR + name)
	print("saved ", name)
