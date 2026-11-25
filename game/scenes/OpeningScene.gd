extends Control
## 启动专用影像。云幕内交换画面，不经路由黑场；不会写入或清空旅程存档。
enum Phase { VIDEO, SUMMARY, COVERING, REVEALING, HOME }
@export var video_stream: VideoStream
var phase := Phase.VIDEO
var _player: VideoStreamPlayer
var _video_stage: Control
var _last_frame: TextureRect
var _skip: Button
var _summary: Control
var _curtain: TextureRect
var _cloud_material: ShaderMaterial
var _home: Control
var _transition: Tween

func _ready() -> void:
	_home = $Home
	_video_stage = ColorRect.new()
	(_video_stage as ColorRect).color = Color.BLACK
	_full_rect(_video_stage)
	var aspect := AspectRatioContainer.new()
	aspect.ratio = 16.0 / 9.0
	_full_rect(aspect, _video_stage)
	_last_frame = TextureRect.new()
	_last_frame.texture = (load("res://assets/cinematics/opening/last_frame.png") if ResourceLoader.exists("res://assets/cinematics/opening/last_frame.png") else null)
	_last_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_last_frame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_last_frame.visible = false
	_full_rect(_last_frame, aspect)
	_player = VideoStreamPlayer.new()
	_player.expand = true
	_player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player.finished.connect(_on_video_finished)
	_full_rect(_player, aspect)
	_skip = UiKit.button("跳过影像 · 查看简介", _request_skip)
	_skip.add_theme_font_size_override("font_size", 22)
	_skip.custom_minimum_size = Vector2(260, 50)
	add_child(_skip)
	_skip.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_skip.offset_left = -292
	_skip.offset_right = -32
	_skip.offset_top = -82
	_skip.offset_bottom = -32
	_skip.tooltip_text = "空格跳过影像，Esc 暂停；跳过后显示剧情简介。"
	_cloud_material = ShaderMaterial.new()
	_cloud_material.shader = preload("res://ui/shaders/CloudCurtain.gdshader")
	_curtain = TextureRect.new()
	_curtain.texture = (load("res://assets/cinematics/opening/cloud_overlay.png") if ResourceLoader.exists("res://assets/cinematics/opening/cloud_overlay.png") else null)
	_curtain.material = _cloud_material
	_curtain.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_curtain.stretch_mode = TextureRect.STRETCH_SCALE
	_curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_curtain.visible = false
	_full_rect(_curtain)
	if video_stream == null:
		_show_summary()
		return
	_player.stream = video_stream
	_player.play()
	_skip.grab_focus()

func _full_rect(control: Control, parent: Node = self) -> void:
	parent.add_child(control)
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _unhandled_key_input(event: InputEvent) -> void:
	if phase == Phase.VIDEO and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		_request_skip()
		get_viewport().set_input_as_handled()

func _request_skip() -> void:
	if phase != Phase.VIDEO:
		return
	_player.stop()
	_show_summary()

func _show_summary() -> void:
	phase = Phase.SUMMARY
	_video_stage.visible = false
	_skip.visible = false
	_summary = ColorRect.new()
	(_summary as ColorRect).color = Color(UiKit.DEEP, 0.88)
	_full_rect(_summary)
	var margin := MarginContainer.new()
	_full_rect(margin, _summary)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 120)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 70)
	var center := CenterContainer.new()
	margin.add_child(center)
	var panel := UiKit.panel()
	panel.custom_minimum_size.x = 880
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	panel.add_child(box)
	box.add_child(UiKit.label("启程之前", 42, UiKit.GOLD.lightened(0.2)))
	var body := UiKit.label("一批入藏的古锦，留下了多种纹样。修复人员能将它保护下来，但缺损处原来的样子与制作工艺，仍需要更多依据。\n\n你是一名纪录片编导。刘主任安排你跟随寻访队伍，沿茶马古道寻找传承这些手艺的人，拍摄专题纪录片。\n\n收好相机与行囊，飞机已越过云层。旅程将从丽江开始。", 26, UiKit.PAPER)
	body.custom_minimum_size.x = 752
	box.add_child(body)
	var proceed := UiKit.button("了解了 · 进入主页面", _begin_transition, true)
	box.add_child(proceed)
	proceed.grab_focus()

func _on_video_finished() -> void:
	if phase != Phase.VIDEO:
		return
	# finished 后播放器可能清掉画面，用同源末帧保持窗景，直到云幕完全遮满。
	_last_frame.visible = true
	_player.visible = false
	_begin_transition()

func _begin_transition() -> void:
	if phase != Phase.VIDEO and phase != Phase.SUMMARY:
		return
	phase = Phase.COVERING
	_skip.visible = false
	_player.paused = true
	var focused := get_viewport().gui_get_focus_owner()
	if is_instance_valid(focused):
		focused.release_focus()
	# 阻断鼠标点击与键盘重复确认；动画跟随场景树暂停。
	_curtain.mouse_filter = Control.MOUSE_FILTER_STOP
	_curtain.visible = true
	_curtain.move_to_front()
	_set_cloud_opening(1.0)
	_transition = create_tween()
	_transition.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_transition.tween_method(_set_cloud_opening, 1.0, 0.0, 1.35)
	await _transition.finished
	_video_stage.visible = false
	if is_instance_valid(_summary):
		_summary.visible = false
	_player.stop()
	_player.stream = null
	video_stream = null
	phase = Phase.REVEALING
	GameMusic.play("home")
	_transition = create_tween()
	_transition.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_transition.tween_interval(0.15)
	_transition.tween_method(_set_cloud_opening, 0.0, 1.0, 2.8)
	_transition.parallel().tween_method(_home.set_menu_reveal, 0.0, 0.999, 1.5).set_delay(1.15)
	await _transition.finished
	_curtain.visible = false
	_curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_home.set_menu_reveal(1.0)
	phase = Phase.HOME
	_home.focus_start()

func _set_cloud_opening(amount: float) -> void:
	_cloud_material.set_shader_parameter("opening", amount)

func set_game_paused(value: bool) -> void:
	if is_instance_valid(_player):
		_player.paused = value or phase != Phase.VIDEO

func is_opening_active() -> bool:
	return phase != Phase.HOME

func can_skip_opening() -> bool:
	return phase == Phase.VIDEO

func skip_opening() -> void:
	_request_skip()
