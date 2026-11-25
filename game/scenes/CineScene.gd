extends Control
## OGV 视频 + 定时选择。缺失视频显示明确接入状态，不发奖励、不推进流程。
var _data: Dictionary
var _player: VideoStreamPlayer
var _choices: VBoxContainer
var _seen: Dictionary = {}
var _active_hotspot: Dictionary = {}
var _ended := false
var _title: Label
var _skip: Button

func _ready() -> void:
	_data = ContentDB.cinematic(SceneRouter.params.get("cine_id", ""))
	if not _valid_data():
		_data = {}
	var page := UiKit.page(self, _data.get("title", "剧情影像"), "古道影像 · Esc 可暂停", _leave)
	_title = page.get_child(1)
	var stage := Control.new()
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.custom_minimum_size.y = 300
	page.add_child(stage)
	_player = VideoStreamPlayer.new()
	_player.expand = true
	stage.add_child(_player)
	_player.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_player.finished.connect(_on_video_finished)
	_choices = VBoxContainer.new()
	_choices.add_theme_constant_override("separation", 12)
	page.add_child(_choices)
	_skip = UiKit.button("跳过影像", _request_skip)
	_skip.visible = _data.get("allow_skip", false)
	page.add_child(_skip)
	var path: String = _data.get("video", "")
	var stream: VideoStream = load(path) as VideoStream if not path.is_empty() and ResourceLoader.exists(path) else null
	if stream == null:
		_title.text = "这段影像正在制作，请稍后再来。"
		_skip.visible = false
		var center := CenterContainer.new()
		stage.add_child(center)
		center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var notice := UiKit.label("影像尚未接入", 44, UiKit.GOLD)
		notice.custom_minimum_size.x = 620
		notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		center.add_child(notice)
		return
	_player.stream = stream
	_player.play()

func _process(_delta: float) -> void:
	if _ended or _player.stream == null or not _active_hotspot.is_empty():
		return
	for hotspot in _data.get("hotspots", []):
		var id: String = hotspot.get("id", "")
		if not _seen.has(id) and _player.stream_position >= float(hotspot.get("at", 0)):
			_show_hotspot(hotspot)
			return

func _show_hotspot(hotspot: Dictionary) -> void:
	_active_hotspot = hotspot
	_player.paused = true
	_title.text = hotspot.get("prompt", "选择下一步")
	UiKit.clear(_choices)
	for i in hotspot.get("choices", []).size():
		_choices.add_child(UiKit.button(hotspot["choices"][i].get("label", "继续"), _choose.bind(i)))
	if _choices.get_child_count() > 0:
		_choices.get_child(0).grab_focus()

func _choose(index: int) -> void:
	if _active_hotspot.is_empty():
		return
	var choices: Array = _active_hotspot.get("choices", [])
	if index < 0 or index >= choices.size():
		return
	var choice: Dictionary = choices[index]
	var cine_id: String = SceneRouter.params.get("cine_id", "")
	GameState.record_choice(cine_id + "/" + str(_active_hotspot.get("id", "")), index)
	JourneyFlow.apply_action(choice.get("action", {}))
	_seen[_active_hotspot.get("id", "")] = true
	_active_hotspot = {}
	UiKit.clear(_choices)
	_title.text = "古道影像 · Esc 可暂停"
	if choice.has("on_end"):
		_ended = true
		JourneyFlow.dispatch(choice["on_end"])
	elif _ended:
		_finish()
	else:
		_player.paused = false

func _request_skip() -> void:
	if not _active_hotspot.is_empty():
		GameUI.notify("先作出当前选择，再继续影像。")
		return
	# 跳过播放仍逐个询问未完成的抉择，不默选、不丢失分支。
	for hotspot in _data.get("hotspots", []):
		if not _seen.has(hotspot.get("id", "")):
			_show_hotspot(hotspot)
			return
	_finish()

func _on_video_finished() -> void:
	_ended = true
	for hotspot in _data.get("hotspots", []):
		if not _seen.has(hotspot.get("id", "")):
			_show_hotspot(hotspot)
			return
	_finish()

func _finish() -> void:
	if _player.stream == null:
		return
	# 视频结束时可能还有同时间的其他选择，逐一补齐。
	for hotspot in _data.get("hotspots", []):
		if not _seen.has(hotspot.get("id", "")):
			_show_hotspot(hotspot)
			return
	_ended = true
	_player.stop()
	if SceneRouter.params.has("flow_step"):
		JourneyFlow.complete_current()
	else:
		JourneyFlow.dispatch(_data.get("on_end", {"type": "map"}))

func _leave() -> void:
	_player.stop()
	var station: String = SceneRouter.params.get("station", "")
	if station.is_empty():
		SceneRouter.goto_map()
	else:
		JourneyFlow.return_to_city(station)

func set_game_paused(value: bool) -> void:
	if is_instance_valid(_player):
		_player.paused = value or not _active_hotspot.is_empty()

func _valid_data() -> bool:
	if _data.is_empty() or not _data.get("hotspots", []) is Array:
		return false
	var ids: Dictionary = {}
	for hotspot in _data.get("hotspots", []):
		if not hotspot is Dictionary or not hotspot.get("choices") is Array:
			return false
		var id: String = hotspot.get("id", "")
		if id.is_empty() or ids.has(id) or hotspot["choices"].is_empty():
			return false
		ids[id] = true
		for choice in hotspot["choices"]:
			if not choice is Dictionary:
				return false
	return true
