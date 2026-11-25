extends Control
var journal_layer: CanvasLayer
var opened_from: Button
var clue_layer: CanvasLayer
var content: VBoxContainer
var filter_row: HBoxContainer
var tabs: HBoxContainer
var selected_city := ""
var selected_tab := "clues"

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var page := UiKit.page(self, "行囊 · 旅途收藏", "把沿途听来的故事，一张一张收好。", _back)
	tabs = HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 12)
	page.add_child(tabs)
	filter_row = HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 10)
	page.add_child(filter_row)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 14)
	scroll.add_child(content)
	_render()

func _render() -> void:
	UiKit.clear(tabs)
	UiKit.clear(filter_row)
	UiKit.clear(content)
	for tab in [["clues", "线索卡 · %d / 12" % ClueBook.count()], ["fragments", "信物手记 · %d / %d" % [GameState.get_fragment_count(), GameState.get_total_fragment_count()]]]:
		var key: String = tab[0]
		var button := ClueCard.small_button(tab[1], func(): selected_tab = key; _render(), UiKit.GOLD)
		button.name = "Tab_" + key
		button.button_pressed = selected_tab == key
		if selected_tab == key: button.modulate = Color("ffdfa7")
		tabs.add_child(button)
	filter_row.visible = selected_tab == "clues"
	if selected_tab == "fragments":
		_render_fragments()
		return
	var all := ClueCard.small_button("全部城市", func(): selected_city = ""; _render(), UiKit.GOLD)
	all.name = "Filter_all"
	filter_row.add_child(all)
	for city_id in ClueBook.CITIES:
		var key: String = city_id
		var button := ClueCard.small_button("%s · %d/3" % [ClueBook.CITIES[key], ClueBook.count(key)], func(): selected_city = key; _render(), ClueBook.COLORS[key])
		button.name = "Filter_" + key
		if selected_city == key: button.modulate = Color("ffdfa7")
		filter_row.add_child(button)
	for city_id in ClueBook.CITIES:
		if not selected_city.is_empty() and selected_city != city_id: continue
		content.add_child(UiKit.label("%s / %s     已收录 %d / 3" % [ClueBook.CITIES[city_id], ClueBook.CATEGORIES[city_id], ClueBook.count(city_id)], 24, UiKit.PAPER))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 18)
		grid.add_theme_constant_override("v_separation", 14)
		content.add_child(grid)
		for item in ClueBook.entries(city_id):
			grid.add_child(ClueCard.inventory_card(item, _open_clue.bind(item["station"], item["id"])))

func _render_fragments() -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 20)
	content.add_child(grid)
	for id in ContentDB.read_json("res://data/fragments.json").get("fragments", {}):
		var collected := GameState.has_fragment(id)
		var card := preload("res://ui/JourneyJournal.gd").fragment_card(id, collected, func(): _open_journal(id))
		grid.add_child(card)
	content.add_child(UiKit.label("收集进度 %d / %d" % [GameState.get_fragment_count(), GameState.get_total_fragment_count()], 28, UiKit.GOLD))

func _open_clue(station_id: String, clue_id: String) -> void:
	var item := ClueBook.entry(station_id, clue_id)
	if clue_layer != null or journal_layer != null or not ClueBook.collected(item): return
	opened_from = get_viewport().gui_get_focus_owner() as Button
	clue_layer = CanvasLayer.new()
	clue_layer.layer = 35
	add_child(clue_layer)
	var card := ClueCard.new()
	clue_layer.add_child(card)
	card.prepare(item, func():
		clue_layer.queue_free()
		clue_layer = null
		if is_instance_valid(opened_from): opened_from.grab_focus()
	)

func _open_journal(fragment_id: String) -> void:
	if journal_layer != null or not GameState.has_fragment(fragment_id): return
	opened_from = get_viewport().gui_get_focus_owner() as Button
	journal_layer = CanvasLayer.new()
	journal_layer.layer = 30
	add_child(journal_layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	journal_layer.add_child(root)
	preload("res://ui/JourneyJournal.gd").new().prepare(root, fragment_id, func():
		journal_layer.queue_free()
		journal_layer = null
		if is_instance_valid(opened_from): opened_from.grab_focus()
	, true)

func _back() -> void:
	var key: String = SceneRouter.params.get("return_key", "map")
	var p: Dictionary = SceneRouter.params.get("return_params", {})
	if key == "city":
		JourneyFlow.open_city(p.get("station", GameState.current_station), p)
	else:
		SceneRouter.goto(key if SceneRouter.is_available(key) else "map", p)
