extends Node
## 本地故障注入：--mock-base-url=http://127.0.0.1:端口
## 真实文本+画布视觉：--llm-live（需要非 headless 渲染及 user://llm.cfg）。
var _failures := 0
var _scene: Node

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS ", description)
	else:
		_failures += 1
		printerr("FAIL ", description)

func _reset(endpoint: String, timeout: float = 2.0) -> void:
	_scene._llm_cfg["endpoint"] = endpoint
	_scene._llm_cfg["timeout_sec"] = timeout
	_scene._llm_cfg["draw_min_strokes"] = 1
	_scene._llm_cfg["instant_outline"] = false
	_scene._api_key = "local-test-key"
	_scene._offline = false
	_scene._offline_noticed = false
	_scene._llm_retry_next_round = false
	_scene._llm_last_error = ""

func _chat() -> Variant:
	return await _scene._llm_chat([{"role": "user", "content": "test"}])

func _ready() -> void:
	_scene = load("res://scenes/puzzles/PuzzlePattern.tscn").instantiate()
	add_child(_scene)
	var mock_base := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mock-base-url="):
			mock_base = arg.trim_prefix("--mock-base-url=")
	if not mock_base.is_empty():
		await _mock_tests(mock_base)
	elif "--llm-live" in OS.get_cmdline_user_args():
		await _live_tests()
	elif "--llm-offline" in OS.get_cmdline_user_args():
		await _offline_tests()
	else:
		_check(false, "必须选择本地 mock 或真实接口模式")
	_scene.queue_free()
	await get_tree().process_frame
	print("Pattern LLM failures=", _failures)
	get_tree().quit(0 if _failures == 0 else 1)

func _mock_tests(base: String) -> void:
	_reset(base + "/ok")
	var content: Variant = await _chat()
	_check(content == "ok" and not _scene._offline, "正常响应可连接")
	_check(_scene._llm_status.text == "在线 · 已收到回应", "界面显示真实在线响应")
	_reset(base + "/slow", 3.0)
	content = await _chat()
	_check(content == "ok", "慢响应在配置等待时间内成功")
	_reset(base + "/retry")
	content = await _chat()
	_check(content == "ok" and not _scene._offline, "503 后重试成功")
	_reset(base + "/auth")
	content = await _chat()
	_check(content == null and _scene._offline and not _scene._llm_retry_next_round, "401 明确提示且不无效重试")
	_check(_scene._llm_last_error == "密钥或访问权限无效", "鉴权错误分类")
	_check(_scene._reconnect_btn.visible, "离线可手动重新连接")
	# 真实传输超时不能受游戏时钟加速影响。
	_reset(base + "/timeout", 1.0)
	var started := Time.get_ticks_msec()
	Engine.time_scale = 8.0
	content = await _chat()
	Engine.time_scale = 1.0
	_check(Time.get_ticks_msec() - started >= 2800, "HTTP 超时按现实时间计时")
	_check(content == null and _scene._llm_retry_next_round, "超时只本轮降级，允许下轮恢复")
	_scene._llm_cfg["endpoint"] = base + "/draw"
	_scene._llm_cfg["stroke_delay"] = 0.01
	_scene._start_round()
	started = Time.get_ticks_msec()
	while _scene._busy and Time.get_ticks_msec() - started < 5000:
		await get_tree().process_frame
	_check(not _scene._offline and not _scene._busy and _scene._options_root.get_child_count() == 4, "下一回合重连成功并完成发题")
	_reset(base + "/malformed")
	content = await _chat()
	_check(content == null and _scene._offline, "非法 choices 类型安全回退")
	_reset(base + "/empty")
	content = await _chat()
	_check(content == null and _scene._offline, "空模型内容不能冒充连接成功")
	_reset("invalid-url")
	content = await _chat()
	_check(content == null and _scene._offline and not _scene._llm_retry_next_round, "错误地址不挂起")
	_scene._on_reconnect_llm()
	_check(_scene._offline == _scene._api_key.is_empty() and not _scene._llm_retry_next_round, "手动重连重新加载密钥并清除失败状态")
	_scene._debug_force_offline()
	content = await _chat()
	_check(content == null and _scene._offline, "无密钥直接使用离线，不发送请求")

func _offline_tests() -> void:
	_scene._debug_force_offline()
	_scene._llm_cfg["stroke_delay"] = 0.01
	_scene._on_intro_start()
	for round_number in range(1, 7):
		var started := Time.get_ticks_msec()
		while _scene._busy and Time.get_ticks_msec() - started < 8000:
			await get_tree().process_frame
		_check(not _scene._busy and _scene._rounds_played == round_number, "离线第 %d 轮可操作" % round_number)
		if round_number == 1 and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://../drafts/llm-connection-fix-2026-10-03/offline-screen.png")
		if _scene._busy:
			return
		if round_number <= 3:
			_scene._on_option(_scene._topic["id"])
		else:
			if round_number == 4:
				_scene._player_strokes = [PackedVector2Array([Vector2(10, 10), Vector2(100, 100)])]
				_scene._on_submit()
				_check(not _scene._busy and _scene._success == 3, "离线画不足三笔不会直接过关")
				_scene._on_clear()
			_scene._debug_doodle()
			_scene._on_submit()
		if round_number < 6:
			started = Time.get_ticks_msec()
			while _scene._rounds_played == round_number and Time.get_ticks_msec() - started < 8000:
				await get_tree().process_frame
	var started := Time.get_ticks_msec()
	while not _scene._solved and Time.get_ticks_msec() - started < 8000:
		await get_tree().process_frame
	_check(_scene._solved and _scene._success == 6, "离线完成全部六轮并通关")
	_check(_scene._api_key.is_empty() and not _scene._llm_retry_next_round, "离线测试全程不调用真实服务")

func _live_tests() -> void:
	_check(not _scene._api_key.is_empty(), "本机密钥已加载")
	if _scene._api_key.is_empty():
		return
	var cfg: Dictionary = _scene._llm_cfg
	var fish: Dictionary = _scene._pattern_by_id("fish")
	var prompt: String = cfg["draw_user"].replace("{name}", fish["name"]).replace("{keywords}", fish["keywords"]).replace("{example}", JSON.stringify(fish["strokes"]))
	var started := Time.get_ticks_msec()
	var content: Variant = await _scene._llm_chat([
		{"role": "system", "content": cfg["draw_system"]},
		{"role": "user", "content": prompt},
	])
	print("LIVE draw seconds=", (Time.get_ticks_msec() - started) / 1000.0)
	var parsed: Variant = _scene._extract_json(str(content))
	_check(content != null and not _scene._offline, "真实文本调用成功，无离线兜底")
	_check(not _scene._validate_strokes(parsed).is_empty(), "真实模型笔触满足游戏协议")
	if _scene._offline:
		return
	_scene._phase = "b"
	_scene._phase_a_chrome(false)
	_scene._player_strokes = _scene._scale_strokes(fish["strokes"]["strokes"])
	_scene._board.queue_redraw()
	# 关闭说明层后截取真实画纸，走玩家提交使用的 PNG/base64 路径。
	_scene._intro_layer.queue_free()
	await get_tree().process_frame
	var b64: String = await _scene._capture_board_b64()
	var image := Image.new()
	_check(image.load_png_from_buffer(Marshalls.base64_to_raw(b64)) == OK, "实际画布截图可解码为 PNG")
	image.save_png("res://../drafts/llm-connection-fix-2026-10-03/live-canvas.png")
	var candidates := ""
	for p in _scene.config["decks"]["animals"]["patterns"]:
		candidates += "%s（%s）｜" % [p["name"], p["keywords"]]
	started = Time.get_ticks_msec()
	content = await _scene._llm_chat([
		{"role": "system", "content": cfg["guess_system"]},
		{"role": "user", "content": [
			{"type": "text", "text": cfg["guess_user"].replace("{candidates}", candidates.trim_suffix("｜"))},
			{"type": "image_url", "image_url": {"url": "data:image/png;base64," + b64}},
		]},
	])
	print("LIVE vision seconds=", (Time.get_ticks_msec() - started) / 1000.0)
	parsed = _scene._extract_json(str(content))
	_check(content != null and not _scene._offline, "真实视觉调用成功，无离线兜底")
	_check(parsed is Dictionary and parsed.has("guess") and parsed.has("is_text"), "视觉返回游戏可读取的猜画结果")
	if parsed is Dictionary:
		print("LIVE vision guess=", parsed.get("guess", ""), " expected=", fish["name"])
		_check(parsed.get("guess", "") == fish["name"], "模型认出真实画布上的鱼")
