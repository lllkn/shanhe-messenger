extends PuzzleBase
## PuzzleDye —— 香格里拉·五色配置（接口约定 v5 注册表 #2）
## 第一关「补锦纹（填色）」：旧锦褪色，选五色之一 → 点或按住拖过纹样 → 整块自动补齐
##   · 38 块多边形（莲花团花：三层莲瓣 + 莲蓬莲子 + 涟漪 + 角苞），数据在 puzzles.json
##   · 色号高对比 + 选中一色将其余置灰 + 丹增气泡按情境提示
##   · 选错色静默不生效（治愈向不报错）；由丹增安静提示所需颜色
##   · Ctrl+Z 撤销；补色进度与完成演出；手动进入第二关
## 第二关「染一缸」：五色按口诀下料 → 看火 → 搅缸 → 观色
## 文化口径见 games/02-香格里拉-五色配置.md（口诀为自拟，依据强度已如实标注）。

const GOLD := Color("#C9A24B")     # 藤黄金（唯一高亮色）
const RED := Color("#B5482F")      # 灯笼暖红（错误反馈）
const INK := Color("#1E3A34")      # 松烟墨青
const PAPER := Color("#EDE3CB")    # 宣纸米白
const MURKY := Color(0.36, 0.34, 0.29)
const LINE := Color("#4A4234")     # 描边线稿
const NO_LABEL := Color("#5C5546")

const PATTERN_ORIGIN := Vector2(104, 104)
const PATTERN_SIZE := 560.0
const VAT_SIZE := Vector2(368, 342)      # 第二关染缸显示尺寸
const LOT_CARD := Vector2(132, 174)      # 第二关料钵卡尺寸

var _assets_dir := ""
var _level := 0

# ---- 第一关（填色）----
var _l1_root: Control
var _pattern_root: Control
var _region_nodes: Dictionary = {}        # id -> Polygon2D
var _region_outlines: Dictionary = {}     # id -> Line2D
var _region_labels: Dictionary = {}       # id -> Label
var _region_no: Dictionary = {}           # id -> 色号
var _region_order: Array = []             # 绘制顺序（后面的盖在上面）
var _filled: Dictionary = {}              # id -> true
var _undo_stack: Array = []
var _miss_count: Dictionary = {}
var _palette: Array = []
var _hex_of_no: Dictionary = {}
var _color_of_no: Dictionary = {}
var _chip_nodes: Dictionary = {}
var _selected_no := 0
var _unfilled := Color("#D6C9AC")
var _unfilled_dim := Color("#C0B296")
var _l1_progress: Label
var _fill_bar: ProgressBar
var _fill_tweens: Dictionary = {}
var _hint_tween: Tween
var _hover_id := ""
var _dragging := false
var _l1_done := false

# ---- 第二关（染缸）----
var _l2_root: Control
var _lot_root: Control
var _lot_cards: Dictionary = {}
var _lot_hover_card: Control
var _lot_hover_elapsed := 0.0
var _lot_hover_pending := false
var _vat_root: Control
var _water: ColorRect
var _water_material: ShaderMaterial
var _water_color := MURKY
var _water_tween: Tween
var _stir_guide: Control
var _stir_status: Label
var _swatch_nodes: Array[Panel] = []
var _modal_layer: CanvasLayer
var _flow := 0.0
var _energy := 0.0
var _visual_angle := 0.0
var _elapsed := 0.0
var _stir_direction := 1.0
var _mouse_position := Vector2.ZERO
var _mouse_pressed := false
var _stir_impulse := 0.0
var _stir_sprite: TextureRect
var _stir_bar: ProgressBar
var _fire: TextureRect
var _progress: Label
var _order: Array = []
var _material_of_color: Dictionary = {}
var _material_name_of_color: Dictionary = {}
var _hex_of_color: Dictionary = {}
var _step := 0
var _phase := ""
var _stir_acc := 0.0
var _stir_left := 0.0
var _stir_needed := 2.0
var _stir_window := 4.0
var _prev_angle := NAN
var _l2_wrong := 0
var _drag_card: Control = null
var _drag_offset := Vector2.ZERO
var _l2_all_done := false
var _npc: TextureRect
var _speech: Control
var _action_button: Button
var _knowledge_continue: Button
var _action: Callable
var _stir_tip_given := false
var _activity_title: Label
var _activity_text: Label
var _start_button: Button
var _selected_hint: Label
var _selected_swatch: Panel
var _settlement_continue: Button

# ---------- 钩子 ----------

func _on_setup(cfg: Dictionary) -> void:
	_assets_dir = cfg.get("assets_dir", "res://assets/puzzles/xianggelila/")
	var bg := TextureRect.new()
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.texture = _tex(_assets_dir + "bg_danzeng_yard.png")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	if bg.texture == null:
		var fallback := ColorRect.new()
		fallback.color = Color(0.12, 0.18, 0.16)
		fallback.set_anchors_preset(Control.PRESET_FULL_RECT)
		fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(fallback)
	var shade := ColorRect.new()
	shade.color = Color(0.08, 0.12, 0.10, 0.34)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	_setup_level1(cfg["level1"])
	_setup_level2(cfg["level2"])
	_setup_guide()
	_setup_activity_card()
	for child in get_children():
		if child is Button:
			child.add_theme_stylebox_override("normal", _style(INK, 8))
			child.add_theme_stylebox_override("hover", _style(Color("34574b"), 8))
			child.add_theme_color_override("font_color", PAPER)
			move_child(child, -1)
	_l1_root.visible = true
	_l2_root.visible = false

func _on_start() -> void:
	_intro_layer.queue_free()
	_level = 1
	_l1_root.visible = true
	_reveal(_l1_root)
	_action_button.visible = false
	_refresh_dimming()
	_speech.call("clear")
	_say("先选一色，再点锦上同号的花瓣。", 5.0, 1)

func _check_win() -> bool:
	return _l1_done and _l2_all_done

func _on_complete() -> void:
	_phase = "done"
	var flash := ColorRect.new()
	flash.color = Color(GOLD, 0.0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash)
	var tween := create_tween()
	tween.tween_property(flash, "color:a", 0.38, 0.5)
	tween.tween_property(flash, "color:a", 0.0, 1.2)
	_popup("五色成一匹", GOLD, Vector2(0, 250))

func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_mouse_pressed = false
		_dragging = false
		_prev_angle = NAN
		_lot_hover_pending = false
		_lot_hover_card = null
		if is_instance_valid(_drag_card):
			_drag_card.position = _drag_card.get_meta("home")
			_drag_card.scale = Vector2.ONE
			_drag_card.rotation = 0.0
		_drag_card = null

func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_mouse_position = get_canvas_transform().affine_inverse() * event.position
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_mouse_pressed = event.pressed
		_prev_angle = NAN
		if not event.pressed:
			_dragging = false
			if _drag_card != null:
				var card := _drag_card
				_drag_card = null
				_drop_material(card)
	elif event is InputEventMouseMotion:
		if _drag_card != null:
			var local_mouse := _lot_root.get_global_transform().affine_inverse() * _mouse_position
			_drag_card.position = local_mouse - _drag_offset
		if _phase == "stir":
			_sample_stir_pointer()

func _unhandled_input(event: InputEvent) -> void:
	if not _started or _finished:
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key: int = event.keycode
	if _level == 1 and not _l1_done:
		match key:
			KEY_1: _select_no(1)
			KEY_2: _select_no(2)
			KEY_3: _select_no(3)
			KEY_4: _select_no(4)
			KEY_5: _select_no(5)
			KEY_Q: _cycle_no(-1)
			KEY_E: _cycle_no(1)
			KEY_Z:
				if event.ctrl_pressed:
					_undo()

func _process(delta: float) -> void:
	_elapsed += delta
	_refresh_activity_card()
	if _dragging and not _mouse_pressed:
		_dragging = false
	if _level != 2:
		return
	_process_lot_hover(delta)
	var moving := false
	if _phase == "stir":
		_stir_left = maxf(0.0, _stir_left - delta)
		_stir_bar.value = _stir_left
		var normalized := (_mouse_position - _water_center()) / (_water.size * 0.5)
		var dist := normalized.length()
		var angle := normalized.angle()
		if _mouse_pressed and dist > 0.23 and dist < 1.65:
			_visual_angle = lerp_angle(_visual_angle, angle, 1.0 - exp(-delta * 20.0))
		moving = _stir_impulse > 0.0 and _mouse_pressed
		var ratio := clampf(_stir_acc / (TAU * _stir_needed), 0.0, 1.0)
		_stir_guide.set("progress", ratio)
		_stir_guide.set("active", moving)
		_stir_status.text = "搅匀 %d%%   ·   余 %.1f 秒" % [roundi(ratio * 100), _stir_left]
		_stir_status.add_theme_color_override("font_color", GOLD.lightened(0.25) if _stir_left > 1.2 else Color("efac87"))
		if not _stir_tip_given and _stir_left < _stir_window * 0.55 and ratio < 0.35:
			_stir_tip_given = true
			_say("别点木棒，按住水面绕圈就好。", 3.0, 3)
		if ratio >= 1.0:
			_finish_stir()
		elif _stir_left <= 0.0:
			_stir_timeout()
	_stir_impulse = maxf(0.0, _stir_impulse - delta)
	_energy = lerpf(_energy, 1.0 if moving else 0.0, 1.0 - exp(-delta * 4.0))
	if not moving:
		_flow += _stir_direction * _energy * delta * 1.4
	_water_material.set_shader_parameter("flow", _flow)
	_water_material.set_shader_parameter("clock", _elapsed)
	_water_material.set_shader_parameter("energy", _energy)
	var orbit := Vector2(cos(_visual_angle), sin(_visual_angle)) * _water.size * Vector2(0.31, 0.29)
	_stir_sprite.position = _water.position + _water.size * 0.5 + orbit - _stir_sprite.pivot_offset
	_stir_sprite.rotation = sin(_visual_angle) * 0.16 - 0.12
	_water_material.set_shader_parameter("spoon", Vector2(0.5, 0.5) + orbit / _water.size)

func _sample_stir_pointer() -> void:
	# Count every input event, including multiple movements within one frame.
	var normalized := (_mouse_position - _water_center()) / (_water.size * 0.5)
	if not _mouse_pressed or normalized.length() <= 0.23 or normalized.length() >= 1.65:
		_prev_angle = NAN
		return
	var angle := normalized.angle()
	if not is_nan(_prev_angle):
		var turn := wrapf(angle - _prev_angle, -PI, PI)
		if absf(turn) < 0.72 and absf(turn) > 0.004:
			_stir_acc += absf(turn)
			_flow += turn
			_stir_direction = signf(turn)
			_stir_impulse = 0.12
	_prev_angle = angle

func _water_center() -> Vector2:
	return _water.global_position + _water.size * 0.5

func _reveal(control: Control) -> void:
	control.modulate.a = 0.0
	create_tween().tween_property(control, "modulate:a", 1.0, 0.4).set_trans(Tween.TRANS_SINE)

# ---------- 通用 ----------

func _tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	push_warning("PuzzleDye: 素材缺失 " + path)
	return null

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
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	return panel

func _label(parent: Control, text: String, pos: Vector2, dimensions: Vector2, font_size: int, color: Color, centered: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.size = dimensions
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if centered:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(label)
	return label

## 文字压在实景上会看不清：加一圈深色描边（游戏 UI 通行做法）
func _outline(label: Label, width: int = 6) -> Label:
	label.add_theme_constant_override("outline_size", width)
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.09, 0.08, 0.88))
	return label

func _popup(text: String, color: Color, pos: Vector2 = Vector2(0, 200)) -> void:
	var pop := Label.new()
	pop.text = text
	pop.add_theme_font_size_override("font_size", 44)
	pop.add_theme_color_override("font_color", color)
	pop.position = pos
	pop.size = Vector2(1280, 60)
	pop.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pop)
	var tween := create_tween().set_parallel()
	tween.tween_property(pop, "position:y", pos.y - 70.0, 0.9)
	tween.tween_property(pop, "modulate:a", 0.0, 0.9)
	tween.chain().tween_callback(pop.queue_free)

func _shake(control: Control) -> void:
	var origin := control.position
	var tween := create_tween()
	for i in 3:
		tween.tween_property(control, "position:x", origin.x + 9.0, 0.045)
		tween.tween_property(control, "position:x", origin.x - 9.0, 0.045)
	tween.tween_property(control, "position:x", origin.x, 0.045)

# ---------- 第一关 · 补锦纹（填色） ----------

func _setup_level1(l1: Dictionary) -> void:
	_l1_root = Control.new()
	_l1_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_l1_root)

	_panel(_l1_root, Vector2(94, 102), Vector2(580, 568), Color(PAPER, 0.98), 8)

	_palette = l1.get("palette", [])
	for p in _palette:
		_hex_of_no[int(p["no"])] = Color(p["hex"])
		_color_of_no[int(p["no"])] = p.get("color", "")
	_unfilled = Color(l1.get("unfilled_hex", "#D6C9AC"))
	_unfilled_dim = _unfilled.darkened(0.12)

	# 纹样：按顺序叠放 Polygon2D + 描边 Line2D + 色号 Label（后画的盖在上面）
	_pattern_root = Control.new()
	_pattern_root.position = PATTERN_ORIGIN
	_pattern_root.size = Vector2(PATTERN_SIZE, PATTERN_SIZE)
	_pattern_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_pattern_root.gui_input.connect(_on_pattern_input)
	_l1_root.add_child(_pattern_root)
	for reg in l1.get("regions", []):
		var id: String = reg["id"]
		var pts := PackedVector2Array()
		for p in reg["poly"]:
			pts.append(Vector2(p[0], p[1]) * PATTERN_SIZE)
		var poly := Polygon2D.new()
		poly.polygon = pts
		poly.color = _unfilled
		poly.antialiased = true
		_pattern_root.add_child(poly)
		var line := Line2D.new()
		var closed := pts.duplicate()
		closed.append(pts[0])
		line.points = closed
		line.width = 2.0
		line.default_color = LINE
		line.antialiased = true
		_pattern_root.add_child(line)
		var centroid := Vector2.ZERO
		for v in pts:
			centroid += v
		centroid /= float(pts.size())
		var lab := Label.new()
		lab.text = str(int(reg["no"]))
		lab.add_theme_font_size_override("font_size", 16)
		lab.add_theme_color_override("font_color", NO_LABEL)
		lab.position = centroid - Vector2(14, 12)
		lab.size = Vector2(28, 24)
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pattern_root.add_child(lab)
		_region_nodes[id] = poly
		_region_outlines[id] = line
		_region_labels[id] = lab
		_region_no[id] = int(reg["no"])
		_region_order.append(id)

	# 调色板（右侧竖排，圆角色片 + 色号；1-5 / Q·E 也可选色）
	var px := 730.0
	var py := 536.0
	for i in _palette.size():
		var p: Dictionary = _palette[i]
		var x := px + i * 79.0
		var chip := Control.new()
		chip.position = Vector2(x, py)
		chip.size = Vector2(68, 106)
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		chip.gui_input.connect(_on_chip_input.bind(int(p["no"])))
		var bg := Panel.new()
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.add_theme_stylebox_override("panel", _chip_style(false))
		chip.add_child(bg)
		var sw := Panel.new()
		sw.position = Vector2(12, 8)
		sw.size = Vector2(44, 44)
		sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sw.add_theme_stylebox_override("panel", _style(Color(p["hex"]), 22))
		chip.add_child(sw)
		_label(chip, str(int(p["no"])), Vector2(12, 8), Vector2(44, 44), 20, _readable_on(Color(p["hex"])), true)
		_outline(_label(chip, p.get("color", ""), Vector2(4, 54), Vector2(60, 24), 18, PAPER, true), 3)
		chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var selected_mark := _label(chip, "已选", Vector2(0, 81), Vector2(68, 25), 18, GOLD.lightened(0.2), true)
		selected_mark.visible = false
		chip.set_meta("mark", selected_mark)
		chip.set_meta("bg", bg)
		_l1_root.add_child(chip)
		_chip_nodes[int(p["no"])] = chip

	_l1_progress = _outline(_label(_l1_root, "", Vector2(746, 38), Vector2(382, 32), 24, PAPER, true), 3)
	_fill_bar = ProgressBar.new()
	_fill_bar.position = Vector2(746, 86)
	_fill_bar.size = Vector2(382, 5)
	_fill_bar.show_percentage = false
	_fill_bar.add_theme_font_size_override("font_size", 1)
	_fill_bar.add_theme_stylebox_override("background", _style(Color(PAPER, 0.22), 3))
	_fill_bar.add_theme_stylebox_override("fill", _style(GOLD, 3))
	_l1_root.add_child(_fill_bar)
	_pattern_root.mouse_exited.connect(_clear_hover)
	var selected_card := _panel(_l1_root, Vector2(714, 440), Vector2(424, 82), Color(INK, 0.96), 12)
	selected_card.z_index = 1
	selected_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_selected_swatch = Panel.new()
	_selected_swatch.position = Vector2(14, 19)
	_selected_swatch.size = Vector2(44, 44)
	_selected_swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selected_card.add_child(_selected_swatch)
	_selected_hint = _label(selected_card, "", Vector2(72, 8), Vector2(342, 68), 26, PAPER)
	_selected_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_select_no(int(_palette[0]["no"]) if _palette.size() > 0 else 0)
	_refresh_progress()

func _chip_style(selected: bool) -> StyleBoxFlat:
	var style := _style(Color(INK, 0.72) if selected else Color(INK, 0.35), 12)
	style.set_border_width_all(4 if selected else 1)
	style.border_color = GOLD if selected else Color(PAPER, 0.16)
	return style

func _readable_on(color: Color) -> Color:
	return Color("#F2EADA") if (color.r + color.g + color.b) < 1.6 else Color("#4A4335")

func _on_chip_input(event: InputEvent, no: int) -> void:
	if _started and not _finished and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_select_no(no)

func _select_no(no: int) -> void:
	if _l1_done or not _chip_nodes.has(no):
		return
	_selected_no = no
	for n in _chip_nodes:
		var bg: Panel = _chip_nodes[n].get_meta("bg")
		bg.add_theme_stylebox_override("panel", _chip_style(_started and n == no))
		(_chip_nodes[n].get_meta("mark") as Label).visible = _started and n == no
	_refresh_dimming()
	if _started and _level == 1:
		_say("取了%s色，找锦上的 %d 号。" % [_color_of_no[no], no])
	if not _hover_id.is_empty():
		_refresh_hover_text(_hover_id)

func _cycle_no(dir: int) -> void:
	for i in _palette.size():
		if int(_palette[i]["no"]) == _selected_no:
			_select_no(int(_palette[(i + dir + _palette.size()) % _palette.size()]["no"]))
			return

## 选中一色后降低其他未涂区域的亮度。
func _refresh_dimming() -> void:
	var remaining := 0
	for id in _region_order:
		if _filled.has(id):
			continue
		var poly: Polygon2D = _region_nodes[id]
		var matching: bool = _started and _region_no[id] == _selected_no
		if matching:
			remaining += 1
		poly.color = _unfilled.lerp(_hex_of_no[_selected_no], 0.24) if matching else _unfilled_dim
		var label: Label = _region_labels[id]
		label.modulate.a = 1.0 if matching else 0.45
		label.add_theme_font_size_override("font_size", 22 if matching else 16)
		label.add_theme_color_override("font_color", INK if matching else NO_LABEL)
		_style_region_hint(id)
	if is_instance_valid(_selected_hint):
		_selected_hint.text = "已选 %d 号 · %s色\n描金 %d 号 · 还剩 %d 处" % [_selected_no, _color_of_no[_selected_no], _selected_no, remaining]
		_selected_swatch.add_theme_stylebox_override("panel", _style(_hex_of_no[_selected_no], 22))
	for n in _chip_nodes:
		(_chip_nodes[n].get_meta("bg") as Panel).add_theme_stylebox_override("panel", _chip_style(_started and n == _selected_no))
		(_chip_nodes[n].get_meta("mark") as Label).visible = _started and n == _selected_no

func _style_region_hint(id: String) -> void:
	var matching: bool = _started and not _filled.has(id) and _region_no[id] == _selected_no
	var line: Line2D = _region_outlines[id]
	line.default_color = GOLD if matching else LINE
	line.width = 3.4 if matching else (2.4 if _filled.has(id) else 1.5)

func _refresh_progress() -> void:
	var total := _region_order.size()
	_l1_progress.text = "补锦   %d / %d" % [_filled.size(), total]
	_fill_bar.value = float(_filled.size()) / maxf(total, 1.0) * 100.0

func _on_pattern_input(event: InputEvent) -> void:
	if _l1_done or not _started:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_try_fill_at(event.position)
		else:
			_dragging = false
	elif event is InputEventMouseMotion:
		_hover_at(event.position)
		if _dragging:
			_try_fill_at(event.position)

func _hit_region(local_pos: Vector2) -> String:
	for i in range(_region_order.size() - 1, -1, -1):
		var id: String = _region_order[i]
		var poly: Polygon2D = _region_nodes[id]
		if Geometry2D.is_point_in_polygon(local_pos, poly.polygon):
			return id
	return ""

func _clear_hover() -> void:
	_hover_at(Vector2(-100, -100))
	_dragging = false

func _hover_at(local_pos: Vector2) -> void:
	if _l1_done:
		return
	var id := _hit_region(local_pos)
	if id == _hover_id:
		return
	if _hover_id != "" and _region_outlines.has(_hover_id):
		_style_region_hint(_hover_id)
	_hover_id = id
	if id == "":
		return
	var line: Line2D = _region_outlines[id]
	line.default_color = Color("f3dfaa")
	line.width = 3.0
	_refresh_hover_text(id)

func _refresh_hover_text(id: String) -> void:
	if not _started or _l1_done:
		return
	# A short dwell prevents the NPC from changing lines as the mouse sweeps.
	get_tree().create_timer(0.18, false).timeout.connect(func():
		if _hover_id != id or _l1_done or _level != 1:
			return
		var no: int = _region_no[id]
		if _filled.has(id):
			_say("这一瓣补好了，再看看旁边。", 2.5)
		elif no == _selected_no:
			_say("对，用%s色，点亮这一瓣。" % _color_of_no[no], 3.5)
		else:
			_say("这一瓣要%s色，取 %d 号再补。" % [_color_of_no[no], no], 3.5)
	)

func _try_fill_at(local_pos: Vector2) -> void:
	var id := _hit_region(local_pos)
	if id == "" or _filled.has(id):
		return
	if _region_no[id] != _selected_no:
		# 选错不扣分，由丹增提示正确颜色。
		_miss_count[id] = int(_miss_count.get(id, 0)) + 1
		if int(_miss_count[id]) == 1 or int(_miss_count[id]) >= 3:
			_miss_count[id] = 0
			_quiet_hint(id)
		return
	_apply_fill(id)

func _apply_fill(id: String) -> void:
	if _filled.has(id):
		return
	_filled[id] = true
	_undo_stack.append(id)
	var target: Color = _hex_of_no[_region_no[id]]
	var poly: Polygon2D = _region_nodes[id]
	poly.color = target.lightened(0.4)
	var tween := create_tween()
	_fill_tweens[id] = tween
	tween.tween_property(poly, "color", target, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var line: Line2D = _region_outlines[id]
	line.default_color = LINE
	line.width = 2.4
	(_region_labels[id] as Label).visible = false
	if id == _hover_id:
		_refresh_hover_text(id)
	_play_sfx("fill")
	_refresh_dimming()
	_refresh_progress()
	if _filled.size() >= _region_order.size():
		_finish_level1()

## 选错时由丹增提醒，同时轻亮对应色。
func _quiet_hint(id: String) -> void:
	var no: int = _region_no[id]
	_say("这瓣需要%s色，选 %d 号就好。" % [_color_of_no[no], no], 3.0, 3)
	if _hint_tween and _hint_tween.is_running():
		_hint_tween.kill()
	var bg: Panel = _chip_nodes[no].get_meta("bg")
	_hint_tween = create_tween()
	_hint_tween.tween_property(bg, "modulate", Color(1.35, 1.25, 1.0), 0.2)
	_hint_tween.tween_property(bg, "modulate", Color.WHITE, 0.35)

func _undo() -> void:
	if _undo_stack.is_empty():
		return
	var id: String = _undo_stack.pop_back()
	_filled.erase(id)
	if _fill_tweens.has(id) and _fill_tweens[id].is_running():
		_fill_tweens[id].kill()
	(_region_labels[id] as Label).visible = true
	_refresh_dimming()
	if id == _hover_id:
		_refresh_hover_text(id)
	_play_sfx("undo")
	_refresh_progress()

## 完成演出：描金依次扫过 → 轻微后拉 → 泛金（总长 ≈1.4s）
func _finish_level1() -> void:
	_l1_done = true
	_dragging = false
	_play_sfx("level_clear")
	_say("你瞧，五色都回到锦上了。", 3.0, 3)
	await get_tree().create_timer(0.2, false).timeout
	var i := 0
	for id in _region_order:
		var line: Line2D = _region_outlines[id]
		get_tree().create_timer(0.02 * i, false).timeout.connect(func() -> void:
			line.default_color = GOLD
			line.width = 2.8
		)
		i += 1
	await get_tree().create_timer(0.02 * _region_order.size() + 0.2, false).timeout
	var flash := ColorRect.new()
	flash.color = Color(GOLD, 0.0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_l1_root.add_child(flash)
	var tween := create_tween()
	tween.tween_property(flash, "color:a", 0.22, 0.18)
	tween.tween_property(flash, "color:a", 0.0, 0.3)
	await get_tree().create_timer(0.45, false).timeout
	_show_stage_clear()

func _enter_level2() -> void:
	_close_modal()
	_action_button.visible = false
	_place_guide(2)
	_speech.call("clear")
	_l1_root.visible = false
	_l2_root.visible = true
	_level = 2
	_start_level2()
	_reveal(_l2_root)

# ---------- 第二关 · 下料 · 看火 · 搅缸 · 观色 ----------

func _setup_level2(l2: Dictionary) -> void:
	_l2_root = Control.new()
	_l2_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_l2_root)
	_order = l2.get("order", [])
	_stir_window = float(l2.get("stir_window_secs", 4.0))
	_stir_needed = float(l2.get("stir_turns_needed", 2.0))
	for m in l2.get("materials", []):
		_material_of_color[m["color"]] = m["material"]
		_material_name_of_color[m["color"]] = m.get("material_name", "")
		_hex_of_color[m["color"]] = Color(m.get("hex", "#EDE3CB"))

	_progress = _outline(_label(_l2_root, "", Vector2(816, 166), Vector2(368, 34), 26, PAPER, true), 3)
	for j in _order.size():
		var swatch := _panel(_l2_root, Vector2(902 + j * 40, 212), Vector2(16, 16), Color(PAPER, 0.18), 8)
		_swatch_nodes.append(swatch)

	_vat_root = Control.new()
	_vat_root.position = Vector2(816, 282)
	_vat_root.size = VAT_SIZE
	_vat_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_l2_root.add_child(_vat_root)
	var vat := TextureRect.new()
	vat.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vat.texture = _tex(_assets_dir + "vat_dye.png")
	vat.set_anchors_preset(Control.PRESET_FULL_RECT)
	vat.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	vat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vat_root.add_child(vat)
	if vat.texture == null:
		var vat_block := Panel.new()
		vat_block.set_anchors_preset(Control.PRESET_FULL_RECT)
		vat_block.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var vat_style := _style(Color("#544F46"), 120)
		vat_style.set_border_width_all(6)
		vat_style.border_color = Color("#2E2A25")
		vat_block.add_theme_stylebox_override("panel", vat_style)
		_vat_root.add_child(vat_block)

	# 缸水按「贴图实际绘制区域」定位（透明底素材裁切后宽高比不一，不能用固定比例）
	var drawn_size := VAT_SIZE
	var drawn_off := Vector2.ZERO
	if vat.texture != null:
		var ts := vat.texture.get_size()
		var fit := minf(VAT_SIZE.x / ts.x, VAT_SIZE.y / ts.y)
		drawn_size = ts * fit
		drawn_off = (VAT_SIZE - drawn_size) * 0.5
	_water = ColorRect.new()
	_water.position = drawn_off + Vector2(drawn_size.x * 0.137, drawn_size.y * 0.084)
	_water.size = Vector2(drawn_size.x * 0.726, drawn_size.y * 0.194)
	_water.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_water_material = ShaderMaterial.new()
	_water_material.shader = preload("res://scenes/puzzles/DyeWater.gdshader")
	_water.material = _water_material
	_vat_root.add_child(_water)
	_stir_guide = Control.new()
	_stir_guide.set_script(preload("res://scenes/puzzles/DyeStirGuide.gd"))
	_stir_guide.position = _water.position - Vector2(9, 8)
	_stir_guide.size = _water.size + Vector2(18, 16)
	_stir_guide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stir_guide.visible = false
	_vat_root.add_child(_stir_guide)

	_stir_sprite = TextureRect.new()
	_stir_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_stir_sprite.texture = _tex(_assets_dir + "tool_stir.png")
	_stir_sprite.size = Vector2(26, 126)
	_stir_sprite.pivot_offset = Vector2(13, 119)
	_stir_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_stir_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stir_sprite.visible = false
	_vat_root.add_child(_stir_sprite)

	_fire = TextureRect.new()
	_fire.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fire.texture = _tex(_assets_dir + "fire_hearth.png")
	_fire.position = Vector2(1040, 523)
	_fire.size = Vector2(110, 86)
	_fire.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_fire.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fire.visible = false
	_l2_root.add_child(_fire)

	_stir_bar = ProgressBar.new()
	_stir_bar.max_value = _stir_window
	_stir_bar.value = _stir_window
	_stir_bar.show_percentage = false
	_stir_bar.add_theme_font_size_override("font_size", 1)
	_stir_bar.position = Vector2(810, 636)
	_stir_bar.size = Vector2(378, 6)
	_stir_bar.add_theme_stylebox_override("background", _style(Color(PAPER, 0.18), 6))
	_stir_bar.add_theme_stylebox_override("fill", _style(GOLD, 6))
	_stir_bar.visible = false
	_l2_root.add_child(_stir_bar)
	_stir_status = _outline(_label(_l2_root, "", Vector2(808, 653), Vector2(382, 28), 18, PAPER, true), 3)

	_lot_root = Control.new()
	_lot_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lot_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_l2_root.add_child(_lot_root)
	var i := 0
	for color_name in _order:
		var material: String = _material_of_color.get(color_name, "")
		var card := _make_lot_card(material, color_name, _hex_of_color.get(color_name, Color("#8A8375")))
		card.position = Vector2(44 + i * 140, 508)
		card.set_meta("home", card.position)
		_lot_root.add_child(card)
		_lot_cards[material] = card
		i += 1

func _make_lot_card(material: String, color_name: String, hex: Color) -> Control:
	var card := Control.new()
	card.size = LOT_CARD
	card.pivot_offset = LOT_CARD * 0.5
	card.set_meta("home", Vector2.ZERO)
	card.set_meta("material", material)
	card.set_meta("color_name", color_name)
	var paper := Panel.new()
	paper.set_anchors_preset(Control.PRESET_FULL_RECT)
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper.add_theme_stylebox_override("panel", _style(Color(PAPER, 0.90), 12))
	card.add_child(paper)
	var content := TextureRect.new()
	content.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	content.texture = _tex(_assets_dir + material + ".png")
	content.position = Vector2(LOT_CARD.x * 0.12, LOT_CARD.y * 0.06)
	content.size = Vector2(LOT_CARD.x * 0.76, LOT_CARD.y * 0.68)
	content.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(content)
	if content.texture == null:
		var block := Panel.new()
		block.position = content.position
		block.size = content.size
		block.mouse_filter = Control.MOUSE_FILTER_IGNORE
		block.add_theme_stylebox_override("panel", _style(hex, 10))
		card.add_child(block)
	_label(card, _material_name_of_color.get(color_name, ""), Vector2(0, LOT_CARD.y * 0.76), Vector2(LOT_CARD.x, 34), 20, INK, true)
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.gui_input.connect(_on_lot_input.bind(card))
	card.mouse_entered.connect(func():
		if _phase == "idle" and _drag_card == null:
			create_tween().tween_property(card, "scale", Vector2(1.025, 1.025), 0.15)
			_lot_hover_card = card
			_lot_hover_elapsed = 0.0
			_lot_hover_pending = true
	)
	card.mouse_exited.connect(func():
		if _drag_card != card:
			create_tween().tween_property(card, "scale", Vector2.ONE, 0.15)
		if _lot_hover_card == card:
			_lot_hover_card = null
			_lot_hover_elapsed = 0.0
			_lot_hover_pending = true
	)
	return card

func _process_lot_hover(delta: float) -> void:
	if not _lot_hover_pending:
		return
	if _phase != "idle" or _drag_card != null or _finished:
		_lot_hover_pending = false
		_lot_hover_card = null
		return
	_lot_hover_elapsed += delta
	if _lot_hover_elapsed <= 1.0:
		return
	_lot_hover_pending = false
	if is_instance_valid(_lot_hover_card):
		var color_name: String = _lot_hover_card.get_meta("color_name")
		_say("蜃灰用于练白。" if color_name == "白" else "%s染%s色。" % [_material_name_of_color[color_name], color_name], 3.0, 1)
	else:
		# 移出也等待一秒，避免连续扫过卡片时反复恢复下料口诀。
		_prompt_material()

func _start_level2() -> void:
	_step = 0
	_phase = "idle"
	_l2_wrong = 0
	_l2_all_done = false
	_stir_acc = 0.0
	_prev_angle = NAN
	_set_water_color(MURKY)
	_update_progress()
	_prompt_material()

func _update_progress() -> void:
	_progress.text = "成色   %d / %d" % [_step, _order.size()]

func _prompt_material() -> void:
	if _step >= _order.size():
		return
	var color: String = _order[_step]
	_say("接着练白，取蜃灰入缸。" if color == "白" else "%s%s，取%s入缸。" % ["先染" if _step == 0 else "接着染", color, _material_name_of_color[color]], 5.0, 1)

func _chant_hint(current_step: int) -> void:
	var color: String = _order[current_step]
	_say("别急，这一步该取蜃灰，先练白。" if color == "白" else "别急，这一味该取%s，染%s色。" % [_material_name_of_color[color], color], 4.0, 3)

func _on_lot_input(event: InputEvent, card: Control) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _phase != "idle":
				return
			_drag_card = card
			var home: Vector2 = card.get_meta("home")
			if home == Vector2.ZERO:
				home = card.position
				card.set_meta("home", home)
			_drag_offset = _lot_root.get_global_transform().affine_inverse() * _mouse_position - home
			_lot_root.move_child(card, -1)
			card.scale = Vector2(1.05, 1.05)
			card.rotation = -0.035
		else:
			if _drag_card == card:
				_drag_card = null
				_drop_material(card)


func _drop_material(card: Control) -> void:
	var drop_pos := _mouse_position
	card.position = card.get_meta("home")
	card.scale = Vector2.ONE
	card.rotation = 0.0
	var vat_rect := Rect2(_vat_root.global_position, _vat_root.size)
	if vat_rect.has_point(drop_pos):
		_commit_material(card.get_meta("material"))

func _commit_material(material: String) -> void:
	if _phase != "idle":
		return
	var expected: String = _order[_step]
	if material == _material_of_color.get(expected, ""):
		_phase = "fire"
		_stir_status.text = ""
		var card: Control = _lot_cards[material]
		create_tween().tween_property(card, "modulate:a", 0.45, 0.3)
		_play_sfx("match_ok")
		_speech.call("clear")
		_say("对，就是%s。等火候到了再搅。" % _material_name_of_color[expected], 2.0, 3)
		_tint_water(_hex_of_color[expected], 0.75, 0.35)
		await _fire_beat()
		_start_stir()
	else:
		_phase = "wrong"
		_l2_wrong += 1
		_play_sfx("match_bad")
		_speech.call("clear")
		_say("这一味先取%s，再来下料。" % _material_name_of_color[expected], 4.0, 3)
		_shake(_vat_root)
		await _murky_flash()
		_phase = "idle"
		if _l2_wrong >= 3:
			_l2_wrong = 0
			_chant_hint(_step)

func _fire_beat() -> void:
	_play_sfx("fire")
	if _fire != null:
		_fire.visible = true
		var tween := create_tween()
		tween.tween_property(_fire, "modulate", Color(1.35, 1.18, 0.92, 1.0), 0.28)
		tween.tween_property(_fire, "modulate", Color(1.0, 1.0, 1.0, 0.6), 0.85)
	await get_tree().create_timer(float(config["level2"].get("fire_secs", 1.2)), false).timeout

func _start_stir() -> void:
	_phase = "stir"
	_begin_stir_round()
	_action_button.visible = false
	_speech.call("clear")
	_say("按住水面绕 %.0f 圈，%.0f 秒内搅匀。" % [_stir_needed, _stir_window], 5.0, 3)

func _begin_stir_round() -> void:
	_stir_acc = 0.0
	_stir_impulse = 0.0
	_stir_tip_given = false
	_stir_left = _stir_window
	_prev_angle = NAN
	_stir_bar.max_value = _stir_window
	_stir_bar.value = _stir_window
	_stir_bar.visible = true
	_stir_sprite.visible = true
	_stir_guide.visible = true
	_stir_guide.set("progress", 0.0)
	_water_material.set_shader_parameter("clarity", 0.0)

func _finish_stir() -> void:
	_phase = "color"
	_stir_bar.visible = false
	_stir_sprite.visible = false
	_stir_guide.visible = false
	_fire.visible = false
	_water_material.set_shader_parameter("clarity", 1.0)
	var expected: String = _order[_step]
	_play_sfx("match_ok")
	_tint_water(_hex_of_color[expected], 1.0, 0.35)
	_stir_status.text = ""
	_speech.call("clear")
	_say("练白这一步成了。" if expected == "白" else "%s色匀开了！这一味成了。" % expected, 2.0, 3)
	_swatch_nodes[_step].add_theme_stylebox_override("panel", _style(_hex_of_color[expected], 4))
	_reveal(_swatch_nodes[_step])
	_step += 1
	_update_progress()
	if _step >= _order.size():
		_l2_all_done = true
		await get_tree().create_timer(0.6, false).timeout
		_complete()
		return
	await get_tree().create_timer(0.6, false).timeout
	_phase = "idle"
	_prev_angle = NAN
	_stir_status.text = ""
	_speech.call("clear")
	_prompt_material()

func _stir_timeout() -> void:
	_phase = "retry"
	_prev_angle = NAN
	_stir_bar.visible = false
	_stir_sprite.visible = false
	_stir_guide.visible = false
	_fire.visible = false
	_stir_status.text = ""
	_play_sfx("match_bad")
	_speech.call("clear")
	_say("还没匀开。按住水面绕圈，再试一次。", 0.0, 3)
	await _murky_flash()
	_show_action("重新搅匀", _start_stir)

func _set_water_color(color: Color) -> void:
	_water_color = color
	_water_material.set_shader_parameter("dye_color", color)

func _murky_flash() -> void:
	_tint_water(MURKY.darkened(0.2), 1.0, 0.18)
	await get_tree().create_timer(0.5, false).timeout

func _tint_water(color: Color, strength: float, secs: float) -> void:
	if _water_tween and _water_tween.is_running():
		_water_tween.kill()
	_water_tween = create_tween()
	_water_tween.tween_method(_set_water_color, _water_color, MURKY.lerp(color, strength), secs)

# Local screens keep the other puzzles' base UI and routing untouched.
func _build_intro() -> void:
	_place_guide(1)
	_intro_layer = CanvasLayer.new()
	_intro_layer.layer = 50
	var box := _dye_summary_box(_intro_layer)
	_centered_line(box, "香格里拉 · 五色配置", 36, GOLD)
	_centered_line(box, "尚未开始", 28, PAPER)
	_centered_line(box, "先补锦纹，再跟丹增染一缸。", 28, PAPER)
	_centered_line(box, "选一色，补一瓣，先把这张旧纹样补好。", 26, PAPER)
	_centered_line(box, "点击下方按钮后，才能选色与填色。", 24, UiKit.MUTED)
	_start_button = UiKit.button("开始补锦", _on_intro_start, true)
	_start_button.custom_minimum_size = Vector2(440, 84)
	_start_button.add_theme_font_size_override("font_size", 32)
	box.add_child(_start_button)
	box.add_child(UiKit.button("暂不开始 · 返回染坊", _exit))
	_start_button.grab_focus()

func _on_intro_start() -> void:
	if _started or _exiting:
		return
	_started = true
	puzzle_started.emit(station_id)
	_on_start()

func _show_stage_clear() -> void:
	_speech.call("clear")
	_say("锦纹补好了！来跟我染一缸。", 0.0, 3)
	_show_action("去染一缸", _enter_level2)

func _show_win_placeholder(fragment_ids: Array) -> void:
	if _gs == get_node_or_null("/root/GameState") and SceneRouter.params.get("defer_reward", false):
		# 保持结算直到玩家确认；手记和碎片依然留到地图收尾之后。
		_speech.call("clear")
		_win_layer = CanvasLayer.new()
		_win_layer.layer = 60
		var box := _dye_summary_box(_win_layer)
		_centered_line(box, "五色成一匹", 36, GOLD)
		_centered_line(box, "补锦纹 · %d / %d\n染一缸 · %d / %d 色" % [_filled.size(), _region_order.size(), _step, _order.size()], 30, PAPER)
		_centered_line(box, "锦纹补好了，五色也都成了。", 28, PAPER)
		_centered_line(box, "确认后回到染坊，听丹增把话说完。", 26, UiKit.MUTED)
		_settlement_continue = UiKit.button("确认完成 · 返回染坊", func():
			if _exiting:
				return
			_exiting = true
			_settlement_continue.disabled = true
			puzzle_completed.emit(station_id, fragment_ids)
			_back_to_map()
		, true)
		_settlement_continue.custom_minimum_size = Vector2(440, 80)
		box.add_child(_settlement_continue)
		return
	_speech.call("clear")
	_say("五色成了！这两页手记，留给你慢慢看。", 4.0, 3)
	_show_knowledge(fragment_ids)
	_win_layer = _modal_layer

func _dye_summary_box(layer: CanvasLayer) -> VBoxContainer:
	add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.09, 0.08, 0.82)
	layer.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	dim.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var card := UiKit.panel()
	card.custom_minimum_size.x = 740
	center.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	card.add_child(box)
	return box

func _centered_line(box: VBoxContainer, text: String, font_size: int, color: Color) -> void:
	var label := UiKit.label(text, font_size, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)

func _setup_activity_card() -> void:
	var card := _panel(self, Vector2(20, 16), Vector2(648, 78), Color(INK, 0.94), 12)
	_activity_title = _label(card, "", Vector2(24, 8), Vector2(600, 34), 26, PAPER)
	_activity_text = _label(card, "", Vector2(24, 44), Vector2(600, 26), 18, GOLD.lightened(0.2))
	_refresh_activity_card()

func _refresh_activity_card() -> void:
	if not is_instance_valid(_activity_title):
		return
	var title := "香格里拉 · 五色配置"
	var status := "准备开坊 · 跟丹增学染色"
	if _level == 1:
		title = "第一关 · 补锦纹"
		status = "锦纹已补好 · 准备染一缸" if _l1_done else "补锦 · 让褪色纹样重新有颜色"
	elif _level == 2:
		title = "第二关 · 染一缸"
		var phases := {
			"idle": "下料 · 第 %d 味" % mini(_step + 1, _order.size()),
			"wrong": "下料 · 重新取料",
			"fire": "看火 · 等染料温开",
			"stir": "搅缸 · 把颜色搅匀",
			"retry": "搅缸 · 等待重试",
			"color": "观色 · 查看成色",
			"done": "五色完成 · 手艺留存"
		}
		status = phases.get(_phase, "染一缸")
	if _activity_title.text != title:
		_activity_title.text = title
	if _activity_text.text != status:
		_activity_text.text = status

func _setup_guide() -> void:
	_npc = TextureRect.new()
	_npc.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_npc.texture = _tex(_assets_dir + "npc_danzeng.png")
	_npc.size = Vector2(240, 240)
	_npc.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_npc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_npc)
	_speech = Control.new()
	_speech.size = Vector2(416, 112)
	_speech.set_script(preload("res://scenes/puzzles/DyeSpeechBubble.gd"))
	_speech.set("speaker", "丹增")
	add_child(_speech)
	_action_button = _make_action("", func():
		_action_button.visible = false
		if _action.is_valid():
			_action.call()
	)
	_action_button.size = Vector2(360, 64)
	_action_button.visible = false
	add_child(_action_button)

func _place_guide(level: int) -> void:
	_npc.position = Vector2(824, 256) if level == 1 else Vector2(72, 240)
	_speech.position = Vector2(716, 136) if level == 1 else Vector2(314, 232)
	_speech.set("tail_left", level == 2)
	_speech.queue_redraw()
	_action_button.position = Vector2(760, 646) if level == 1 else Vector2(342, 365)

func _say(text: String, hold: float = 4.0, priority: int = 1) -> void:
	if is_instance_valid(_speech):
		_speech.call("say", text, hold, priority)

func _show_action(text: String, action: Callable) -> void:
	_action = action
	_action_button.text = text
	_action_button.visible = true

func _make_action(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 28)
	button.add_theme_color_override("font_color", PAPER)
	button.add_theme_color_override("font_hover_color", PAPER)
	button.add_theme_color_override("font_pressed_color", PAPER)
	button.add_theme_stylebox_override("normal", _style(INK, 10))
	button.add_theme_stylebox_override("hover", _style(Color("34574b"), 10))
	button.add_theme_stylebox_override("pressed", _style(Color("152e27"), 10))
	var focus := _style(Color(INK, 0.0), 10)
	focus.set_border_width_all(2)
	focus.border_color = GOLD
	button.add_theme_stylebox_override("focus", focus)
	button.pressed.connect(action)
	return button

func _show_knowledge(fragment_ids: Array) -> void:
	_close_modal()
	_modal_layer = CanvasLayer.new()
	_modal_layer.layer = 60
	add_child(_modal_layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal_layer.add_child(root)
	var fragment_id: String = config.get("fragment_id", "frag_dye_five") if fragment_ids.is_empty() else fragment_ids[0]
	var knowledge = load("res://ui/DyeKnowledge.gd").new()
	_knowledge_continue = knowledge.prepare(root, fragment_id, func():
		_knowledge_continue.disabled = true
		puzzle_completed.emit(station_id, fragment_ids)
		_back_to_map()
	)

func _close_modal() -> void:
	if is_instance_valid(_modal_layer):
		_modal_layer.queue_free()
	_modal_layer = null

# ---------- ShotRunner 调试钩子 ----------

func _debug_fill_first(count: int) -> void:
	var i := 0
	for id in _region_order:
		if i >= count:
			break
		var saved := _selected_no
		_selected_no = _region_no[id]
		_apply_fill(id)
		_selected_no = saved
		i += 1
	_refresh_dimming()

func _debug_fill_all() -> void:
	_debug_fill_first(_region_order.size())

func _debug_commit(color_name: String) -> void:
	_commit_material(_material_of_color.get(color_name, ""))

func _debug_force_stir() -> void:
	_stir_acc = _stir_needed * TAU
