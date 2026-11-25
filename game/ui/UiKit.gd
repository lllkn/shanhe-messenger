class_name UiKit
extends RefCounted
## 生图素材由AtlasTexture取样，文字保持实时控件；原图alpha不作像素修改。
const INK := Color("1e3a34")
const DEEP := Color("122a27")
const PAPER := Color("ede3cb")
const GOLD := Color("c9a24b")
const MUTED := Color("c1c7ad")
const ART := "res://assets/ui/shanhe_v2/"

static func style(bg: Color, border: Color = GOLD, margin: float = 22.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(4)
	s.set_content_margin_all(margin)
	return s

static func atlas_surface(kind: String) -> AtlasTexture:
	var source := load(ART + "surfaces_atlas.png") as Texture2D
	var areas := {
		"paper": Rect2(12, 156, 610, 587),
		"silk": Rect2(639, 157, 600, 580),
		"wood": Rect2(17, 904, 612, 164),
		"gold": Rect2(628, 897, 612, 171),
	}
	var area: Rect2 = areas.get(kind, areas["silk"])
	var factor := float(source.get_width()) / 1254.0
	var texture := AtlasTexture.new()
	texture.atlas = source
	texture.region = Rect2(area.position * factor, area.size * factor)
	texture.filter_clip = true
	return texture

static func surface(kind: String, margin: float = 64.0, tint: Color = Color.WHITE) -> StyleBox:
	# 公开源码不分发原图；缺图时使用原生样式。
	if not ResourceLoader.exists(ART + "surfaces_atlas.png"):
		var color := PAPER if kind in ["paper", "gold"] else DEEP
		return style(color * tint, GOLD, margin)
	var s := StyleBoxTexture.new()
	var sample := atlas_surface(kind)
	s.texture = sample.atlas
	s.region_rect = sample.region
	s.modulate_color = tint
	var panel := kind == "paper" or kind == "silk"
	var border := 90.0 if panel else 0.0
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		s.set_texture_margin(side, border)
		s.set_content_margin(side, margin if panel or side == SIDE_LEFT or side == SIDE_RIGHT else 10.0)
	return s

static func label(text: String, size: int = 28, color: Color = PAPER) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0.02, 0.05, 0.04, 0.22) if color != INK else Color(1, 0.94, 0.76, 0.35))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

static func button(text: String, action: Callable, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(120, 58)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", 28)
	b.add_theme_stylebox_override("normal", surface("gold" if primary else "wood", 14))
	b.add_theme_stylebox_override("hover", surface("gold", 14, Color(1.08, 1.04, 0.94)))
	b.add_theme_stylebox_override("pressed", surface("gold", 14, Color(0.82, 0.83, 0.72)))
	b.add_theme_stylebox_override("focus", surface("gold", 14))
	b.add_theme_stylebox_override("disabled", surface("wood", 14, Color(0.6, 0.63, 0.59)))
	b.add_theme_color_override("font_color", INK if primary else PAPER)
	b.add_theme_color_override("font_focus_color", INK)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_pressed_color", INK)
	b.add_theme_color_override("font_disabled_color", Color("a8ae99"))
	b.pressed.connect(action)
	return b

static func panel(paper: bool = false) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", surface("paper" if paper else "silk"))
	return p

static func slider(minimum: float, maximum: float, step: float, value: float) -> HSlider:
	var control := HSlider.new()
	control.min_value = minimum
	control.max_value = maximum
	control.step = step
	control.value = value
	control.custom_minimum_size.y = 28
	control.add_theme_stylebox_override("slider", style(DEEP, GOLD.darkened(0.25), 4))
	control.add_theme_stylebox_override("grabber_area", style(GOLD, GOLD, 4))
	control.add_theme_stylebox_override("grabber_area_highlight", style(GOLD.lightened(0.2), GOLD, 4))
	for icon in ["grabber", "grabber_highlight", "grabber_disabled"]:
		if ResourceLoader.exists(ART + "slider_knob.svg"):
			control.add_theme_icon_override(icon, load(ART + "slider_knob.svg"))
	return control

static func image(root: Control, texture_path: String, tint: Color = Color.WHITE) -> TextureRect:
	var art := TextureRect.new()
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.texture = load(texture_path) if ResourceLoader.exists(texture_path) else null
	art.modulate = tint
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(art)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return art

static func background(root: Control, texture_path: String = "") -> void:
	var color := ColorRect.new()
	color.color = DEEP
	root.add_child(color)
	color.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image(root, texture_path if not texture_path.is_empty() and ResourceLoader.exists(texture_path) else ART + "title_landscape.png", Color(0.64, 0.7, 0.65, 1.0))
	var veil := ColorRect.new()
	veil.color = Color(DEEP, 0.78 if texture_path.is_empty() else 0.48)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(veil)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

static func page(root: Control, title: String, subtitle: String, back: Callable = Callable()) -> VBoxContainer:
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background(root)
	var margin := MarginContainer.new()
	root.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 32)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	margin.add_child(col)
	var row := HBoxContainer.new()
	col.add_child(row)
	row.add_child(label(title, 40, GOLD.lightened(0.2)))
	if back.is_valid():
		row.add_child(button("返回", back))
	col.add_child(label(subtitle, 26, MUTED))
	return col

static func clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
