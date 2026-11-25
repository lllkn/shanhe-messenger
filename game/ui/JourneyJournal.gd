extends RefCounted
## 四城收尾与信物重读共用手记；只展示内容，不修改旅程进度。
const JOURNALS := "res://data/journals.json"

static func entry(fragment_id: String) -> Dictionary:
	var fragment := ContentDB.fragment(fragment_id)
	return ContentDB.read_json(JOURNALS).get(fragment.get("station", ""), {})

func _panel(parent: Control, pos: Vector2, dimensions: Vector2, color: Color) -> Panel:
	var panel := Panel.new()
	panel.position = pos
	panel.size = dimensions
	panel.add_theme_stylebox_override("panel", UiKit.style(color, Color.TRANSPARENT, 12))
	parent.add_child(panel)
	return panel

func _label(parent: Control, text: String, pos: Vector2, dimensions: Vector2, font_size: int, centered := false) -> Label:
	var label := UiKit.label(text, font_size, UiKit.INK)
	label.position = pos
	label.size = dimensions
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if centered: label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(label)
	return label

func prepare(parent: Control, fragment_id: String, on_continue: Callable, replay := false) -> Button:
	var fragment := ContentDB.fragment(fragment_id)
	var journal := entry(fragment_id)
	var dim := ColorRect.new()
	dim.color = Color(0.035, 0.075, 0.06, 0.76)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(dim)
	var spread := _panel(dim, Vector2.ZERO, Vector2(1040, 600), Color("e6d9bc"))
	spread.name = "JournalSpread"
	spread.mouse_filter = Control.MOUSE_FILTER_STOP
	var center_spread := func(): spread.position = (parent.get_viewport_rect().size - spread.size) * 0.5
	center_spread.call()
	parent.resized.connect(center_spread)
	_label(spread, journal.get("title", "旅途手记"), Vector2(40,18), Vector2(960,28), 17, true)
	_label(spread, journal.get("heading", "一段手艺，一枚信物"), Vector2(40,52), Vector2(960,50), 35, true)
	_label(spread, journal.get("quote", ""), Vector2(40,103), Vector2(960,26), 18, true)
	for side in ["left", "right"]:
		var page := _panel(spread, Vector2(32 if side == "left" else 532,140), Vector2(476,340), Color("f5eddc"))
		_label(page, journal.get(side + "_title", ""), Vector2(24,12), Vector2(428,36), 25)
		if side == "left" and fragment.get("station", "") == "xianggelila":
			var cfg: Dictionary = ContentDB.read_json("res://data/puzzles.json")["xianggelila"]["level2"]
			var directions := ["东方","南方","中央","西方","北方"]
			for i in cfg["materials"].size():
				var material: Dictionary = cfg["materials"][i]
				_panel(page, Vector2(25,66+i*39), Vector2(20,20), Color(material["hex"]))
				var material_name: String = "练白" if material["color"] == "白" else material["material_name"]
				_label(page, "%s · %s    %s" % [material["color"],directions[i],material_name], Vector2(62,59+i*39), Vector2(384,34), 21)
		else:
			var lines: Array = journal.get(side + "_lines", [])
			for i in lines.size():
				_label(page, lines[i], Vector2(24,63+i*48), Vector2(428,42), 20)
		_label(page, journal.get(side + "_note", ""), Vector2(24,276), Vector2(428,56), 14)
	_label(spread, ("信物「%s」· 已收录" if replay else "获得「%s」· 已放入行囊") % fragment.get("name", "古道信物"), Vector2(40,487), Vector2(960,26), 18, true)
	_label(spread, fragment.get("meaning", ""), Vector2(40,515), Vector2(960,24), 17, true)
	var button := UiKit.button("合上手记 · 返回信物" if replay else "收好手记 · 继续旅程", on_continue, true)
	button.position = Vector2(340,538)
	button.custom_minimum_size = Vector2(360,44)
	button.size = Vector2(360,44)
	spread.add_child(button)
	button.grab_focus()
	return button

static func fragment_card(fragment_id: String, collected: bool, on_open: Callable) -> PanelContainer:
	var fragment := ContentDB.fragment(fragment_id)
	var journal := entry(fragment_id)
	var card := PanelContainer.new()
	card.name = fragment_id
	card.custom_minimum_size = Vector2(570, 278)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", UiKit.style(Color("e6d9bc") if collected else Color("c8c6b3"), Color("b5a57e"), 24))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	card.add_child(box)
	box.add_child(UiKit.label(journal.get("title", "旅途手记"), 22, UiKit.INK))
	box.add_child(UiKit.label(fragment.get("name", "信物") if collected else "尚未收集", 30, UiKit.INK))
	var page := PanelContainer.new()
	page.add_theme_stylebox_override("panel", UiKit.style(Color("f5eddc"), Color.TRANSPARENT, 14))
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(page)
	page.add_child(UiKit.label(fragment.get("meaning", "") if collected else fragment.get("usage", ""), 22, UiKit.INK))
	if collected:
		box.add_child(UiKit.button("打开手记", on_open))
	else:
		box.add_child(UiKit.label("完成本城故事后，收下这页手记。", 18, UiKit.INK))
	return card
