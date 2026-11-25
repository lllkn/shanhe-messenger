extends Control
## DialogueScene —— 数据驱动对话场景（剧情 / 问路 / 风物点通吃）
##
## 用法：SceneRouter.goto_dialogue("对话id")
## 数据：res://data/dialogues/<对话id>.json
##
## JSON 格式：
## {
##   "id": "sample_lijiang",
##   "on_end": {"type": "map"},                      // 对话结束后的去向，见 _finish()
##   "lines": [
##     {"speaker": "小学生", "text": "……"},          // 普通行
##     {"speaker": "我", "text": "……", "next": 5},   // 说完跳到第 5 行（默认顺序往下）
##     {"speaker": "阿东巴", "text": "……", "choices": [   // 选项行（文字打完后出按钮）
##       {"label": "说明来意", "next": 7},
##       {"label": "递介绍信", "next": 8, "action": {"type": "flag", "key": "has_letter"}}
##     ]}
##   ]
## }
## action 支持：{"type":"flag","key":"x"} 剧情标记
##             {"type":"fragment","id":"frag_x"} 直接发碎片
##             {"type":"choice","cine":"cine_x","index":0} 记录抉择

signal dialogue_finished(dialogue_id: String)
signal dialogue_left
var inline_mode := false
var _scene_background: TextureRect

func configure_inline(id: String) -> void:
	inline_mode = true
	dialogue_id = id

const DIALOGUE_DIR := "res://data/dialogues/"
## 风格规范 v1 色板
const INK := Color("1E3A34")     # 松烟墨青
const PAPER := Color("EDE3CB")   # 宣纸米白
const GOLD := Color("C9A24B")    # 藤黄金
const RED := Color("B5482F")     # 灯笼暖红（点缀）

const CHAR_INTERVAL := 0.035     # 打字机速度（秒/字）

var dialogue_id := ""
var lines: Array = []
var on_end: Dictionary = {"type": "map"}
var line_idx := -1

var _typing := false
var _char_timer := 0.0
var _finished := false

var _name_chip: PanelContainer
var _name_label: Label
var _text_label: RichTextLabel
var _hint_label: Label
var _choice_box: VBoxContainer
var _portrait: TextureRect
var _subtitle: Label
var _body_slot: Control
var lijiang_stage: Control # 保留现有测试接口；当前为对应城市的共用人物舞台

func _ready() -> void:
	_build_ui()
	if not inline_mode:
		dialogue_id = SceneRouter.params.get("dialogue_id", "sample_lijiang")
	if _load_dialogue(dialogue_id):
		var stage_script: Script
		for path in ["res://ui/LijiangDialogueStage.gd", "res://ui/PuerDialogueStage.gd", "res://ui/DaliDialogueStage.gd", "res://ui/XianggelilaDialogueStage.gd", "res://ui/GuchengDialogueStage.gd"]:
			var candidate: Script = load(path)
			if dialogue_id in candidate.PORTRAITS:
				stage_script = candidate
				break
		if stage_script != null:
			lijiang_stage = stage_script.new()
			add_child(lijiang_stage)
			move_child(lijiang_stage, 1 if _scene_background != null else 0)
			lijiang_stage.prepare(dialogue_id)
			lijiang_stage.photo_ready.connect(func():
				if not _typing: _on_line_shown()
			)

		_advance()
	else:
		_finished = true
		_hint_label.text = "内容尚未接入 · 可返回旅程"
		_hint_label.visible = true

# ---------- UI 构建（代码建节点，免编辑器摆放） ----------

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var station: String = SceneRouter.params.get("station", "lijiang")
	if not inline_mode:
		UiKit.background(self, ContentDB.station(station).get("preview", ""))
	_subtitle = UiKit.label("古道拾语", 38, GOLD)
	_subtitle.position = Vector2(40, 30)
	_subtitle.size = Vector2(750, 60)
	add_child(_subtitle)
	var back := UiKit.button("结束交谈" if inline_mode else "返回旅程", _leave)
	add_child(back)
	back.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	back.offset_left = -190
	back.offset_right = -40
	back.offset_top = 30
	back.offset_bottom = 86
	_portrait = TextureRect.new()
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_portrait)
	_portrait.position = Vector2(70, 106)
	_portrait.size = Vector2(330, 335)

	# 选项容器（底部对话框上方，右对齐）
	_choice_box = VBoxContainer.new()
	# 空选项容器不遮挡背后舞台的手机滑杆和确认按钮；子按钮仍各自接收输入。
	_choice_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_choice_box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_choice_box.offset_top = -500.0
	_choice_box.offset_bottom = -300.0
	_choice_box.offset_left = -710.0
	_choice_box.offset_right = -40.0
	_choice_box.alignment = BoxContainer.ALIGNMENT_END
	_choice_box.add_theme_constant_override("separation", 10)
	add_child(_choice_box)

	# 底部对话框
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_top = -285.0
	panel.offset_left = 40.0
	panel.offset_right = -40.0
	panel.offset_bottom = -16.0
	var panel_style := UiKit.surface("paper", 64)
	panel_style.content_margin_bottom = 24.0
	panel.add_theme_stylebox_override("panel", panel_style)
	add_child(panel)
	panel.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_continue()
			panel.accept_event()
	)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	_body_slot = Control.new()
	_body_slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_slot.custom_minimum_size.y = 112
	_body_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body_slot.resized.connect(_layout_text)
	vbox.add_child(_body_slot)
	_text_label = RichTextLabel.new()
	_text_label.bbcode_enabled = false
	_text_label.fit_content = false
	_text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text_label.scroll_active = true
	_text_label.custom_minimum_size = Vector2(0, 0)
	_text_label.add_theme_font_size_override("normal_font_size", 36)
	_text_label.add_theme_color_override("default_color", INK)
	_body_slot.add_child(_text_label)

	_hint_label = Label.new()
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_label.text = "▼ 点击 / 空格继续"
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint_label.add_theme_font_size_override("font_size", 20)
	_hint_label.add_theme_color_override("font_color", INK)
	vbox.add_child(_hint_label)

	# 说话人名牌（浮在对话框上沿）
	_name_chip = PanelContainer.new()
	_name_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_chip.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_name_chip.offset_left = 100.0
	_name_chip.offset_top = -315.0
	_name_chip.offset_bottom = -252.0
	_name_chip.offset_right = 300.0
	var chip_style := UiKit.surface("wood", 24)
	_name_chip.add_theme_stylebox_override("panel", chip_style)
	_name_label = Label.new()
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.add_theme_font_size_override("font_size", 28)
	_name_label.add_theme_color_override("font_color", PAPER)
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_chip.add_child(_name_label)
	add_child(_name_chip)

# ---------- 数据加载 ----------

func _load_dialogue(id: String) -> bool:
	if not ContentDB.valid_id(id):
		_text_label.text = "这段对话尚未接入。"
		return false
	var path := DIALOGUE_DIR + id + ".json"
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_text_label.text = "这段对话正在制作，请稍后再来。"
		return false
	var data: Variant = JSON.parse_string(file.get_as_text())
	if not data is Dictionary or not data.get("lines") is Array:
		_text_label.text = "对话暂时无法读取，请返回旅程。"
		return false
	lines = data["lines"]
	if lines.is_empty():
		_text_label.text = "这段对话正在制作，请稍后再来。"
		return false
	for line in lines:
		if not line is Dictionary or not line.get("text", "") is String:
			return false
		if line.has("next") and (int(line["next"]) < 0 or int(line["next"]) > lines.size()):
			return false
		if line.has("choices"):
			if not line["choices"] is Array:
				return false
			for choice in line["choices"]:
				if not choice is Dictionary or int(choice.get("next", 0)) < 0 or int(choice.get("next", 0)) > lines.size():
					return false
	_subtitle.text = data.get("title", "古道拾语")
	on_end = data.get("on_end", {"type": "map"})
	if inline_mode and data.has("background"):
		_set_scene_background(data["background"])
	return true

func _set_scene_background(path: String) -> void:
	if not ResourceLoader.exists(path): return
	if _scene_background == null:
		_scene_background = TextureRect.new()
		_scene_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_scene_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_scene_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_scene_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_scene_background)
		move_child(_scene_background, 0)
	_scene_background.texture = load(path)

# ---------- 播放流程 ----------

func _goto_line(idx: int) -> void:
	if idx < 0 or idx >= lines.size():
		_finish()
		return
	line_idx = idx
	var line: Dictionary = lines[line_idx]
	if inline_mode and line.has("background"):
		_set_scene_background(line["background"])
	var portrait_path: String = line.get("portrait", "")
	_portrait.visible = not portrait_path.is_empty() and ResourceLoader.exists(portrait_path)
	if _portrait.visible:
		_portrait.texture = load(portrait_path)
	if lijiang_stage != null:
		_portrait.hide()
		lijiang_stage.show_line(line_idx, line.get("speaker", ""))
	_name_label.text = line.get("speaker", "")
	_name_chip.visible = not _name_label.text.is_empty()
	_text_label.text = line.get("text", "")
	_text_label.visible_characters = 0
	_hint_label.text = "点击 / 空格补全文字"
	_hint_label.visible = true
	_clear_choices()
	_typing = true
	_char_timer = 0.0
	_layout_text.call_deferred()

func _layout_text() -> void:
	if _text_label == null or _body_slot == null or _body_slot.size.x <= 0: return
	# 固定可用宽度后再测行高，短句居中，长句保持在正文区域内。
	_text_label.size = _body_slot.size
	var height := minf(_text_label.get_content_height(), _body_slot.size.y)
	_text_label.size.y = height
	_text_label.position = Vector2(0, maxf(0, (_body_slot.size.y-height)*0.5))

func _advance() -> void:
	_goto_line(line_idx + 1)

## 点击/按键：打字中→补全本行；打完→下一行
func _continue() -> void:
	if _finished:
		return
	if _typing:
		_text_label.visible_characters = -1
		_typing = false
		_on_line_shown()
	elif not _has_choices():
		if lijiang_stage != null and lijiang_stage.blocks_continue():
			_hint_label.text = lijiang_stage.continue_hint()
			return
		var line: Dictionary = lines[line_idx]
		_goto_line(int(line.get("next", line_idx + 1)))

func _process(delta: float) -> void:
	if not _typing:
		return
	_char_timer += delta
	var total := _text_label.get_total_character_count()
	var interval := CHAR_INTERVAL / GameSettings.text_speed
	while _char_timer >= interval and _typing:
		_char_timer -= interval
		_text_label.visible_characters += 1
		if _text_label.visible_characters >= total:
			_typing = false
			_on_line_shown()

func _on_line_shown() -> void:
	var line: Dictionary = lines[line_idx]
	if line.has("choices") and not line["choices"].is_empty():
		_hint_label.visible = false
		_show_choices(line["choices"])
	else:
		_hint_label.text = lijiang_stage.continue_hint() if lijiang_stage != null and lijiang_stage.blocks_continue() else "▼ 点击 / 空格继续"
		_hint_label.visible = true

# ---------- 选项 ----------

func _has_choices() -> bool:
	return _choice_box.get_child_count() > 0

func _show_choices(choices: Array) -> void:
	_clear_choices()
	for i in choices.size():
		var btn := UiKit.button(choices[i].get("label", "..."), _choose.bind(i))
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_choice_box.add_child(btn)
	if _choice_box.get_child_count() > 0:
		_choice_box.get_child(0).grab_focus()

func _clear_choices() -> void:
	UiKit.clear(_choice_box)

func _choose(i: int) -> void:
	if _finished or line_idx < 0 or line_idx >= lines.size():
		return
	var line: Dictionary = lines[line_idx]
	if i < 0 or i >= line.get("choices", []).size():
		return
	var choice: Dictionary = line["choices"][i]
	_clear_choices()
	if choice.has("action"):
		_apply_action(choice["action"])
	_goto_line(int(choice.get("next", line_idx + 1)))

# ---------- 动作与结束 ----------

func _apply_action(action: Dictionary) -> void:
	JourneyFlow.apply_action(action)

func _finish() -> void:
	if _finished:
		return
	_finished = true
	dialogue_finished.emit(dialogue_id)
	if inline_mode:
		return
	if SceneRouter.params.has("flow_step"):
		JourneyFlow.complete_current()
	else:
		JourneyFlow.dispatch(on_end)

func _leave() -> void:
	if inline_mode:
		dialogue_left.emit()
		return
	var station: String = SceneRouter.params.get("station", "")
	if station.is_empty():
		SceneRouter.goto_map()
	else:
		JourneyFlow.return_to_city(station)

# ---------- 输入 ----------

func _input(event: InputEvent) -> void:
	# 在GUI按键之前处理，避免上次点击留下的按钮焦点吃掉空格。
	if _finished or _has_choices(): return
	# 亮度操作期间让滑杆和按钮接收空格/Enter，不能抢先推进剧情。
	if lijiang_stage != null and lijiang_stage.blocks_continue() and not _typing: return
	if event is InputEventKey and event.pressed and not event.echo and (event.physical_keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER] or event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]):
		_continue()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_continue()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_continue()
		get_viewport().set_input_as_handled()
