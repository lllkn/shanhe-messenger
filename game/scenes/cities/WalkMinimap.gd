extends Control
## 由真实路网采样格绘制；目标可点击，仅切换引导目标。
var city: Node3D
var map_rect := Rect2(12, 38, 236, 174)
var floor_texture: ImageTexture

func _ready() -> void:
	custom_minimum_size = Vector2(260, 234)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

func screen_point(p: Vector3) -> Vector2:
	var b: Array = city.story["bounds"]
	return map_rect.position + Vector2((p.x-b[0])/(b[1]-b[0]),(p.z-b[2])/(b[3]-b[2]))*map_rect.size

func prepare_floor() -> void:
	var grid: AStarGrid2D = city.walk_guide.grid
	var image := Image.create(grid.region.size.x, grid.region.size.y, false, Image.FORMAT_RGBA8)
	for x in grid.region.size.x:
		for z in grid.region.size.y:
			image.set_pixel(x, z, Color(0.55, 0.56, 0.43, 0.36) if not grid.is_point_solid(Vector2i(x, z)) else Color.TRANSPARENT)
	floor_texture = ImageTexture.create_from_image(image)
	queue_redraw()

func _draw() -> void:
	if city == null:
		return
	draw_style_box(UiKit.style(Color(0.04, 0.09, 0.08, 0.90), UiKit.GOLD, 12), Rect2(Vector2.ZERO, size))
	var font := get_theme_default_font()
	draw_string(font, Vector2(14, 25), city.story["map_title"], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, UiKit.PAPER)
	if floor_texture != null:
		draw_texture_rect(floor_texture, map_rect, false)
	var river := PackedVector2Array()
	for p in city.story["canal"]:
		river.append(screen_point(Vector3(p[0], 0, p[1])))
	if river.size() > 1: draw_polyline(river, Color(0.21, 0.57, 0.64), 5, true)
	for bridge in city.story["bridges"]:
		var pos: Vector3 = city.bridge_center(bridge)
		draw_circle(screen_point(pos), 4, UiKit.PAPER)
	if city.guide_path.size() > 1:
		var route := PackedVector2Array()
		for p in city.guide_path: route.append(screen_point(p))
		draw_polyline(route, UiKit.GOLD, 2, true)
	for item in city.hotspots:
		var p := screen_point(item["position"])
		var done: bool = city.hotspot_done(item)
		var active: bool = item["id"] == city.target_id
		draw_circle(p, 6 if active else 4, UiKit.MUTED if done else UiKit.GOLD)
		if active: draw_arc(p, 9, 0, TAU, 24, UiKit.PAPER, 1.5, true)
		draw_string(font, p + Vector2(8, 4), item["short"], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiKit.PAPER)
	var player_pos := screen_point(city.player.position)
	draw_circle(player_pos, 4, Color.WHITE)
	var forward := Vector2(-sin(city.yaw), -cos(city.yaw))
	draw_line(player_pos, player_pos + forward * 12, Color.WHITE, 2, true)
	draw_string(font, Vector2(14, 224), "白点：你   金点：待访谈   浅点：已完成", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiKit.MUTED)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		for item in city.hotspots:
			if event.position.distance_to(screen_point(item["position"])) < 18:
				city.select_target(item["id"])
				accept_event()
				return
