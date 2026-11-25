extends Node
const INK := preload("res://puzzles/PatternInk.gd")
const STREAM := preload("res://puzzles/PatternSseStream.gd")
const BRUSHES := preload("res://puzzles/PatternBrushLibrary.gd")
const OUT := "user://test-output/"
var _failures := 0
var _scene: Node
var _painting_done := false

func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS ", label)
	else:
		_failures += 1
		printerr("FAIL ", label)

func _ready() -> void:
	_unit_tests()
	_scene = load("res://scenes/puzzles/PuzzlePattern.tscn").instantiate()
	add_child(_scene)
	_scene._intro_layer.queue_free()
	var base := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mock-base-url="):
			base = arg.trim_prefix("--mock-base-url=")
	if not base.is_empty():
		await _mock_tests(base)
	elif "--live" in OS.get_cmdline_user_args():
		for topic_id in ["butterfly", "plum_blossom", "oil_umbrella"]:
			await _live_topic(topic_id)
	_scene.queue_free()
	await get_tree().process_frame
	print("Pattern Stream failures=", _failures)
	get_tree().quit(0 if _failures == 0 else 1)

func _unit_tests() -> void:
	var parser = INK.new()
	_check(parser.feed_commands('```json\n{"op":"ell').is_empty(), "不完整命令不提前落笔")
	var commands: Array = parser.feed_commands('ipse","x":50,"y":50,"rx":20,"ry":20}\n{"op":"comment","text":"花开{春}，好看"}\n```')
	_check(commands.size() == 2 and commands[1]["text"] == "花开{春}，好看", "JSON跨token、中文和引号内括号正确解析")
	var circle: PackedVector2Array = INK.command_to_stroke(commands[0])
	_check(circle.size() == 65 and circle[0].is_equal_approx(circle[64]), "椭圆采样成闭合光滑曲线")
	_check(is_equal_approx(circle[0].x - circle[32].x, circle[16].y - circle[48].y), "圆形等比绘制，不被630×400画纸拉宽")
	var prefix: PackedVector2Array = INK.prefix(circle, 0.25)
	_check(prefix.size() > 2 and prefix.size() < circle.size(), "单笔按长度逐渐出现，不整笔闪现")
	_check(INK.command_to_stroke({"op":"path", "p":[[0,0],[10,10]]}).is_empty(), "拒绝双点直线命令")
	_check(INK.command_to_stroke({"op":"ellipse", "x":95,"y":50,"rx":20,"ry":20}).is_empty(), "拒绝越出纸面的曲线")
	_check(INK.command_to_stroke({"op":"ellipse", "x":"bad","y":50,"rx":20,"ry":20}).is_empty(), "非数值控制点不崩溃")
	_check(INK.command_to_stroke({"op":"petal","x":50,"y":50,"l":25,"w":8,"a":-90}).size() == 65, "花瓣由两段贝塞尔曲线组成")
	var stream = STREAM.new()
	var received: Array = []
	stream.text_received.connect(func(text: String) -> void: received.append(text))
	var event := 'data: ' + JSON.stringify({"choices":[{"delta":{"content":"一笔一笔画"}}]}) + '\r\n\r\ndata: [DONE]\n\n'
	var bytes := event.to_utf8_buffer()
	for byte in bytes:
		stream.feed_bytes(PackedByteArray([byte]))
	_check(received == ["一笔一笔画"] and stream._finished, "SSE逐字节分片不损坏UTF-8中文")
	stream.free()
	var config: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/puzzles.json"))
	for deck in config["dali"]["decks"].values():
		for topic in deck["patterns"]:
			var brushes: Array = BRUSHES.recipe(topic["id"])
			var valid := brushes.size() >= 8
			for command in brushes:
				valid = valid and not INK.command_to_stroke(command).is_empty()
			_check(valid, topic["id"] + " 曲线库完整且所有笔触在纸内")

func _reset(endpoint: String, timeout: float = 3.0) -> void:
	_scene._llm_cfg["endpoint"] = endpoint
	_scene._llm_cfg["timeout_sec"] = timeout
	_scene._llm_cfg["draw_min_strokes"] = 1
	_scene._llm_cfg["instant_outline"] = false
	_scene._api_key = "local-test-key"
	_scene._offline = false
	_scene._llm_retry_next_round = false
	_scene._offline_noticed = false

func _mock_tests(base: String) -> void:
	var topic: Dictionary = _scene._pattern_by_id("butterfly")
	_reset(base + "/stream")
	await _scene._paint_popo_topic(topic, false)
	_check(not _scene._offline and _scene._stream_stats["commands"] == 3, "真实HTTP流式分片解析三笔曲线")
	_check(_scene._stream_stats["first_visible_ms"] < _scene._stream_stats["finished_ms"] - 1000, "第一笔在服务器输出完毕前显示")
	_check(not _scene._inking and _scene._ink_queue.is_empty(), "网络完成后等待落笔队列结束")
	var old_count: int = _scene._popo_strokes.size()
	await _scene._paint_popo_topic(topic, true)
	_check(_scene._popo_strokes.size() == old_count + 3, "补画流式追加，不清除已画主体")
	_reset(base + "/stream-retry")
	await _scene._paint_popo_topic(topic, false)
	_check(not _scene._offline and _scene._popo_strokes.size() == 3, "首次503后流式重试成功，笔触不重复")
	_reset(base + "/stream-auth")
	await _scene._paint_popo_topic(topic, false)
	_check(_scene._offline and not _scene._llm_retry_next_round and _scene._stream_stats["fallback"], "401无效密钥只请求一次并使用预设曲线")
	_reset(base + "/stream-cut")
	await _scene._paint_popo_topic(topic, false)
	_check(_scene._offline and _scene._stream_stats["fallback"], "中途断流会清除残稿并使用完整预设")
	_check(_scene._popo_strokes.size() == _scene._fallback_topic_strokes(topic).size(), "断流不叠加模型残稿与预设图")
	_reset(base + "/stream")
	_scene._start_round()
	var started := Time.get_ticks_msec()
	while _scene._busy and Time.get_ticks_msec() - started < 8000:
		await get_tree().process_frame
	_check(not _scene._busy and _scene._options_root.get_child_count() == 4, "完成流式作画后正常进入四选一")

func _paint(topic: Dictionary) -> void:
	_painting_done = false
	await _scene._paint_popo_topic(topic, false)
	_painting_done = true

func _live_topic(topic_id: String) -> void:
	_check(not _scene._api_key.is_empty(), "真实接口已加载密钥")
	if _scene._api_key.is_empty():
		return
	_scene._offline = false
	var topic: Dictionary = _scene._pattern_by_id(topic_id)
	_scene._phase_a_chrome(true)
	_paint(topic)
	var started := Time.get_ticks_msec()
	var progress_saved := false
	while not _painting_done and Time.get_ticks_msec() - started < 125000:
		if not progress_saved and _scene._popo_strokes.size() >= 2 and _scene._stream_stats["finished_ms"] < 0:
			_scene._board.queue_redraw()
			await get_tree().process_frame
			RenderingServer.force_draw()
			get_viewport().get_texture().get_image().save_png(OUT + topic_id + "-progress.png")
			progress_saved = true
		await get_tree().process_frame
	_check(_painting_done and not _scene._offline and not _scene._stream_stats["fallback"], topic_id + " 实际在线曲线作画成功")
	var stats: Dictionary = _scene._stream_stats
	var raw_file := FileAccess.open(OUT + topic_id + "-raw.txt", FileAccess.WRITE)
	raw_file.store_string(str(stats.get("raw_content", "")))
	print("LIVE ", topic_id, " first_visible_s=", (stats["first_visible_ms"] - stats["started_ms"]) / 1000.0,
		" response_done_s=", (stats["finished_ms"] - stats["started_ms"]) / 1000.0, " commands=", stats["commands"], " invalid=", stats["invalid"])
	_check(stats["first_visible_ms"] > 0 and stats["first_visible_ms"] < stats["finished_ms"], topic_id + " 收完全部响应之前已开始画")
	_check(stats["first_visible_ms"] - stats["started_ms"] < 300, topic_id + " 基础轮廓无需等待网络即开始画")
	_check(stats["commands"] >= 6 and stats["invalid"] == 0, topic_id + " 曲线数量和协议合法")
	_scene._board.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	RenderingServer.force_draw()
	var screenshot := get_viewport().get_texture().get_image()
	screenshot.save_png(OUT + topic_id + "-finished.png")
	var canvas := screenshot.get_region(Rect2i(_scene._board.get_global_rect()))
	canvas.save_png(OUT + topic_id + "-canvas.png")
	var ink_pixels := 0
	for y in range(0, canvas.get_height(), 2):
		for x in range(0, canvas.get_width(), 2):
			var color := canvas.get_pixel(x, y)
			if color.b > color.r + 0.08 and color.b > color.g + 0.04:
				ink_pixels += 1
	_check(ink_pixels > 100, topic_id + " 实际渲染画布包含靛蓝笔触")
	var file := FileAccess.open(OUT + topic_id + "-commands.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(_scene._draw_commands, "\t"))
