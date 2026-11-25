class_name JourneyCanvas
extends Control
## 艺术长卷上的站点控件；坐标为视觉布局，不代表真实地理方位。
signal station_selected(station_id: String)
var selected_id := ""
var _markers: Array[Button] = []
var _badges: Array[PanelContainer] = []
var _route: Control
var _points: Array[Vector2] = [Vector2(0.14, 0.28), Vector2(0.36, 0.17), Vector2(0.49, 0.49), Vector2(0.79, 0.75), Vector2(0.78, 0.36)]

## 旅程高亮与查看选中独立：重访旧站不会夺走下一站的引导。
static func recommended_station() -> String:
	for st in GameState.stations:
		if GameState.is_unlocked(st["id"]) and not GameState.is_completed(st["id"]):
			return st["id"]
	if GameState.is_unlocked(GameState.current_station):
		return GameState.current_station
	for i in range(GameState.stations.size() - 1, -1, -1):
		var st: Dictionary = GameState.stations[i]
		if GameState.is_unlocked(st["id"]):
			return st["id"]
	return ""

static func station_state(id: String) -> String:
	if not GameState.is_unlocked(id):
		return "locked"
	return "completed" if GameState.is_completed(id) else "active"

static func state_label(id: String) -> String:
	match station_state(id):
		"completed": return "已走过"
		"locked": return "尚未解锁"
	if GameState.current_station == id:
		return "正在进行"
	for key in GameState.flags:
		if str(key).begins_with("flow/" + id + "/") and GameState.has_flag(key):
			return "正在进行"
	return "下一站"

static func unlock_hint(id: String) -> String:
	var index: int = GameState.station_index.get(id, 0)
	if index <= 0:
		return "从丽江开始你的古道旅程。"
	var previous: Dictionary = GameState.stations[index - 1]
	return "完成%s%s后解锁。" % [previous["name"], "并收齐本站信物" if not previous.get("fragments", []).is_empty() else "的故事"]

func _ready() -> void:
	clip_contents = true
	UiKit.image(self, UiKit.ART + "journey_landscape.png")
	_route = Control.new()
	_route.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_route)
	_route.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_route.draw.connect(_draw_route)
	for i in GameState.stations.size():
		var st: Dictionary = GameState.stations[i]
		var sid: String = st["id"]
		var b := UiKit.button(st["name"], func(): station_selected.emit(sid))
		b.add_theme_font_size_override("font_size", 26)
		b.custom_minimum_size = Vector2(160, 58)
		b.size = Vector2(160, 58)
		add_child(b)
		_markers.append(b)
		var badge := PanelContainer.new()
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var text := UiKit.label("", 16)
		text.autowrap_mode = TextServer.AUTOWRAP_OFF
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.add_child(text)
		add_child(badge)
		_badges.append(badge)
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	for i in _markers.size():
		_markers[i].position = size * _points[i % _points.size()] - _markers[i].size * 0.5
		_badges[i].position = _markers[i].position + Vector2((_markers[i].size.x - _badges[i].size.x) * 0.5, _markers[i].size.y + 2)
	_route.queue_redraw()

func select(id: String) -> void:
	selected_id = id
	for i in _markers.size():
		var sid: String = GameState.stations[i]["id"]
		var state := station_state(sid)
		var active := state == "active"
		var locked := state == "locked"
		var kind := "gold" if active else "wood"
		var tint := Color(0.48, 0.53, 0.51) if locked else Color.WHITE
		var font := Color("abb3a7") if locked else (UiKit.INK if active else UiKit.PAPER)
		var b := _markers[i]
		b.set_meta("journey_state", state)
		b.add_theme_stylebox_override("normal", UiKit.surface(kind, 14, tint))
		b.add_theme_stylebox_override("hover", UiKit.surface(kind, 14, tint.lightened(0.12)))
		b.add_theme_stylebox_override("pressed", UiKit.surface(kind, 14, tint.darkened(0.12)))
		var focus := UiKit.style(Color.TRANSPARENT, UiKit.PAPER if locked else UiKit.GOLD.lightened(0.3), 0)
		focus.set_border_width_all(2)
		focus.set_corner_radius_all(16)
		b.add_theme_stylebox_override("focus", focus)
		for key in ["font_color", "font_focus_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(key, font)
		b.tooltip_text = unlock_hint(sid) if locked else ("重回%s，重温沿途故事。" % b.text if state == "completed" else "继续%s的旅程。" % b.text)
		var badge := _badges[i]
		var badge_color := UiKit.GOLD.lightened(0.15) if active else (Color("68766a") if locked else UiKit.DEEP)
		var badge_style := UiKit.style(badge_color, Color.TRANSPARENT, 6)
		badge_style.content_margin_top = 2
		badge_style.content_margin_bottom = 2
		badge.add_theme_stylebox_override("panel", badge_style)
		var text := badge.get_child(0) as Label
		text.text = ("● " if active else "") + state_label(sid)
		text.add_theme_color_override("font_color", UiKit.INK if active else UiKit.PAPER)
		badge.reset_size()
	_layout()

func _draw_route() -> void:
	if _markers.size() < 2:
		return
	for i in _markers.size() - 1:
		var from_point: Vector2 = size * _points[i]
		var to_point: Vector2 = size * _points[i + 1]
		var active := GameState.is_unlocked(GameState.stations[i + 1]["id"])
		_route.draw_dashed_line(from_point, to_point, Color(UiKit.GOLD if active else UiKit.INK, 0.65), 2.0, 7.0, true)
	for i in _markers.size():
		var sid: String = GameState.stations[i]["id"]
		var rect := _markers[i].get_rect().grow(4)
		if station_state(sid) == "active":
			var glow := UiKit.style(Color.TRANSPARENT, Color(UiKit.GOLD.lightened(0.2), 0.65), 0)
			glow.set_corner_radius_all(20)
			glow.shadow_color = Color(UiKit.GOLD, 0.35)
			glow.shadow_size = 8
			_route.draw_style_box(glow, rect)
		if sid == selected_id:
			# 四角表示正在查看，避免把旧站或锁定站也染成金牌。
			var color := UiKit.PAPER if station_state(sid) == "locked" else UiKit.GOLD.lightened(0.35)
			for corner in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
				var direction := Vector2(1 if corner.x == rect.position.x else -1, 1 if corner.y == rect.position.y else -1)
				_route.draw_line(corner, corner + Vector2(10 * direction.x, 0), color, 2, true)
				_route.draw_line(corner, corner + Vector2(0, 10 * direction.y), color, 2, true)
