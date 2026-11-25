extends Control
## 生图山水标题页；控件与素材分离，现有入口和存档接口保持不变。
@export var defer_focus := false
var _menu_root: Control
var _start_button: Button
var _menu_buttons: Array[Button] = []

func _ready() -> void:
	UiKit.image(self, UiKit.ART + "title_landscape.png")
	_menu_root = Control.new()
	_menu_root.name = "Menu"
	_menu_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_menu_root)
	_menu_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var title_block := VBoxContainer.new()
	_menu_root.add_child(title_block)
	title_block.set_anchors_preset(Control.PRESET_TOP_LEFT)
	title_block.position = Vector2(90, 128)
	title_block.size = Vector2(580, 380)
	title_block.add_theme_constant_override("separation", 14)
	var chapter := UiKit.label("茶 马 古 道    ·    影 游 纪 行", 24, UiKit.INK)
	title_block.add_child(chapter)
	var title := UiKit.label("山河信使", 106, UiKit.INK)
	title.add_theme_font_override("font", load("res://assets/shared/fonts/emphasis.tres"))
	title_block.add_child(title)
	title_block.add_child(UiKit.label("循着古道，拾起散落的记忆。\n让每一段故事，在手中重新相连。", 28, UiKit.INK))
	var band := ColorRect.new()
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.color = Color(UiKit.DEEP, 0.78)
	_menu_root.add_child(band)
	band.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	band.offset_top = -154
	var layout := MarginContainer.new()
	_menu_root.add_child(layout)
	layout.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	layout.offset_top = -142
	layout.offset_bottom = -22
	layout.offset_left = 70
	layout.offset_right = -70
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	layout.add_child(box)
	var small := HBoxContainer.new()
	box.add_child(small)
	small.add_child(UiKit.label("丽江  /  香格里拉  /  大理  /  普洱  /  古城", 24, UiKit.PAPER))
	var progress := UiKit.label("行囊信物  %d / %d" % [GameState.get_fragment_count(), GameState.get_total_fragment_count()], 24, UiKit.GOLD.lightened(0.25))
	progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	small.add_child(progress)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	box.add_child(row)
	var go := UiKit.button("继续旅程" if GameState.get_fragment_count() > 0 or not GameState.current_station.is_empty() else "踏上古道", func(): SceneRouter.goto_map(), true)
	_start_button = go
	for b in [go, UiKit.button("信物图鉴", func(): SceneRouter.goto_codex()), UiKit.button("游戏设置", func(): GameUI.open_settings()), UiKit.button("重新启程", func(): GameUI.confirm_new_game())]:
		_menu_buttons.append(b)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 62
		row.add_child(b)
	var hint := UiKit.label("Esc · 旅程菜单   /   收集进度自动保存", 20, UiKit.PAPER)
	_menu_root.add_child(hint)
	hint.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	hint.offset_left = -510
	hint.offset_right = -38
	hint.offset_top = 30
	hint.offset_bottom = 58
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	set_menu_reveal(0.0 if defer_focus else 1.0)
	if not defer_focus:
		focus_start()

## 开场只显露山水，云散后才允许鼠标和键盘操作菜单。
func set_menu_reveal(amount: float) -> void:
	_menu_root.modulate.a = clampf(amount, 0.0, 1.0)
	_menu_root.visible = amount > 0.0
	for button in _menu_buttons:
		button.disabled = amount < 1.0
		button.focus_mode = Control.FOCUS_ALL if amount >= 1.0 else Control.FOCUS_NONE

func focus_start() -> void:
	_start_button.grab_focus()
