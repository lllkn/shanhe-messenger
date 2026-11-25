extends Control
## 长卷只展示旅程与解锁进度；走进城市直接进入3D出生点。
var _detail: VBoxContainer
var _canvas: JourneyCanvas
var _selected := ""
var _recommended := ""
var _progress: Label

func _ready() -> void:
	var page := UiKit.page(self, "古道行旅", "循着金色驿站继续前行，也可点选其他驿站查看手记。", func(): SceneRouter.goto("home"))
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 20)
	page.add_child(body)
	var scroll_frame := UiKit.panel(true)
	var scroll_surface := UiKit.surface("paper", 28)
	scroll_surface.content_margin_bottom = 50
	scroll_frame.add_theme_stylebox_override("panel", scroll_surface)
	scroll_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(scroll_frame)
	var scroll_col := VBoxContainer.new()
	scroll_col.add_theme_constant_override("separation", 12)
	scroll_frame.add_child(scroll_col)
	_canvas = JourneyCanvas.new()
	_canvas.custom_minimum_size = Vector2(580, 300)
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_col.add_child(_canvas)
	_canvas.station_selected.connect(_select)
	var legend := HBoxContainer.new()
	legend.alignment = BoxContainer.ALIGNMENT_CENTER
	legend.add_theme_constant_override("separation", 18)
	for item in [["● 下一站 / 进行中", UiKit.GOLD.darkened(0.3)], ["● 已走过", UiKit.INK], ["● 尚未解锁", Color("68766a")]]:
		var label := UiKit.label(item[0], 18, item[1])
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		legend.add_child(label)
	scroll_col.add_child(legend)
	var right := UiKit.panel()
	var detail_surface := UiKit.surface("silk", 64)
	detail_surface.content_margin_bottom = 36
	right.add_theme_stylebox_override("panel", detail_surface)
	right.custom_minimum_size.x = 360
	body.add_child(right)
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 7)
	right.add_child(_detail)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 20)
	page.add_child(footer)
	_progress = UiKit.label("", 21, UiKit.PAPER)
	footer.add_child(_progress)
	footer.add_child(UiKit.button("信物图鉴", func(): SceneRouter.goto_codex()))
	footer.add_child(UiKit.button("旅程菜单", func(): GameUI.open_pause()))
	_recommended = JourneyCanvas.recommended_station()
	_select(_recommended)
	_update_progress()
	GameState.progress_changed.connect(_on_progress_changed)

func _update_progress() -> void:
	_progress.text = "已走过 %d / %d 站  ·  行囊信物 %d / %d" % [GameState.completed.size(), GameState.stations.size(), GameState.get_fragment_count(), GameState.get_total_fragment_count()]

func _on_progress_changed() -> void:
	var next := JourneyCanvas.recommended_station()
	var target := next if next != _recommended else _selected
	_recommended = next
	_select(target)
	_update_progress()

func _select(id: String) -> void:
	if not GameState.station_index.has(id):
		return
	_selected = id
	_canvas.select(id)
	UiKit.clear(_detail)
	var st: Dictionary = GameState.stations[GameState.station_index[id]]
	var meta := ContentDB.station(id)
	var state := JourneyCanvas.station_state(id)
	var active := state == "active"
	var locked := state == "locked"
	_detail.add_child(UiKit.label("第 %s 站 · 古道手记" % ["一", "二", "三", "四", "五"][GameState.station_index[id]], 20, UiKit.GOLD.lightened(0.15)))
	var status := UiKit.label(("● " if active else "") + JourneyCanvas.state_label(id), 20, UiKit.GOLD.lightened(0.3) if active else UiKit.MUTED)
	_detail.add_child(status)
	_detail.add_child(UiKit.label(st["name"], 42, UiKit.PAPER))
	_detail.add_child(UiKit.label(st["theme"], 22, UiKit.GOLD.lightened(0.15)))
	var desc := UiKit.label(meta.get("subtitle", ""), 22, UiKit.PAPER)
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail.add_child(desc)
	var hint := "本站手记已完成，可重回故地。"
	if locked:
		hint = JourneyCanvas.unlock_hint(id)
	elif active:
		hint = "旅程已自动记录，继续本站故事。" if JourneyCanvas.state_label(id) == "正在进行" else "下一段旅程已开启，前往本站。"
	_detail.add_child(UiKit.label(hint, 18, UiKit.MUTED))
	var action: String = "尚未解锁" if locked else (("重回" if state == "completed" else "继续") + st["name"])
	var enter := UiKit.button(action, func(): SceneRouter.goto_station(id), active)
	enter.add_theme_font_size_override("font_size", 25)
	enter.disabled = locked
	_detail.add_child(enter)
