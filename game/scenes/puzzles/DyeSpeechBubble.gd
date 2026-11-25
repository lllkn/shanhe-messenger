extends Control
## One short utterance at a time; phase instructions outrank hover chatter.
var speaker := "丹僧"
var tail_left := false
var _text: Label
var _hold := 0.0
var _persistent := false
var _priority := -1
var _last_text := ""
var _fade: Tween

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_label := Label.new()
	name_label.text = speaker
	name_label.position = Vector2(22, 12)
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", Color("8b7146"))
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(name_label)
	_text = Label.new()
	_text.position = Vector2(22, 37)
	_text.size = size - Vector2(44, 45)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.add_theme_font_size_override("font_size", 21)
	_text.add_theme_color_override("font_color", Color("1e3a34"))
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_text)
	visible = false

func say(text: String, hold: float = 4.0, priority: int = 1) -> void:
	if visible and priority < _priority and (_persistent or _hold > 0.0):
		return
	if visible and _last_text == text:
		return
	if _fade and _fade.is_running():
		_fade.kill()
	_last_text = text
	_text.text = text
	var font := _text.get_theme_font("font")
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 21).x
	var lines := maxi(1, ceili(width / (size.x - 44.0)))
	size.y = 78.0 + 28.0 * (lines - 1)
	_text.size.y = size.y - 45.0
	_hold = hold
	_persistent = hold <= 0.0
	_priority = priority
	var was_visible := visible
	visible = true
	if not was_visible:
		modulate.a = 0.0
		_fade = create_tween()
		_fade.tween_property(self, "modulate:a", 1.0, 0.18)
	else:
		modulate.a = 1.0
	queue_redraw()

func clear() -> void:
	if _fade and _fade.is_running():
		_fade.kill()
	visible = false
	_priority = -1
	_last_text = ""

func _process(delta: float) -> void:
	if not visible or _persistent or _hold <= 0.0:
		return
	_hold = maxf(0.0, _hold - delta)
	if _hold <= 0.0:
		_fade = create_tween()
		_fade.tween_property(self, "modulate:a", 0.0, 0.25)
		_fade.tween_callback(clear)

func _draw() -> void:
	var paper := Color("f1e8d3")
	var shape := StyleBoxFlat.new()
	shape.bg_color = paper
	shape.set_corner_radius_all(18)
	shape.set_border_width_all(1)
	shape.border_color = Color("baa47b")
	shape.shadow_color = Color(0.04, 0.08, 0.05, 0.18)
	shape.shadow_size = 8
	draw_style_box(shape, Rect2(Vector2.ZERO, size))
	var tail := PackedVector2Array()
	if tail_left:
		tail = PackedVector2Array([Vector2(1, 58), Vector2(-25, 88), Vector2(1, 83)])
	else:
		tail = PackedVector2Array([Vector2(192, size.y - 1), Vector2(222, size.y + 29), Vector2(222, size.y - 1)])
	draw_colored_polygon(tail, paper)
