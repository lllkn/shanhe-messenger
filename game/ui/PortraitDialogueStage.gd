extends Control
signal photo_ready
## 配置驱动的共用人物与手机舞台；无照片配置时不创建或加载手机。
var config: Dictionary = {}

func stage_config(_id: String) -> Dictionary:
	return {}

var npc: TextureRect
var protagonist: TextureRect
var phone: Control
var screen: TextureRect
var slider: HSlider
var brightness_label: Label
var confirm_button: Button
var zoom_button: Button
var instruction: Label
var settings_panel: PanelContainer
var interaction_required := false
var confirmed := false
var adjusted := false
var zoomed := false
var photo_brightness := 35.0
var _dialogue_id := ""

func prepare(id: String) -> void:
	_dialogue_id = id
	config = stage_config(id)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.07, 0.06, 0.40)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	npc = _image(config.get("portrait", ""), Vector2(50, 106), Vector2(340, 336))
	protagonist = _image("res://assets/puzzles/dali/player_silhouette.png", Vector2(905, 126), Vector2(330, 312))
	protagonist.modulate = Color(0.80, 0.86, 0.83, 0.94)
	if not config.has("photo"): return
	phone = Control.new()
	phone.position = Vector2(440, 108)
	phone.size = Vector2(442, 320)
	phone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(phone)
	# AtlasTexture取样透明正面手机，不修改原始像素。
	var atlas := AtlasTexture.new()
	atlas.atlas = load("res://assets/characters/lijiang/phone-front-v01.png")
	var ratio := float(atlas.atlas.get_width()) / 1024.0
	atlas.region = Rect2(183*ratio, 129*ratio, 652*ratio, 1278*ratio)
	var frame := TextureRect.new()
	frame.texture = atlas
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	frame.size = Vector2(185, 320)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	phone.add_child(frame)
	var clipping := Panel.new()
	clipping.position = Vector2(20, 30)
	clipping.size = Vector2(146, 254)
	clipping.clip_contents = true
	clipping.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clipping.add_theme_stylebox_override("panel", UiKit.style(Color("101918"), Color.TRANSPARENT, 0))
	phone.add_child(clipping)
	screen = TextureRect.new()
	screen.texture = load(config["photo"])
	screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	screen.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	screen.size = clipping.size
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clipping.add_child(screen)
	# 只有丽江首次交给阿东巴的照片需要操作；后续城市只显示清晰照片。
	if not config.get("allow_adjustment", false):
		_refresh_phone()
		phone.hide()
		return
	settings_panel = PanelContainer.new()
	settings_panel.position = Vector2(200, 8)
	settings_panel.size = Vector2(244, 304)
	settings_panel.add_theme_stylebox_override("panel", UiKit.style(Color(0.04, 0.09, 0.08, 0.96), UiKit.GOLD, 12))
	phone.add_child(settings_panel)
	var controls := VBoxContainer.new()
	controls.add_theme_constant_override("separation", 12)
	settings_panel.add_child(controls)
	controls.add_child(UiKit.label(config.get("photo_title", "手机里的古锦照片"), 22, UiKit.PAPER))
	brightness_label = UiKit.label("", 20, UiKit.GOLD)
	controls.add_child(brightness_label)
	slider = UiKit.slider(10, 100, 1, photo_brightness)
	slider.name = "PhoneBrightness"
	slider.tooltip_text = "拖动滑杆，或使用左右方向键调亮屏幕。"
	slider.value_changed.connect(_set_brightness)
	controls.add_child(slider)
	instruction = UiKit.label("", 18, UiKit.PAPER)
	instruction.custom_minimum_size.y = 48
	controls.add_child(instruction)
	zoom_button = UiKit.button(config.get("zoom_text", "放大纹样"), _toggle_zoom)
	zoom_button.add_theme_font_size_override("font_size", 20)
	zoom_button.custom_minimum_size.y = 40
	controls.add_child(zoom_button)
	confirm_button = UiKit.button(config.get("confirm_text", "让对方看照片"), confirm_photo, true)
	confirm_button.add_theme_font_size_override("font_size", 20)
	confirm_button.custom_minimum_size.y = 44
	controls.add_child(confirm_button)
	_refresh_phone()
	phone.hide()

func _image(path: String, at: Vector2, dimensions: Vector2) -> TextureRect:
	var image := TextureRect.new()
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image.position = at
	image.size = dimensions
	if not path.is_empty() and ResourceLoader.exists(path): image.texture = load(path)
	image.visible = image.texture != null
	add_child(image)
	return image

func show_line(index: int, speaker: String) -> void:
	npc.modulate = Color.WHITE if speaker not in ["主角", "旁白"] else Color(0.72, 0.76, 0.74)
	protagonist.modulate.a = 1.0 if speaker == "主角" else 0.78
	var portraits: Dictionary = config.get("speaker_portraits", {})
	var path: String = portraits.get(speaker, config.get("portrait", ""))
	if not path.is_empty(): npc.texture = load(path)
	if phone == null: return
	var span: Array = config.get("phone_lines", [])
	phone.visible = span.size() == 2 and index >= span[0] and index <= span[1]
	interaction_required = config.get("allow_adjustment", false) and index == int(config.get("required_line", -1))
	_refresh_phone()

func blocks_continue() -> bool:
	return interaction_required and not confirmed

func _set_brightness(value: float) -> void:
	if not config.get("allow_adjustment", false) or confirmed: return
	photo_brightness = value
	adjusted = true
	_refresh_phone()

func _refresh_phone() -> void:
	if screen == null: return
	var adjusting: bool = config.get("allow_adjustment", false) and not confirmed
	var light := lerpf(0.12, 1.0, photo_brightness/100.0) if adjusting else 1.0
	screen.modulate = Color(light, light, light)
	# 展示模式保留整张原图，收起整个调整栏并让手机居中。
	var enlarged := adjusting and zoomed
	screen.scale = Vector2(2.5, 2.5) if enlarged else Vector2.ONE
	screen.position = -screen.size*0.75 if enlarged else Vector2.ZERO
	phone.position.x = 440 if adjusting else 547.5
	phone.size.x = 442 if adjusting else 185
	if settings_panel == null: return
	if not adjusting:
		var focused := get_viewport().gui_get_focus_owner()
		if focused != null and settings_panel.is_ancestor_of(focused): focused.release_focus()
	settings_panel.visible = adjusting
	brightness_label.text = "屏幕亮度 · %d%%" % int(photo_brightness)
	confirm_button.visible = interaction_required and adjusting
	confirm_button.disabled = not _can_confirm_photo()
	instruction.text = "照片已确认，可以继续。" if confirmed else (config.get("instruction", "调亮到70%以上，再递给对方。") if interaction_required else "可以调亮屏幕，放大查看。")

func _toggle_zoom() -> void:
	if not config.get("allow_adjustment", false) or confirmed: return
	zoomed = not zoomed
	zoom_button.text = "查看整张" if zoomed else config.get("zoom_text", "放大纹样")
	_refresh_phone()

func _can_confirm_photo() -> bool:
	return interaction_required and not confirmed and phone.is_visible_in_tree() and adjusted and photo_brightness >= 70 and (not config.get("require_zoom", false) or zoomed)

func confirm_photo() -> void:
	if not _can_confirm_photo(): return
	confirmed = true
	_refresh_phone()
	photo_ready.emit()

func continue_hint() -> String:
	return config.get("continue_hint", "请先调亮手机，并点击「让对方看照片」")
