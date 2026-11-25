extends Control
## 留白后的片尾；没有拼锦、评级或新奖励。
func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# 与主页面共用山水画，沿用统一遮罩，保证片尾文字清楚可读。
	UiKit.background(self, UiKit.ART + "title_landscape.png")
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(420, 0)
	box.add_theme_constant_override("separation", 24)
	center.add_child(box)
	var title := UiKit.label("山河信使", 56, UiKit.PAPER)
	title.add_theme_font_override("font", load("res://assets/shared/fonts/emphasis.tres"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var end := UiKit.label("终", 26, UiKit.GOLD)
	end.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(end)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 36
	box.add_child(spacer)
	box.add_child(UiKit.button("重温终章", func(): JourneyFlow.open_city("gucheng", {"replay_ending": true})))
	box.add_child(UiKit.button("返回旅途长卷", func(): SceneRouter.goto_map(), true))
	box.add_child(UiKit.button("返回主页面", func(): SceneRouter.goto("home")))
	box.modulate.a = 0.0
	create_tween().tween_property(box, "modulate:a", 1.0, 1.2)
