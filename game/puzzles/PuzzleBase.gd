class_name PuzzleBase
extends Control
## PuzzleBase —— 小游戏场景基类（接口约定 v2 §三）
## 生命周期：setup → start（说明页）→ 玩法进行 → _complete() / _exit()
## 子类只需实现 4 个钩子：_on_setup / _on_start / _check_win / _on_complete

signal puzzle_started(station_id)
signal puzzle_completed(station_id, fragment_ids: Array)
signal puzzle_exited(station_id, solved: bool)

const PUZZLES_JSON := "res://data/puzzles.json"

## 各子场景在编辑器里设置（或 SceneRouter params 传入 station）
@export var station_id: String = ""

var config: Dictionary = {}

var _gs: Node                      # GameState 或内存 mock
var _intro_layer: CanvasLayer      # 玩法说明页
var _win_layer: CanvasLayer        # 占位胜利反馈（统一接入阶段换正式结算 UI）
var _finished := false
var _started := false
var _exiting := false

# ---------- MockGameState（独立测试用，接口与 GameState 白名单一致，不持久化） ----------
class MockGameState:
	extends Node
	var fragments: Dictionary = {}
	var solved: Dictionary = {}
	func has_fragment(id: String) -> bool: return fragments.has(id)
	func get_fragments() -> Array: return fragments.keys()
	func get_fragment_count() -> int: return fragments.size()
	func is_puzzle_solved(station_id: String) -> bool: return solved.has(station_id)
	func add_fragment(id: String) -> void: fragments[id] = true
	func mark_puzzle_solved(station_id: String) -> void: solved[station_id] = true
	func record_choice(station_id: String, choice_id) -> void: pass
	func evaluate_ending() -> String:
		var c := fragments.size()
		if c >= 4: return "kaiguan"
		elif c == 3: return "zhicheng"
		else: return "cundang"

func _ready() -> void:
	# 触发方式：主线 params 优先，编辑器导出值兜底（F6 独立测试）
	var routed: bool = SceneRouter.SCENES.get(SceneRouter.current_key, "") == scene_file_path and SceneRouter.current_key.begins_with("puzzle_")
	if routed and SceneRouter.params.has("station"):
		station_id = SceneRouter.params["station"]
	# 主线路由使用真实状态；F6/工具实例使用mock，避免独立试玩污染进度
	if has_node("/root/GameState") and routed:
		_gs = get_node("/root/GameState")
	else:
		_gs = MockGameState.new()
		add_child(_gs)
	config = _load_config(station_id)
	_build_exit_button()
	_on_setup(config)
	_build_intro()

func _load_config(sid: String) -> Dictionary:
	var file := FileAccess.open(PUZZLES_JSON, FileAccess.READ)
	if file == null:
		push_error("PuzzleBase: 找不到 " + PUZZLES_JSON)
		return {}
	var data: Variant = JSON.parse_string(file.get_as_text())
	if data == null or not data.has(sid):
		push_error("PuzzleBase: puzzles.json 缺少节点 " + sid)
		return {}
	return data[sid]

# ---------- 说明页 ----------

func _build_intro() -> void:
	_intro_layer = CanvasLayer.new()
	_intro_layer.layer = 50
	var box := _modal_box(_intro_layer)
	box.add_child(UiKit.label(config.get("intro_title", station_id), 44, UiKit.GOLD))
	box.add_child(UiKit.label(config.get("intro_text", ""), 28))
	box.add_child(UiKit.label("可反复尝试 · 中途退出不会发放碎片", 24, UiKit.MUTED))
	var begin := UiKit.button("开始体验", _on_intro_start, true)
	box.add_child(begin)

func _modal_box(layer: CanvasLayer) -> VBoxContainer:
	add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.09, 0.08, 0.94)
	dim.size = get_viewport().get_visible_rect().size
	layer.add_child(dim)
	var center := CenterContainer.new()
	dim.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var card := UiKit.panel()
	card.custom_minimum_size.x = 1000
	center.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 24)
	card.add_child(box)
	return box

func _on_intro_start() -> void:
	if _started or _exiting:
		return
	_started = true
	_intro_layer.queue_free()
	puzzle_started.emit(station_id)
	_on_start()

# ---------- 退出按钮（右上角，基类自带，子类不要删） ----------

func _build_exit_button() -> void:
	var btn := Button.new()
	btn.text = "退出"
	btn.add_theme_font_size_override("font_size", 24)
	btn.custom_minimum_size = Vector2(96, 48)
	btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	btn.offset_left = -116
	btn.offset_right = -20
	btn.offset_top = 16
	btn.offset_bottom = 64
	btn.pressed.connect(_exit)
	add_child(btn)

# ---------- 统一收尾 ----------

## 达成结算条件时由子类调用，基类走统一收尾（接口约定 v2 §4.1-3）
func _complete() -> void:
	if _finished or _exiting:
		return
	_finished = true
	var fragment_ids: Array = []
	var frag_id: String = config.get("fragment_id", "")
	var deferred: bool = _gs == get_node_or_null("/root/GameState") and SceneRouter.params.get("defer_reward", false)
	if deferred:
		_gs.set_flag("flow/" + station_id + "/" + str(SceneRouter.params.get("flow_step", "glyph")))
	elif frag_id != "":
		_gs.add_fragment(frag_id)          # 写入即自动存档
		fragment_ids.append(frag_id)
	if not deferred:
		_gs.mark_puzzle_solved(station_id)
	_on_complete()                          # 胜利瞬间表现（子类实现，1-2 秒）
	await get_tree().create_timer(2.0, false).timeout
	_show_win_placeholder(fragment_ids)

## 占位胜利反馈（统一接入阶段换成正式结算 UI，§4.1）
func _show_win_placeholder(fragment_ids: Array) -> void:
	_win_layer = CanvasLayer.new()
	_win_layer.layer = 60
	var box := _modal_box(_win_layer)
	box.add_child(UiKit.label("一段手艺，一枚信物", 44, UiKit.GOLD))
	if fragment_ids.is_empty():
		box.add_child(UiKit.label("信物拼合完成", 32))
	for id in fragment_ids:
		var entry := ContentDB.fragment(id)
		box.add_child(UiKit.label("获得 · " + entry.get("name", "古道信物"), 32))
		box.add_child(UiKit.label(entry.get("meaning", ""), 28))
		box.add_child(UiKit.label(entry.get("source", ""), 24, UiKit.MUTED))
	box.add_child(UiKit.label("碎片已放入行囊，可在图鉴中重温。", 28))
	box.add_child(UiKit.button("带上信物 · 继续旅程", func():
		puzzle_completed.emit(station_id, fragment_ids)
		_back_to_map()
	, true))

## 中途退出（碎片不发、进度不记，可再次进入）
func _exit() -> void:
	if _finished or _exiting:
		return
	_exiting = true
	puzzle_exited.emit(station_id, false)
	_back_to_map()

func _back_to_map() -> void:
	if SceneRouter.params.has("flow_step") and _finished:
		JourneyFlow.complete_current()
		return
	if SceneRouter.params.has("city_context"):
		JourneyFlow.return_to_city(station_id)
		return
	# 独立体验沿用总览返回
	if ResourceLoader.exists("res://scenes/MapScene.tscn"):
		SceneRouter.goto_map()
	else:
		get_tree().quit()

## 音效预留（开发期静音，统一接入阶段配）
func _play_sfx(_sfx_name: String) -> void:
	pass

# ---------- 子类钩子（必须覆写） ----------

func _on_setup(_cfg: Dictionary) -> void:
	pass

func _on_start() -> void:
	pass

func _check_win() -> bool:
	return false

func _on_complete() -> void:
	pass
