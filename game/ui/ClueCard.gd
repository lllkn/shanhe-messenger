class_name ClueCard
extends Control
## 同一张手绘卡用于地图获得、任务重读和行囊。只读，不发奖。
const CARD_SIZE := Vector2(940, 558)
const INVENTORY_WIDTH := 548.0
const PAPER_ART := "res://assets/ui/clues/clue-paper-v01.png"
var close_action: Callable
var close_button: Button
var card: Control
var entry_key := ""

static func paper(parent: Control) -> void:
	var art := TextureRect.new()
	art.texture = load(PAPER_ART)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(art)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

static func portrait(parent: Control, item: Dictionary, pos: Vector2, dimensions: Vector2) -> void:
	var art := TextureRect.new()
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.texture = load(item["portrait"])
	art.position = pos
	art.size = dimensions
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(art)

static func text_at(parent: Control, value: String, pos: Vector2, dimensions: Vector2, font_size: int, color := UiKit.INK) -> Label:
	var label := UiKit.label(value, font_size, color)
	label.position = pos
	label.size = dimensions
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

static func small_button(value: String, action: Callable, accent: Color) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size = Vector2(170, 44)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 19)
	for state in ["font_color", "font_focus_color", "font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(state, UiKit.INK)
	for state in ["normal", "hover", "pressed", "focus"]:
		var style := UiKit.style(Color("e5eacb") if state == "normal" else Color("f5d99b"), accent, 10)
		style.set_corner_radius_all(12)
		style.set_border_width_all(2)
		button.add_theme_stylebox_override(state, style)
	button.pressed.connect(action)
	return button

func prepare(item: Dictionary, on_close: Callable, acquired := false, next_note := "") -> void:
	close_action = on_close
	entry_key = item["key"]
	add_to_group("open_clue_cards")
	name = "ClueCard"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.035, 0.07, 0.06, 0.72)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card = _face(item, true, "新线索 · 已收进行囊" if acquired else "旅途线索 · 重温笔记", next_note if not next_note.is_empty() else "访谈记录已整理，随时可以在行囊中重读。")
	add_child(card)
	close_button = small_button("收好线索 · 继续走访" if acquired else "合上卡片", close, item["color"])
	close_button.position = Vector2(350, 468)
	close_button.size = Vector2(270, 46)
	close_button.name = "CloseClue"
	card.add_child(close_button)
	resized.connect(_layout)
	_layout()
	close_button.grab_focus()

static func _face(item: Dictionary, unlocked: bool, status: String, note: String) -> Control:
	var face := Control.new()
	face.name = "CluePaper"
	face.size = CARD_SIZE
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper(face)
	if unlocked:
		portrait(face, item, Vector2(50, 110), Vector2(246, 310))
	else:
		var unknown := text_at(face, "?", Vector2(50, 210), Vector2(246, 110), 80, Color("9da990"))
		unknown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var person := text_at(face, (item["name"] if unlocked else "待访人物"), Vector2(42, 429), Vector2(263, 35), 24)
	person.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var place := text_at(face, (item["place"] if unlocked else "完成走访后收录"), Vector2(42, 466), Vector2(263, 28), 18, Color("697b6b"))
	place.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text_at(face, status, Vector2(350, 55), Vector2(526, 32), 18, item["color"])
	text_at(face, "%s / %s  ·  访谈 %02d" % [item["city"], item["category"], item["number"]], Vector2(350, 96), Vector2(526, 30), 19, Color("687a69"))
	text_at(face, (item["title"] if unlocked else "尚未收录"), Vector2(350, 148), Vector2(526, 85), 33)
	text_at(face, (item["text"] if unlocked else "完成这处走访后，收下新的笔记。"), Vector2(350, 234), Vector2(508, 151), 24)
	text_at(face, note, Vector2(350, 397), Vector2(508, 55), 17, Color("687a69"))
	return face

func _layout() -> void:
	if card == null: return
	var fit := minf(1.0, minf((size.x - 32) / CARD_SIZE.x, (size.y - 32) / CARD_SIZE.y))
	card.scale = Vector2.ONE * maxf(0.1, fit)
	card.position = (size - card.size * card.scale) * 0.5

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not event.is_echo() and not get_tree().paused:
		get_viewport().set_input_as_handled()
		close()

func close() -> void:
	if not close_action.is_valid(): return
	var action := close_action
	close_action = Callable()
	remove_from_group("open_clue_cards")
	action.call()

static func inventory_card(item: Dictionary, on_open: Callable) -> Button:
	var unlocked := ClueBook.collected(item)
	var button := Button.new()
	button.name = item["key"].replace("/", "_")
	button.custom_minimum_size = Vector2(INVENTORY_WIDTH, INVENTORY_WIDTH * CARD_SIZE.y / CARD_SIZE.x)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.disabled = not unlocked
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if unlocked else Control.CURSOR_ARROW
	for state in ["normal", "disabled", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(state, UiKit.style(Color.TRANSPARENT, item["color"] if state in ["hover", "focus"] else Color.TRANSPARENT, 0))
	var visual := _face(item, unlocked, "旅途线索 · 已收进行囊" if unlocked else "旅途线索 · 等待走访", "访谈记录已整理，点击卡片可重读。" if unlocked else "线索会随着旅程逐步收录。")
	button.add_child(visual)
	var footer := Panel.new()
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.position = Vector2(350, 468)
	footer.size = Vector2(270, 46)
	var footer_style := UiKit.style(Color("e5eacb"), item["color"], 10)
	footer_style.set_corner_radius_all(12)
	footer.add_theme_stylebox_override("panel", footer_style)
	visual.add_child(footer)
	var hint := text_at(footer, "点击重读  →" if unlocked else "等待走访", Vector2.ZERO, footer.size, 19)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# 容器只决定卡片宽度；在同一个设计坐标系中整体缩放，不单独拉伸底图。
	var layout := func():
		var width := maxf(INVENTORY_WIDTH, button.size.x)
		var fit := width / CARD_SIZE.x
		var height := width * CARD_SIZE.y / CARD_SIZE.x
		if not is_equal_approx(button.custom_minimum_size.y, height): button.custom_minimum_size.y = height
		visual.scale = Vector2.ONE * fit
	button.resized.connect(layout)
	layout.call()
	if not unlocked: visual.modulate = Color(0.85, 0.85, 0.81)
	button.pressed.connect(on_open)
	return button
