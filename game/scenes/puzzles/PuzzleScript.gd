extends PuzzleBase
## PuzzleScript —— 普洱·贝叶经归册（接口约定 v3 注册表 #4）
## 第一关「整」：桌面散着 12 张贝叶，挑出属于本匣（同路人规矩）的 6 张 →
##   叶子码进木匣夹板 → 两端各点一下打孔。
## 第二关「穿」：打过孔的叶子穿上绳，拖动排序 → 请岩香过目；
##   念到第一张语义不通的叶子，它掉在地上，捡起来重穿。全通 → 誓约演出 → 发碎片。
## 内容全部来自 puzzles.json，脚本只定义布局与交互。

const LEAF_TEX := "leaf_beiye.png"
const NPC_TEX := "npc_yanxiang.png"
const TOOL_TEX := "tool_punch.png"
const BOX_TEX := "box_press.png"

const EMPHASIS_FONT := preload("res://assets/shared/fonts/emphasis.tres")

const GOLD := Color("#C9A24B")
const RED := Color("#B5482F")
const INK := Color("#1E3A34")
const PAPER := Color("#EDE3CB")
const ROPE := Color("#6B4A32")

# ---- 第一关布局：12 张叶子 4×3 摊在桌面 ----
const L1_LEAF := Vector2(292, 70)
const L1_COLS := 4
const L1_ORIGIN := Vector2(50, 396)
const L1_STEP := Vector2(300, 84)

# ---- 木匣/打孔 ----
const BOX_SIZE := Vector2(560, 176)
const BOX_POS := Vector2(360, 424)

# ---- 第二关布局：中央竖向装订，叶子横排成一册 ----
const L2_LEAF := Vector2(326, 78)
const L2_X := 460.0
const L2_Y0 := 140.0
const L2_STEP := 84.0
const FLOOR_LEAF := Vector2(230, 55)
const FLOOR_Y := 677.0

var _assets_dir: String = ""
var _level := 0

# 第一关状态
var _l1_root: Control
var _l1_cards: Dictionary = {}          # leaf_id -> Button
var _l1_picked: Array = []              # 已挑中的 leaf_id
var _volume_ids: Array = []             # 本匣 6 张 id
var _pick_counter: Label
var _hint: Label
var _wrong_streak := 0
var _punching := false
var _punched := 0
var _box_node: Control
var _hole_marks: Array = []

# 第二关状态
var _l2_root: Control
var _l2_rows: Dictionary = {}           # leaf_id -> Control（在绳上的行）
var _order: Array = []                  # 绳上顺序（leaf_id）
var _floor_rows: Dictionary = {}        # leaf_id -> Control（掉在地上的）
var _floor_order: Array = []
var _correct_order: Array = []
var _text_of: Dictionary = {}           # leaf_id -> 文案
var _drag_row: Control = null
var _drag_id := ""
var _drag_from_floor := false
var _drag_offset := Vector2.ZERO
var _insert_index := -1
var _hint2: Label
var _verify_btn: Button
var _bubble: Control
var _bubble_label: Label
var _busy := false
var _fail_streak := 0
var _solved := false
var _insert_marker: Panel
var _progress_dots: Array[Panel] = []
var _pick_guide: Panel
var _l1_title: Label
var _l1_prompt: Label
var _punch_leaf: Control

# ---------- 钩子 ----------

func _on_setup(cfg: Dictionary) -> void:
	_assets_dir = cfg.get("assets_dir", "res://assets/puzzles/puer/")
	var bg := TextureRect.new()
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.texture = load(_assets_dir + "bg_zangfang.png")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var shade := ColorRect.new()
	shade.color = Color(0.05, 0.09, 0.08, 0.36)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	_text_of.clear()
	for entry in cfg["level1"]["leaves"]:
		_text_of[entry["id"]] = entry["text"]
		if entry.get("in_volume", false):
			_volume_ids.append(entry["id"])
	_correct_order = cfg["level2"]["order"].duplicate()

	_setup_level1(cfg["level1"])
	_setup_level2(cfg["level2"])
	_l2_root.visible = false
	# 独立运行时 MockGameState 也会成为子节点，不能用第一个子节点猜退出按钮。
	for child in get_children():
		if child is Button:
			move_child(child, -1)
			_style_button(child)
			child.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

func _on_start() -> void:
	_level = 1
	_l1_root.visible = true
	for i in _l1_cards.size():
		var card: Control = _l1_cards.values()[i]
		_reveal(card, i * 0.035, 14.0)

func _check_win() -> bool:
	return _solved

func _on_complete() -> void:
	_play_sfx("match_ok")
	for i in _order.size():
		var row: Control = _l2_rows[_order[i]]
		_border(row, Color("#FFE09B"), 1.4, L2_LEAF)
		var tween := create_tween()
		tween.tween_interval(i * 0.08)
		tween.tween_property(row, "scale", Vector2.ONE * 1.03, 0.14)
		tween.tween_property(row, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# ---------- 通用小组件 ----------

func _style(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	return style

func _panel(parent: Control, pos: Vector2, dimensions: Vector2, color: Color, radius: int) -> Panel:
	var panel := Panel.new()
	panel.position = pos
	panel.size = dimensions
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := _style(color, radius)
	style.set_border_width_all(1)
	style.border_color = Color(GOLD, 0.35)
	style.shadow_color = Color(0.02, 0.04, 0.03, 0.32)
	style.shadow_size = 12
	style.shadow_offset = Vector2(0, 6)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	return panel

func _label(parent: Control, text: String, pos: Vector2, dimensions: Vector2, font_size: int, color: Color, centered: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.size = dimensions
	label.add_theme_font_size_override("font_size", font_size)
	if font_size >= 24:
		label.add_theme_font_override("font", EMPHASIS_FONT)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if centered:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(label)
	return label

func _style_button(button: Button) -> void:
	var normal := _style(INK, 16)
	normal.set_border_width_all(2)
	normal.border_color = GOLD
	normal.shadow_color = Color(INK, 0.30)
	normal.shadow_size = 4
	normal.shadow_offset = Vector2(0, 4)
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("#31574A")
	button.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("#142D27")
	button.add_theme_stylebox_override("pressed", pressed)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(INK, 0.60)
	disabled.border_color = Color(GOLD, 0.25)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_disabled_color", Color(PAPER, 0.45))

## 圆点（孔位/绳环）
func _dot(parent: Control, pos: Vector2, radius: float, fill: Color, ring: Color) -> Panel:
	var dot := Panel.new()
	dot.size = Vector2(radius * 2, radius * 2)
	dot.position = pos - Vector2(radius, radius)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(int(radius))
	style.set_border_width_all(2)
	style.border_color = ring
	dot.add_theme_stylebox_override("panel", style)
	dot.pivot_offset = dot.size * 0.5
	parent.add_child(dot)
	return dot

## 中文手动折行：Godot 的 Label 会把宽度钳到文本最小宽度，自动换行对无空格中文不生效，
## 所以按字数在标点处主动断行，返回带 \n 的文本。
func _wrap_cjk(text: String, max_chars: int) -> String:
	if text.length() <= max_chars:
		return text
	var lines: Array = []
	var rest := text
	while rest.length() > max_chars:
		var cut := -1
		for i in range(max_chars, 0, -1):
			var ch := rest.substr(i - 1, 1)
			if ch == "，" or ch == "。" or ch == "；" or ch == "、":
				cut = i
				break
		if cut <= 0:
			cut = max_chars
		lines.append(rest.substr(0, cut))
		rest = rest.substr(cut)
	if rest != "":
		lines.append(rest)
	return "\n".join(lines)

## 一张贝叶：叶面图 + 可读纸条 + 两端孔位
func _make_leaf(text: String, size: Vector2, with_holes: bool, font_size: int) -> Control:
	var row := Control.new()
	row.size = size
	row.pivot_offset = size * 0.5
	var shadow := _panel(row, Vector2(10, 12), size - Vector2(20, 14), Color(0.02, 0.04, 0.03, 0.35), 12)
	shadow.get_theme_stylebox("panel").set_border_width_all(0)
	var art := TextureRect.new()
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.texture = load(_assets_dir + LEAF_TEX)
	art.position = Vector2.ZERO
	art.size = size
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(art)
	# 文字垫纸：叶面肌理深，先铺一层米白再写字，保证可读
	var plate := Panel.new()
	plate.position = Vector2(size.x * 0.09, size.y * 0.10)
	plate.size = Vector2(size.x * 0.82, size.y * 0.80)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var paper_style := _style(Color(PAPER, 0.92), 7)
	paper_style.set_border_width_all(1)
	paper_style.border_color = Color(GOLD, 0.45)
	plate.add_theme_stylebox_override("panel", paper_style)
	row.add_child(plate)
	var label := Label.new()
	var leaf_font_size := mini(font_size, int(size.y * 0.26))
	var max_chars := maxi(4, int(size.x * 0.72 / float(leaf_font_size)))
	# 先设字体再给文本与尺寸，避免默认字号把最小宽度撑大后无法缩回。
	label.add_theme_font_override("font", EMPHASIS_FONT)
	label.add_theme_font_size_override("font_size", leaf_font_size)
	label.text = _wrap_cjk(text, max_chars)
	label.position = Vector2(size.x * 0.10, size.y * 0.10)
	label.size = Vector2(size.x * 0.80, size.y * 0.80)
	label.add_theme_color_override("font_color", INK)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	# Godot 会延迟重算字体的最小尺寸，等主题更新后再落实文字区域。
	label.set_deferred("size", Vector2(size.x * 0.80, size.y * 0.80))
	if with_holes:
		_dot(row, Vector2(size.x * 0.07, size.y * 0.5), 7.0, Color(INK, 0.85), GOLD)
		_dot(row, Vector2(size.x * 0.93, size.y * 0.5), 7.0, Color(INK, 0.85), GOLD)
	return row

func _border(row: Control, color: Color, duration: float, size: Vector2) -> void:
	var border := Panel.new()
	border.set_meta("feedback", true)
	border.position = Vector2(-4, -4)
	border.size = size + Vector2(8, 8)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := _style(Color(color, 0.05), 14)
	style.set_border_width_all(4)
	style.border_color = color
	border.add_theme_stylebox_override("panel", style)
	row.add_child(border)
	var tween := create_tween()
	tween.tween_interval(duration * 0.6)
	tween.tween_property(border, "modulate:a", 0.0, duration * 0.4)
	tween.tween_callback(border.queue_free)

func _shake(row: Control) -> void:
	var home := row.get_meta("home", row.position) as Vector2
	var tween := create_tween()
	tween.tween_property(row, "position", home + Vector2(-7, 0), 0.06)
	tween.tween_property(row, "position", home + Vector2(7, 0), 0.08)
	tween.tween_property(row, "position", home + Vector2(-4, 0), 0.07)
	tween.tween_property(row, "position", home, 0.08)

func _pulse_gold(row: Control, size: Vector2) -> void:
	var ring := Panel.new()
	ring.set_meta("feedback", true)
	ring.position = Vector2(-6, -6)
	ring.size = size + Vector2(12, 12)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := _style(Color(0.0, 0.0, 0.0, 0.0), 16)
	style.set_border_width_all(5)
	style.border_color = Color("#FFE09B")
	ring.add_theme_stylebox_override("panel", style)
	row.add_child(ring)
	var tween := create_tween().set_loops(4)
	tween.tween_property(ring, "modulate:a", 0.25, 0.22)
	tween.tween_property(ring, "modulate:a", 1.0, 0.22)
	tween.finished.connect(ring.queue_free)

# ---------- 第一关：整理 · 打孔 ----------

func _setup_level1(l1: Dictionary) -> void:
	_l1_root = Control.new()
	_l1_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_l1_root.visible = false
	add_child(_l1_root)

	_panel(_l1_root, Vector2(28, 382), Vector2(1224, 270), Color(INK, 0.66), 24)
	_panel(_l1_root, Vector2(220, 658), Vector2(840, 48), Color(INK, 0.88), 18)
	_pick_guide = _panel(_l1_root, Vector2(46, 148), Vector2(420, 194), Color(INK, 0.9), 18)
	_label(_pick_guide, l1.get("guide_title", ""), Vector2(20, 16), Vector2(380, 36), 26, GOLD)
	_label(_pick_guide, l1.get("guide_text", ""), Vector2(20, 60), Vector2(380, 116), 22, PAPER)
	# 岩香（对面坐着）
	var npc := TextureRect.new()
	npc.name = "Npc"
	npc.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	npc.texture = load(_assets_dir + NPC_TEX)
	npc.position = Vector2(527, 100)
	npc.size = Vector2(205, 296)
	npc.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	npc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	npc.set_meta("home", npc.position)
	_l1_root.add_child(npc)
	var bob := create_tween().set_loops()
	bob.tween_property(npc, "position:y", 94.0, 2.2).set_trans(Tween.TRANS_SINE)
	bob.tween_property(npc, "position:y", 100.0, 2.2).set_trans(Tween.TRANS_SINE)

	_panel(_l1_root, Vector2(20, 16), Vector2(1240, 84), Color(INK, 0.90), 20)
	_l1_title = _label(_l1_root, l1.get("title", ""), Vector2(48, 26), Vector2(700, 36), 30, PAPER)
	_l1_prompt = _label(_l1_root, l1.get("prompt", ""), Vector2(48, 64), Vector2(880, 28), 19, Color(PAPER, 0.84))
	_pick_counter = Label.new()
	_pick_counter.position = Vector2(860, 30)
	_pick_counter.size = Vector2(220, 56)
	_pick_counter.add_theme_font_override("font", EMPHASIS_FONT)
	_pick_counter.add_theme_font_size_override("font_size", 26)
	_pick_counter.add_theme_color_override("font_color", GOLD)
	_pick_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pick_counter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pick_counter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_l1_root.add_child(_pick_counter)
	for i in _volume_ids.size():
		_progress_dots.append(_dot(_l1_root, Vector2(890 + i * 28, 86), 3.5, Color(GOLD, 0.18), Color(GOLD, 0.4)))

	var ids: Array = []
	for entry in l1["leaves"]:
		ids.append(entry["id"])
	ids.shuffle()
	for i in ids.size():
		var lid: String = ids[i]
		var rect_pos := L1_ORIGIN + Vector2((i % L1_COLS) * L1_STEP.x, (i / L1_COLS) * L1_STEP.y)
		var btn := Button.new()
		btn.custom_minimum_size = L1_LEAF
		btn.size = L1_LEAF
		btn.position = rect_pos
		btn.focus_mode = Control.FOCUS_NONE
		btn.pivot_offset = L1_LEAF * 0.5
		btn.rotation = randf_range(-0.022, 0.022)
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			btn.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		btn.set_meta("home", rect_pos)
		btn.set_meta("base_rot", btn.rotation)
		var leaf := _make_leaf(_text_of[lid], L1_LEAF, false, 19)
		leaf.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(leaf)
		btn.pressed.connect(_on_pick_leaf.bind(lid))
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.mouse_entered.connect(func() -> void:
			if not btn.disabled and not _punching:
				_hover_leaf(btn, true, _is_picked(lid))
		)
		btn.mouse_exited.connect(func() -> void:
			if not btn.disabled and not _punching:
				_hover_leaf(btn, false, _is_picked(lid))
		)
		_l1_cards[lid] = btn
		_l1_root.add_child(btn)

	_hint = _label(_l1_root, l1.get("hint_idle", ""), Vector2(140, 664), Vector2(1000, 36), 24, PAPER, true)
	_refresh_pick_counter()

func _is_picked(lid: String) -> bool:
	return lid in _l1_picked

func _on_pick_leaf(lid: String) -> void:
	if _level != 1 or _punching or _finished:
		return
	var l1: Dictionary = config["level1"]
	if not _is_picked(lid) and lid in _volume_ids:
		_l1_picked.append(lid)
		var btn: Button = _l1_cards[lid]
		_stop_motion(btn)
		btn.modulate.a = 1.0
		_set_selected(btn, true)
		_border(btn, Color("#FFE09B"), 0.5, L1_LEAF)
		var tween := create_tween().set_parallel()
		btn.set_meta("motion", tween)
		tween.tween_property(btn, "scale", Vector2.ONE * 1.04, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(btn, "position", (btn.get_meta("home") as Vector2) + Vector2(0, -8), 0.16)
		tween.tween_property(btn, "rotation", 0.0, 0.16)
		_play_sfx("pick")
		_wrong_streak = 0
		_refresh_pick_counter()
		if _l1_picked.size() >= _volume_ids.size():
			_begin_punch_phase()
		return
	if _is_picked(lid):
		_l1_picked.erase(lid)
		var btn2: Button = _l1_cards[lid]
		_stop_motion(btn2)
		_set_selected(btn2, false)
		_clear_feedback(btn2)
		var back := create_tween().set_parallel()
		btn2.set_meta("motion", back)
		back.tween_property(btn2, "scale", Vector2.ONE, 0.16)
		back.tween_property(btn2, "position", btn2.get_meta("home") as Vector2, 0.16)
		back.tween_property(btn2, "rotation", btn2.get_meta("base_rot") as float, 0.16)
		_refresh_pick_counter()
		return
	# 干扰叶：抖动 + 提示
	_wrong_streak += 1
	var decoy: Button = _l1_cards[lid]
	_border(decoy, Color("#EF8B73"), 0.7, L1_LEAF)
	_shake(decoy)
	_play_sfx("match_bad")
	_hint.text = l1.get("wrong_hint", "")
	_hint.add_theme_color_override("font_color", Color("#FFD1BC"))
	if _wrong_streak >= 3:
		_wrong_streak = 0
		_hint.text = l1.get("wrong3_hint", "")
		_hint.add_theme_color_override("font_color", GOLD)
		for vid in _volume_ids:
			if not _is_picked(vid):
				_pulse_gold(_l1_cards[vid], L1_LEAF)

func _clear_feedback(node: Control) -> void:
	for child in node.get_children():
		if child.has_meta("feedback"):
			child.queue_free()

func _refresh_pick_counter() -> void:
	var l1: Dictionary = config["level1"]
	for i in _progress_dots.size():
		_progress_dots[i].modulate = Color("#FFE09B") if i < _l1_picked.size() else Color(1, 1, 1, 0.35)
	_pick_counter.text = "%s %d / %d" % [l1.get("picked_prefix", "已挑"), _l1_picked.size(), _volume_ids.size()]

## 挑齐 → 叶子码进木匣 → 两端打孔
func _begin_punch_phase() -> void:
	if _punching:
		return
	_punching = true
	_pick_guide.visible = false
	_l1_title.text = config["level1"].get("punch_title", "")
	_l1_prompt.text = config["level1"].get("punch_prompt", "")
	for card in _l1_cards.values():
		_stop_motion(card)
		# 淡出的散叶仍有点击范围，进入打孔后必须全部释放鼠标事件。
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clear_all_feedback()
	_hint.text = config["level1"].get("punch_hint", "")
	_hint.add_theme_color_override("font_color", GOLD)
	# 未挑中的散叶淡出
	for lid in _l1_cards:
		if not _is_picked(lid):
			var fade := create_tween()
			fade.tween_property(_l1_cards[lid], "modulate:a", 0.0, 0.4)
			_l1_cards[lid].disabled = true
	# 木匣夹板升起
	_box_node = Control.new()
	_box_node.position = BOX_POS + Vector2(0, 26)
	_box_node.size = BOX_SIZE
	_box_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box_node.modulate.a = 0.0
	_l1_root.add_child(_box_node)
	# 木匣压在叶子下面，叶子落在匣面上（夹板夹叶的观感）
	_l1_root.move_child(_box_node, 1)
	var box := TextureRect.new()
	box.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# 截取木夹板中间的木纹，去掉图片中预绘的四个孔，孔位由贝叶本身决定。
	var wood := AtlasTexture.new()
	wood.atlas = load(_assets_dir + BOX_TEX)
	wood.region = Rect2(180, 4, 540, 116)
	box.texture = wood
	box.size = BOX_SIZE
	box.stretch_mode = TextureRect.STRETCH_SCALE
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box_node.add_child(box)
	# 六张叶片叠齐，最后一张是可见的打孔面。
	for i in 6:
		var sheet := _make_leaf(config["level1"].get("box_caption", "") if i == 5 else "", Vector2(504, 86), false, 22)
		sheet.position = Vector2(28, 32 + i * 3)
		sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_box_node.add_child(sheet)
		if i == 5:
			_punch_leaf = sheet
	var arrive := create_tween().set_parallel()
	arrive.tween_property(_box_node, "position", BOX_POS, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	arrive.tween_property(_box_node, "modulate:a", 1.0, 0.30)
	# 已挑叶子飞进匣里、隐入夹板之间（留出匣面给打孔）
	for i in _l1_picked.size():
		var btn: Button = _l1_cards[_l1_picked[i]]
		var target := BOX_POS + Vector2(BOX_SIZE.x * 0.5 - L1_LEAF.x * 0.28, BOX_SIZE.y * 0.5 - L1_LEAF.y * 0.28)
		var fly := create_tween().set_parallel()
		fly.tween_property(btn, "position", target, 0.40).set_delay(0.08 + i * 0.05).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		fly.tween_property(btn, "scale", Vector2(0.56, 0.56), 0.40).set_delay(0.08 + i * 0.05)
		fly.tween_property(btn, "rotation", 0.0, 0.36).set_delay(0.08 + i * 0.05)
		fly.tween_property(btn, "modulate:a", 0.0, 0.22).set_delay(0.34 + i * 0.05)
		btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	await get_tree().create_timer(0.72, false).timeout
	# 孔位、点击区都跟随可见贝叶；与第二关的孔位比例相同。
	for side in [0, 1]:
		var center := Vector2(_punch_leaf.size.x * (0.07 if side == 0 else 0.93), _punch_leaf.size.y * 0.5)
		var marker := _dot(_punch_leaf, center, 12.0, Color(GOLD, 0.45), Color("#FFE09B"))
		marker.set_meta("side", side)
		var pulse := create_tween().set_loops()
		pulse.tween_property(marker, "modulate:a", 0.65, 0.6)
		pulse.tween_property(marker, "modulate:a", 1.0, 0.6)
		marker.set_meta("pulse", pulse)
		_hole_marks.append(marker)
		var area := Button.new()
		area.size = Vector2(58, 58)
		area.position = center - area.size * 0.5
		area.focus_mode = Control.FOCUS_NONE
		area.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			area.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		area.pressed.connect(_on_punch.bind(side))
		_punch_leaf.add_child(area)
	_l1_leave_level1.call_deferred()

## 第一关收尾：孔位亮起后只留提示话术
func _l1_leave_level1() -> void:
	_hint.text = config["level1"].get("punch_hint", "")

func _on_punch(side: int) -> void:
	if not _punching or _finished:
		return
	if _hole_marks.size() <= side:
		return
	var marker: Panel = _hole_marks[side]
	if marker.get_meta("done", false):
		return
	marker.set_meta("done", true)
	var pulse: Tween = marker.get_meta("pulse")
	if pulse != null and pulse.is_running():
		pulse.kill()
	var center := _punch_leaf.position + marker.position + marker.size * 0.5
	# 按图片里锥尖的位置定位，落锥时锥尖正好碰到孔心。
	var tool := TextureRect.new()
	tool.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tool.texture = load(_assets_dir + TOOL_TEX)
	tool.size = Vector2(120, 116)
	tool.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tool.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tip := Vector2(tool.size.x * 0.02, tool.size.y * 0.91)
	tool.pivot_offset = tip
	tool.position = center - tip - Vector2(0, 90)
	tool.rotation = -0.14
	tool.modulate.a = 0.0
	_box_node.add_child(tool)
	var strike := create_tween()
	strike.tween_property(tool, "modulate:a", 1.0, 0.10)
	strike.parallel().tween_property(tool, "rotation", 0.0, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	strike.tween_property(tool, "position", center - tip, 0.16).set_trans(Tween.TRANS_SINE)
	strike.tween_callback(func() -> void:
		_play_sfx("punch")
		_impact(_box_node, center)
		_shake(_box_node)
		marker.remove_theme_stylebox_override("panel")
		marker.add_theme_stylebox_override("panel", _hole_style())
		var dust := create_tween()
		dust.tween_property(marker, "scale", Vector2(1.5, 1.5), 0.16)
		dust.tween_property(marker, "scale", Vector2.ONE, 0.20).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	)
	strike.tween_property(tool, "position", center - tip - Vector2(0, 76), 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.10)
	strike.tween_property(tool, "modulate:a", 0.0, 0.18).set_delay(0.22)
	strike.tween_callback(tool.queue_free)
	_punched += 1
	if _punched >= 2:
		_punching = true
		await get_tree().create_timer(0.95, false).timeout
		_go_level2()

func _hole_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.09, 0.08, 0.95)
	style.set_corner_radius_all(15)
	style.set_border_width_all(3)
	style.border_color = Color(ROPE, 0.95)
	return style

func _clear_all_feedback() -> void:
	for lid in _l1_cards:
		_clear_feedback(_l1_cards[lid])

func _go_level2() -> void:
	var npc: TextureRect = _l1_root.get_node("Npc")
	var move := create_tween().set_parallel()
	move.tween_property(_l1_root, "modulate:a", 0.0, 0.36)
	move.tween_property(npc, "position", Vector2(26, 126), 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	move.tween_property(npc, "size", Vector2(160, 231), 0.5)
	move.chain().tween_callback(func() -> void:
		_l1_root.visible = false
		_l2_root.visible = true
		_l2_root.modulate.a = 0.0
		_level = 2
		for i in _order.size():
			_reveal(_l2_rows[_order[i]], i * 0.055, 18.0)
		var fade := create_tween()
		fade.tween_property(_l2_root, "modulate:a", 1.0, 0.40)
	)

# ---------- 第二关：穿绳 · 排序 ----------

func _setup_level2(l2: Dictionary) -> void:
	_l2_root = Control.new()
	_l2_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_l2_root)
	_panel(_l2_root, Vector2(20, 16), Vector2(1240, 84), Color(INK, 0.90), 20)
	_label(_l2_root, l2.get("title", ""), Vector2(48, 26), Vector2(700, 36), 30, PAPER)
	_label(_l2_root, l2.get("prompt", ""), Vector2(48, 64), Vector2(700, 28), 19, Color(PAPER, 0.84))

	_panel(_l2_root, Vector2(440, 130), Vector2(366, 520), Color(INK, 0.66), 22)
	_panel(_l2_root, Vector2(898, 170), Vector2(340, 390), Color(INK, 0.91), 22)
	_label(_l2_root, l2.get("guide_title", ""), Vector2(924, 194), Vector2(284, 42), 30, GOLD)
	var guide := _label(_l2_root, l2.get("guide_text", ""), Vector2(924, 250), Vector2(284, 144), 20, PAPER)
	guide.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label(_l2_root, "拖动调整 · 金线处放入\n落下的叶子可拖回", Vector2(924, 412), Vector2(284, 60), 19, Color(PAPER, 0.82))
	_insert_marker = _panel(_l2_root, Vector2.ZERO, Vector2(350, 4), Color("#FFE09B"), 2)
	_insert_marker.z_index = 20
	_insert_marker.visible = false
	# 岩香（左上，看着你排经）
	var npc := TextureRect.new()
	npc.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	npc.texture = load(_assets_dir + NPC_TEX)
	npc.position = Vector2(26, 126)
	npc.size = Vector2(160, 231)
	npc.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	npc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_l2_root.add_child(npc)

	# 念读气泡
	_bubble = Control.new()
	_bubble.position = Vector2(26, 372)
	_bubble.size = Vector2(400, 132)
	_bubble.modulate.a = 0.0
	_l2_root.add_child(_bubble)
	var bubble_bg := Panel.new()
	bubble_bg.size = _bubble.size
	bubble_bg.position = Vector2.ZERO
	bubble_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg_style := _style(Color(PAPER, 0.94), 16)
	bg_style.set_border_width_all(2)
	bg_style.border_color = Color(GOLD, 0.8)
	bubble_bg.add_theme_stylebox_override("panel", bg_style)
	_bubble.add_child(bubble_bg)
	_label(_bubble, "岩香念", Vector2(18, 10), Vector2(200, 24), 18, Color(INK, 0.75))
	_bubble_label = _label(_bubble, "", Vector2(18, 36), Vector2(364, 82), 24, INK)
	_bubble_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP

	# 两根竖绳（装订线）
	var rope_x := [L2_X + L2_LEAF.x * 0.075, L2_X + L2_LEAF.x * 0.925]
	var rope_nodes: Array = []
	for x in rope_x:
		var rope := ColorRect.new()
		rope.color = Color(ROPE, 0.95)
		rope.position = Vector2(x - 2, 118)
		rope.size = Vector2(4, L2_Y0 + L2_STEP * 5 + L2_LEAF.y - 118)
		rope.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rope.z_index = 5
		_l2_root.add_child(rope)
		rope_nodes.append(rope)

	# 地上（散叶落脚处）
	var floor_line := ColorRect.new()
	floor_line.color = Color(GOLD, 0.22)
	floor_line.position = Vector2(40, 644)
	floor_line.size = Vector2(1200, 2)
	floor_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_l2_root.add_child(floor_line)
	_label(_l2_root, l2.get("floor_caption", ""), Vector2(40, 612), Vector2(420, 28), 18, Color(PAPER, 0.7))

	# 初始：6 张叶子已穿上绳，但顺序是乱的
	var shuffled: Array = _correct_order.duplicate()
	shuffled.shuffle()
	for lid in shuffled:
		var row := _make_leaf_row(lid)
		row.z_index = 3
		_l2_root.add_child(row)
		_l2_rows[lid] = row
		_order.append(lid)
	_reflow(0.0, true)
	# 绳压在叶面上：孔位处能看到绳穿过
	for rope in rope_nodes:
		rope.move_to_front()

	_verify_btn = Button.new()
	_verify_btn.name = "VerifyBtn"
	_verify_btn.text = l2.get("verify_text", "请岩香过目")
	_verify_btn.position = Vector2(926, 488)
	_verify_btn.size = Vector2(240, 56)
	_verify_btn.add_theme_font_size_override("font_size", 26)
	_style_button(_verify_btn)
	_verify_btn.pressed.connect(_on_verify)
	_l2_root.add_child(_verify_btn)

	_hint2 = _label(_l2_root, l2.get("hint_idle", ""), Vector2(360, 96), Vector2(600, 34), 22, PAPER, true)
	_hint2.add_theme_color_override("font_color", Color(PAPER, 0.92))

## 绳上的一行（可拖动）
func _make_leaf_row(lid: String) -> Control:
	var row := _make_leaf(_text_of[lid], L2_LEAF, true, 23)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.set_meta("leaf_id", lid)
	row.gui_input.connect(_on_row_input.bind(row))
	row.mouse_entered.connect(func() -> void:
		if _drag_row == null and not _busy and not _solved:
			_border(row, Color(GOLD, 0.8), 0.45, L2_LEAF)
	)
	return row

func _reflow(duration: float = 0.18, instant: bool = false) -> void:
	for i in _order.size():
		var lid: String = _order[i]
		if not _l2_rows.has(lid):
			continue
		var row: Control = _l2_rows[lid]
		if row == _drag_row:
			continue
		_stop_motion(row)
		# 快速拖放会中止入场渐显，归位时保证每张叶子仍完整可读。
		row.modulate.a = 1.0
		var target := Vector2(L2_X, L2_Y0 + i * L2_STEP)
		row.set_meta("home", target)
		if instant:
			row.position = target
		else:
			var tween := create_tween().set_parallel()
			row.set_meta("motion", tween)
			tween.tween_property(row, "rotation", 0.0, duration)
			tween.tween_property(row, "position", target, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tween.tween_property(row, "scale", Vector2.ONE, duration)
	for i in _floor_order.size():
		var lid2: String = _floor_order[i]
		if not _floor_rows.has(lid2):
			continue
		var row2: Control = _floor_rows[lid2]
		_stop_motion(row2)
		var target2 := Vector2(60 + i * 198, FLOOR_Y - FLOOR_LEAF.y * 0.5)
		row2.set_meta("home", target2)
		if instant:
			row2.position = target2
		else:
			var tween2 := create_tween().set_parallel()
			row2.set_meta("motion", tween2)
			tween2.tween_property(row2, "position", target2, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tween2.tween_property(row2, "scale", Vector2.ONE * 0.70, duration)

func _on_row_input(event: InputEvent, row: Control) -> void:
	if _level != 2 or _busy or _finished or _solved:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var pointer: Vector2 = _l2_root.get_global_transform().affine_inverse() * (row.get_global_transform() * event.position)
		_begin_drag(row, _floor_rows.has(str(row.get_meta("leaf_id"))), pointer)

func _on_floor_input(event: InputEvent, row: Control) -> void:
	if _level != 2 or _busy or _finished or _solved:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var pointer: Vector2 = _l2_root.get_global_transform().affine_inverse() * (row.get_global_transform() * event.position)
		_begin_drag(row, true, pointer)

func _begin_drag(row: Control, from_floor: bool, pointer: Vector2 = Vector2.INF) -> void:
	_stop_motion(row)
	row.modulate.a = 1.0
	_drag_row = row
	_insert_marker.visible = true
	_update_insert_marker(_slot_index_at(row.position.y))
	_drag_id = row.get_meta("leaf_id")
	_drag_from_floor = from_floor
	_drag_offset = (pointer if pointer != Vector2.INF else _l2_root.get_local_mouse_position()) - row.position
	row.z_index = 30
	row.mouse_default_cursor_shape = Control.CURSOR_DRAG
	if from_floor:
		_floor_order.erase(_drag_id)
		_floor_rows.erase(_drag_id)
		_l2_rows[_drag_id] = row
		_l2_root.move_child(row, _l2_root.get_child_count() - 1)
		_reflow(0.16)
	else:
		_order.erase(_drag_id)
		_reflow(0.16)
	var grow := create_tween().set_parallel()
	grow.tween_property(row, "scale", Vector2.ONE * 1.04, 0.14)
	row.set_meta("motion", grow)
	grow.tween_property(row, "rotation", -0.025, 0.14)
	row.scale = Vector2.ONE * 1.02

func _input(event: InputEvent) -> void:
	if _drag_row == null:
		return
	if not is_instance_valid(_drag_row):
		_drag_row = null
		return
	if event is InputEventMouseMotion:
		# 使用事件所在视口的坐标，避免原生光标、缩放或测试视口的缓存位置不一致。
		_drag_row.position = _l2_root.get_global_transform().affine_inverse() * event.position - _drag_offset
		_insert_index = _slot_index_at(_drag_row.position.y)
		_update_insert_marker(_insert_index)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		var row := _drag_row
		_drag_row = null
		_insert_marker.visible = false
		row.z_index = 3
		row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_commit_drag(row)
		get_viewport().set_input_as_handled()

## 落点 → 插入序号
func _slot_index_at(y: float) -> int:
	var idx := int(round((y - L2_Y0) / L2_STEP))
	return clampi(idx, 0, _order.size())

func _commit_drag(row: Control) -> void:
	var lid: String = _drag_id
	_order.erase(lid)
	var idx := _slot_index_at(row.position.y)
	idx = clampi(idx, 0, _order.size())
	_order.insert(idx, lid)
	if _drag_from_floor:
		_hint2.text = config["level2"].get("hint_ready", "")
	_drag_from_floor = false
	_border(row, Color("#FFE09B"), 0.5, L2_LEAF)
	_reflow(0.24)

# ---------- 念读验证 ----------

func _on_verify() -> void:
	var l2: Dictionary = config["level2"]
	if _level != 2 or _busy or _finished or _solved or _drag_row != null:
		return
	if _order.size() < _correct_order.size():
		_hint2.text = "还有叶子躺在地上，先把它捡回绳上"
		_hint2.add_theme_color_override("font_color", Color("#FFD1BC"))
		return
	_busy = true
	_verify_btn.disabled = true
	var first_wrong := -1
	for i in _correct_order.size():
		if _order[i] != _correct_order[i]:
			first_wrong = i
			break
	# 岩香逐句念下去
	for i in (first_wrong if first_wrong >= 0 else _correct_order.size()):
		var lid: String = _order[i]
		var row: Control = _l2_rows[lid]
		_bubble_label.text = _text_of[lid]
		var show := create_tween().set_parallel()
		show.tween_property(_bubble, "modulate:a", 1.0, 0.18)
		_border(row, Color("#FFE09B"), 0.35, L2_LEAF)
		var tw := create_tween()
		tw.tween_property(row, "position:x", L2_X + 16.0, 0.12)
		tw.tween_property(row, "position:x", L2_X, 0.16)
		_play_sfx("read")
		await get_tree().create_timer(0.42, false).timeout
	if first_wrong < 0:
		await get_tree().create_timer(0.25, false).timeout
		_on_solved()
		return
	# 念不通：这一张掉地上
	var bad_id: String = _order[first_wrong]
	_bubble_label.text = l2.get("wrong_hint", "")
	var bad_row: Control = _l2_rows[bad_id]
	_border(bad_row, Color("#EF8B73"), 1.0, L2_LEAF)
	_play_sfx("match_bad")
	_hint2.text = l2.get("wrong_hint", "")
	_hint2.add_theme_color_override("font_color", Color("#FFD1BC"))
	_fail_streak += 1
	await get_tree().create_timer(0.35, false).timeout
	_drop_to_floor(bad_id)
	await get_tree().create_timer(0.62, false).timeout
	if _fail_streak >= 3:
		_fail_streak = 0
		_hint2.text = l2.get("fail3_hint", "")
		_hint2.add_theme_color_override("font_color", GOLD)
		# 金光指向：本该接在这一位的叶子
		var wrong_index := 0
		while wrong_index < _order.size() and wrong_index < _correct_order.size() \
				and _order[wrong_index] == _correct_order[wrong_index]:
			wrong_index += 1
		var target_id: String = _correct_order[clampi(wrong_index, 0, _correct_order.size() - 1)]
		if _l2_rows.has(target_id):
			_pulse_gold(_l2_rows[target_id], L2_LEAF)
		elif _floor_rows.has(target_id):
			_pulse_gold(_floor_rows[target_id], FLOOR_LEAF)
	await get_tree().create_timer(0.4, false).timeout
	var hid := create_tween()
	hid.tween_property(_bubble, "modulate:a", 0.0, 0.25)
	_busy = false
	_verify_btn.disabled = false

## 掉地上：从绳上滑落到地面条
func _drop_to_floor(lid: String) -> void:
	var row: Control = _l2_rows[lid]
	_order.erase(lid)
	_l2_rows.erase(lid)
	_floor_order.append(lid)
	_floor_rows[lid] = row
	var land_x := 60.0 + (_floor_order.size() - 1) * 198.0
	var tween := create_tween()
	tween.tween_property(row, "position", Vector2(L2_X - 40, 470), 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(row, "rotation", -0.10, 0.18)
	tween.tween_property(row, "position", Vector2(land_x + 40, FLOOR_Y + 26 - FLOOR_LEAF.y * 0.5), 0.34).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(row, "rotation", 0.05, 0.34)
	tween.tween_property(row, "position:y", FLOOR_Y - FLOOR_LEAF.y * 0.5, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(row, "rotation", 0.0, 0.16)
	tween.parallel().tween_property(row, "scale", Vector2.ONE * 0.70, 0.34)
	tween.tween_callback(func() -> void:
		row.set_meta("home", row.position)
		_reflow(0.14)
	)

# ---------- 通关：誓约演出 ----------

func _on_solved() -> void:
	_solved = true
	_verify_btn.disabled = true
	_hint2.text = "六句约定接上了，岩香又看了一遍古锦照片。"
	_hint2.add_theme_color_override("font_color", GOLD)
	var hide_bubble := create_tween()
	hide_bubble.tween_property(_bubble, "modulate:a", 0.0, 0.25)
	await get_tree().create_timer(0.6, false).timeout
	if _is_deferred_story():
		_complete()
		return
	var l2: Dictionary = config["level2"]
	var layer := CanvasLayer.new()
	layer.layer = 40
	add_child(layer)
	var viewport_size := get_viewport().get_visible_rect().size
	var dim := ColorRect.new()
	dim.color = Color(INK, 0.80)
	dim.size = viewport_size
	dim.modulate.a = 0.0
	layer.add_child(dim)
	var card := Control.new()
	card.size = Vector2(920, 470)
	card.position = (viewport_size - card.size) * 0.5
	card.pivot_offset = card.size * 0.5
	layer.add_child(card)
	var paper := TextureRect.new()
	paper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	paper.texture = load("res://assets/shared/paper_base.png")
	paper.size = card.size
	paper.stretch_mode = TextureRect.STRETCH_SCALE
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(paper)
	_label(card, "普洱 · 贝叶经归册", Vector2(60, 44), Vector2(800, 26), 19, Color(INK, 0.8), true)
	_label(card, "岩香念到最后一段，停住了", Vector2(60, 74), Vector2(800, 44), 34, INK, true)
	_label(card, l2.get("oath_intro", ""), Vector2(80, 140), Vector2(760, 34), 22, INK, true)
	var quote_plate := Panel.new()
	quote_plate.position = Vector2(90, 178)
	quote_plate.size = Vector2(740, 108)
	quote_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var plate_style := _style(Color(GOLD, 0.13), 14)
	plate_style.set_border_width_all(2)
	plate_style.border_color = Color(GOLD, 0.75)
	quote_plate.add_theme_stylebox_override("panel", plate_style)
	card.add_child(quote_plate)
	var oath_quote := Label.new()
	oath_quote.text = l2.get("oath_text", "")
	oath_quote.position = Vector2(100, 186)
	oath_quote.size = Vector2(720, 92)
	oath_quote.add_theme_font_override("font", EMPHASIS_FONT)
	oath_quote.add_theme_font_size_override("font_size", 34)
	oath_quote.add_theme_color_override("font_color", Color("#8A5A1E"))
	oath_quote.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	oath_quote.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	oath_quote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	oath_quote.mouse_filter = Control.MOUSE_FILTER_IGNORE
	oath_quote.modulate.a = 0.0
	card.add_child(oath_quote)
	_label(card, l2.get("oath_tail", ""), Vector2(80, 302), Vector2(760, 34), 22, INK, true)
	var btn := Button.new()
	btn.text = "收下这段誓约"
	btn.position = Vector2(290, 366)
	btn.size = Vector2(340, 58)
	btn.add_theme_font_size_override("font_size", 25)
	_style_button(btn)
	btn.pressed.connect(func() -> void:
		layer.queue_free()
		_complete()
	)
	card.add_child(btn)
	card.scale = Vector2.ONE * 0.9
	card.modulate.a = 0.0
	var show := create_tween().set_parallel()
	show.tween_property(dim, "modulate:a", 1.0, 0.28)
	show.tween_property(card, "modulate:a", 1.0, 0.26)
	show.tween_property(card, "scale", Vector2.ONE, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	show.tween_property(oath_quote, "modulate:a", 1.0, 0.6).set_delay(0.35)

# ---------- 结算页（替换基类占位） ----------

func _show_win_placeholder(fragment_ids: Array) -> void:
	if _is_deferred_story():
		# 主线自动返回接收尾，不显示提前领奖或额外确认按钮。
		puzzle_completed.emit(station_id, fragment_ids)
		_back_to_map()
		return
	_win_layer = CanvasLayer.new()
	_win_layer.layer = 60
	add_child(_win_layer)
	var viewport_size := get_viewport().get_visible_rect().size
	var dim := ColorRect.new()
	dim.color = Color(INK, 0.86)
	dim.size = viewport_size
	_win_layer.add_child(dim)
	var card := Control.new()
	card.size = Vector2(960, 520)
	card.position = (viewport_size - card.size) * 0.5
	card.pivot_offset = card.size * 0.5
	dim.add_child(card)
	var paper := TextureRect.new()
	paper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	paper.texture = load("res://assets/shared/paper_base.png")
	paper.size = card.size
	paper.stretch_mode = TextureRect.STRETCH_SCALE
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(paper)
	_label(card, "普洱 · 奘房", Vector2(60, 44), Vector2(840, 26), 19, Color(INK, 0.8), true)
	_label(card, "贝叶经归册完成", Vector2(60, 74), Vector2(840, 56), 42, INK, true)
	_label(card, "六句互助约定，一页一页归了位", Vector2(60, 138), Vector2(840, 30), 23, INK, true)

	# 排序结果一览
	for i in _correct_order.size():
		var lid: String = _correct_order[i]
		var mini := _make_leaf(_text_of[lid], Vector2(268, 62), true, 19)
		mini.position = Vector2(66 + (i % 3) * 280, 190 + (i / 3) * 82)
		mini.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(mini)
		mini.modulate.a = 0.0
		mini.scale = Vector2.ONE * 0.86
		var reveal := create_tween().set_parallel()
		reveal.tween_property(mini, "modulate:a", 1.0, 0.22).set_delay(0.30 + i * 0.07)
		reveal.tween_property(mini, "scale", Vector2.ONE, 0.3).set_delay(0.30 + i * 0.07).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_label(card, "获得 · 贝叶誓约碎片" if not fragment_ids.is_empty() else "贝叶经归册完成", Vector2(80, 386), Vector2(800, 36), 27, INK, true)
	var button := Button.new()
	button.text = "带上碎片 · 返回地图"
	button.position = Vector2(320, 438)
	button.size = Vector2(320, 56)
	button.add_theme_font_size_override("font_size", 25)
	_style_button(button)
	button.pressed.connect(func() -> void:
		puzzle_completed.emit(station_id, fragment_ids)
		_back_to_map()
	)
	card.add_child(button)
	card.scale = Vector2.ONE * 0.88
	card.modulate.a = 0.0
	var tween := create_tween().set_parallel()
	tween.tween_property(card, "modulate:a", 1.0, 0.28)
	tween.tween_property(card, "scale", Vector2.ONE, 0.46).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# ---------- 视觉与动效 ----------

func _is_deferred_story() -> bool:
	return _gs == get_node_or_null("/root/GameState") and SceneRouter.params.get("defer_reward", false) and SceneRouter.params.get("station", "") == station_id

func _stop_motion(node: Control) -> void:
	var motion: Tween = node.get_meta("motion") if node.has_meta("motion") else null
	if motion != null and motion.is_valid():
		motion.kill()

func _hover_leaf(card: Control, active: bool, selected: bool) -> void:
	_stop_motion(card)
	card.modulate.a = 1.0
	var motion := create_tween().set_parallel()
	card.set_meta("motion", motion)
	var lift := -8.0 if selected else 0.0
	if active:
		lift -= 4.0
	motion.tween_property(card, "position", (card.get_meta("home") as Vector2) + Vector2(0, lift), 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	motion.tween_property(card, "scale", Vector2.ONE * (1.035 if active or selected else 1.0), 0.18)
	card.z_index = 2 if active or selected else 0

func _set_selected(card: Control, selected: bool) -> void:
	var old := card.get_node_or_null("Selected")
	if old != null:
		card.remove_child(old)
		old.queue_free()
	if not selected:
		return
	var frame := _panel(card, Vector2(4, 1), L1_LEAF - Vector2(8, 2), Color(GOLD, 0.06), 12)
	frame.name = "Selected"
	var style := frame.get_theme_stylebox("panel") as StyleBoxFlat
	style.set_border_width_all(2)
	style.border_color = Color("#FFE09B")
	_label(frame, "✓", Vector2(L1_LEAF.x - 29, 1), Vector2(22, 24), 18, Color("#FFE09B"), true)

func _reveal(node: Control, delay: float, lift: float) -> void:
	_stop_motion(node)
	var home := node.position
	node.position.y += lift
	node.modulate.a = 0.0
	var motion := create_tween().set_parallel()
	node.set_meta("motion", motion)
	motion.tween_property(node, "position", home, 0.42).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	motion.tween_property(node, "modulate:a", 1.0, 0.32).set_delay(delay)

func _step_badges(parent: Control, pos: Vector2, active: int) -> void:
	var titles := ["选叶", "打孔", "排序"]
	for i in titles.size():
		var box := _panel(parent, pos + Vector2(i * 88, 0), Vector2(72, 42), Color(GOLD, 0.18) if i == active else Color(INK, 0.62), 12)
		box.set_meta("step", i)
		_label(box, titles[i], Vector2.ZERO, box.size, 22, GOLD if i == active else Color(PAPER, 0.6), true)

func _update_insert_marker(index: int) -> void:
	_insert_marker.position = Vector2(L2_X - 12, L2_Y0 + index * L2_STEP - 5)

func _impact(parent: Control, center: Vector2) -> void:
	for i in 10:
		var angle := TAU * float(i) / 10.0
		var spark := _dot(parent, center, 2.0 + (i % 3), Color("#FFE09B"), Color(GOLD, 0.0))
		var fly := create_tween().set_parallel()
		fly.tween_property(spark, "position", spark.position + Vector2(cos(angle), sin(angle)) * (26.0 + i * 2), 0.38).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		fly.tween_property(spark, "modulate:a", 0.0, 0.38)
		fly.chain().tween_callback(spark.queue_free)

# 仅为贝叶关卡定制说明页，其他小游戏沿用基类。
func _build_intro() -> void:
	_intro_layer = CanvasLayer.new()
	_intro_layer.layer = 50
	add_child(_intro_layer)
	var dim := ColorRect.new()
	dim.size = get_viewport().get_visible_rect().size
	dim.color = Color(INK, 0.82)
	_intro_layer.add_child(dim)
	var card := _panel(dim, (dim.size - Vector2(900, 460)) * 0.5, Vector2(900, 460), Color(INK, 0.97), 24)
	card.add_theme_stylebox_override("panel", UiKit.surface("silk", 0))
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	_label(card, "茶马古道  /  普洱 · 奘房", Vector2(48, 28), Vector2(804, 30), 20, GOLD, true)
	_label(card, config.get("intro_title", "贝叶经归册"), Vector2(48, 72), Vector2(804, 64), 42, PAPER, true)
	var body := _label(card, config.get("intro_text", ""), Vector2(70, 152), Vector2(760, 150), 23, Color(PAPER, 0.9), true)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_step_badges(card, Vector2(326, 314), 0)
	var button := UiKit.button("开始归册", _on_intro_start, true)
	button.position = Vector2(330, 378)
	button.size = Vector2(240, 56)
	button.add_theme_font_size_override("font_size", 25)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.add_child(button)
	_reveal(card, 0.0, 16.0)

func _activate_step(parent: Control, active: int) -> void:
	for child in parent.get_children():
		if child.has_meta("step"):
			var selected: bool = int(child.get_meta("step")) == active
			var style := child.get_theme_stylebox("panel") as StyleBoxFlat
			style.bg_color = Color(GOLD, 0.18) if selected else Color(INK, 0.62)
			child.get_child(0).add_theme_color_override("font_color", GOLD if selected else Color(PAPER, 0.6))
