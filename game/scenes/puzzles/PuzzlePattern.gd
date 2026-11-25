extends PuzzleBase
## PuzzlePattern —— 大理·你画我猜·双三轮（接口约定 v7 注册表 #3）
## 前半程「婆婆画」3 轮：基础轮廓先落笔，LLM 流式选择曲线笔法 → 玩家 4 选 1。
## 后半程「玩家画」3 轮：玩家照纹样卡作画 → GLM-4V 视觉猜（3 次机会可补画）。
## 6 轮累计认对 ≥5 过关，不足则加赛；断网/无 key 自动降级本地模式（离线可通关）。
## 内容全部来自 puzzles.json 的 dali 节点，脚本只定义布局与交互。

const INK_GEOMETRY := preload("res://puzzles/PatternInk.gd")
const INK_STREAM := preload("res://puzzles/PatternSseStream.gd")
const INK_BRUSHES := preload("res://puzzles/PatternBrushLibrary.gd")

const EMPHASIS_FONT := preload("res://assets/shared/fonts/emphasis.tres")

const GOLD := Color("#C9A24B")
const GOLD_HI := Color("#FFE09B")
const RED := Color("#B5482F")
const INK := Color("#1E3A34")
const PAPER := Color("#EDE3CB")
const INDIGO := Color("#3B4A6B")

# ---- 布局（1280×720）----
const POPO_POS := Vector2(36, 150)
const POPO_SIZE := Vector2(200, 411)       # 487×1000 比例
const BOARD_POS := Vector2(290, 130)
const BOARD_SIZE := Vector2(630, 400)
const SIL_POS := Vector2(965, 340)
const SIL_SIZE := Vector2(280, 239)        # 1052×900 比例
const TOPIC_POS := Vector2(975, 128)
const TOPIC_SIZE := Vector2(150, 150)
const OPTION_Y := 545.0
const OPTION_CARD := 90.0
const OPTION_STEP := 130.0
const SUBMIT_POS := Vector2(440, 566)
const CLEAR_POS := Vector2(660, 566)
const BTN_SIZE := Vector2(180, 54)
const STRIP_RECT := Rect2(20, 662, 1240, 44)

const EXPRESSIONS := {
	"normal": "npc_popo.png",
	"thinking": "npc_popo_thinking.png",
	"happy": "npc_popo_happy.png",
	"confused": "npc_popo_confused.png",
	"laugh": "npc_popo_laugh.png",
}

var _assets_dir := ""
var _llm_cfg := {}
var _texts := {}
var _win_need := 5
var _total_rounds := 6

var _expr_tex := {}            # 表情名 -> Texture2D
var _api_key := ""
var _offline := false
var _offline_noticed := false
var _llm_retry_next_round := false
var _llm_last_error := ""
var _llm_status: Label
var _reconnect_btn: Button

var _popo: TextureRect
var _board: Control            # 画纸（婆婆画与玩家画共用）
var _silhouette: TextureRect
var _topic_box: Control        # 玩家画阶段的纹样卡
var _options_root: Control     # 婆婆画阶段的 4 张选项卡
var _strip: Label              # 婆婆的话
var _title: Label
var _prompt: Label
var _progress: Label
var _dots: Array[Panel] = []
var _submit_btn: Button
var _clear_btn: Button
var _charcoal: TextureRect

# 回合状态
var _phase := "a"              # a=婆婆画 b=玩家画
var _rounds_played := 0
var _success := 0
var _results: Array[bool] = []
var _pools := {"a": [], "b": []}   # 各阶段题池（pattern Dictionary）
var _used_ids := {}
var _topic: Dictionary = {}
var _option_ids: Array = []
var _attempts := 0
var _busy := false
var _solved := false
var _win_card_layer: CanvasLayer

# 画纸状态
var _player_strokes: Array = []          # PackedVector2Array（画纸本地坐标）
var _current := PackedVector2Array()
var _drawing_now := false
var _popo_strokes: Array = []            # PackedVector2Array（已换算到画纸坐标）
var _reveal_count := 0
var _ink_queue: Array = []
var _partial_ink := PackedVector2Array()
var _inking := false
var _ink_generation := 0
var _stream_stats: Dictionary = {}
var _draw_commands: Array = []
var _brush_catalogue: Array = []
var _used_brushes: Array = []
var _draw_topic_name := ""

# ---------- 钩子 ----------

func _on_setup(cfg: Dictionary) -> void:
	_assets_dir = cfg.get("assets_dir", "res://assets/puzzles/dali/")
	_llm_cfg = cfg.get("llm", {})
	_texts = cfg.get("texts", {})
	_win_need = int(cfg.get("win_need", 5))
	_total_rounds = int(cfg.get("total_rounds", 6))
	_api_key = _load_api_key()
	_offline = _api_key == ""

	for expr in EXPRESSIONS:
		_expr_tex[expr] = _optional_texture(_assets_dir + EXPRESSIONS[expr])

	_build_scene(cfg)
	_update_llm_status("离线 · 未配置密钥" if _offline else "已就绪 · 等待作画")
	_prepare_pools(cfg)
	# 退出按钮置顶并统一风格
	for child in get_children():
		if child is Button:
			move_child(child, -1)
			_style_button(child)

func _on_start() -> void:
	if _offline and not _offline_noticed:
		_offline_noticed = true
	_start_round()

func _check_win() -> bool:
	return _solved

func _on_complete() -> void:
	_play_sfx("match_ok")
	_set_expression("laugh")
	_pulse_gold(_board, BOARD_SIZE)

# ---------- 场景搭建 ----------

func _build_scene(cfg: Dictionary) -> void:
	var bg := TextureRect.new()
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.texture = _optional_texture(_assets_dir + "bg_zharanfang.png")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var shade := ColorRect.new()
	shade.color = Color(0.05, 0.09, 0.08, 0.30)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	# 顶栏
	_panel(self, Vector2(20, 16), Vector2(1240, 84), Color(INK, 0.90), 20)
	_title = _label(self, "", Vector2(48, 26), Vector2(640, 36), 30, PAPER)
	_prompt = _label(self, "", Vector2(48, 64), Vector2(760, 28), 19, Color(PAPER, 0.84))
	_progress = _label(self, "", Vector2(820, 30), Vector2(320, 32), 24, GOLD, true)
	for i in _total_rounds:
		_dots.append(_dot(self, Vector2(850 + i * 40, 84), 6.0, Color(GOLD, 0.18), Color(GOLD, 0.4)))

	# 婆婆（左）
	_popo = TextureRect.new()
	_popo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_popo.texture = _expr_tex["normal"]
	_popo.position = POPO_POS
	_popo.size = POPO_SIZE
	_popo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_popo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_popo)
	var bob := create_tween().set_loops()
	bob.tween_property(_popo, "position:y", POPO_POS.y - 6.0, 2.4).set_trans(Tween.TRANS_SINE)
	bob.tween_property(_popo, "position:y", POPO_POS.y, 2.4).set_trans(Tween.TRANS_SINE)

	# 炭条图标（婆婆作画时亮）
	_charcoal = TextureRect.new()
	_charcoal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_charcoal.texture = _optional_texture(_assets_dir + "tool_charcoal.png")
	_charcoal.position = Vector2(214, 520)
	_charcoal.size = Vector2(72, 39)
	_charcoal.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_charcoal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_charcoal.modulate.a = 0.0
	add_child(_charcoal)

	# 画纸（中）
	var paper_frame := _panel(self, BOARD_POS - Vector2(10, 10), BOARD_SIZE + Vector2(20, 20), Color(PAPER, 0.96), 18)
	var frame_style := paper_frame.get_theme_stylebox("panel") as StyleBoxFlat
	frame_style.set_border_width_all(3)
	frame_style.border_color = Color(GOLD, 0.75)
	_board = Control.new()
	_board.position = BOARD_POS
	_board.size = BOARD_SIZE
	_board.mouse_filter = Control.MOUSE_FILTER_STOP
	_board.draw.connect(_on_board_draw)
	_board.gui_input.connect(_on_board_input)
	add_child(_board)

	# 玩家剪影（右）
	_silhouette = TextureRect.new()
	_silhouette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_silhouette.texture = _optional_texture(_assets_dir + "player_silhouette.png")
	_silhouette.position = SIL_POS
	_silhouette.size = SIL_SIZE
	_silhouette.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_silhouette.modulate.a = 0.82
	_silhouette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_silhouette)

	# 纹样卡（玩家画阶段，右上）
	_topic_box = Control.new()
	_topic_box.position = TOPIC_POS
	_topic_box.size = TOPIC_SIZE
	_topic_box.visible = false
	add_child(_topic_box)

	# 选项卡容器（婆婆画阶段，底部）
	_options_root = Control.new()
	_options_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_options_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_options_root)

	# 画好了 / 重画（玩家画阶段）
	_submit_btn = _make_button("画好了", SUBMIT_POS, BTN_SIZE, _on_submit)
	_clear_btn = _make_button("重画", CLEAR_POS, BTN_SIZE, _on_clear)
	_submit_btn.visible = false
	_clear_btn.visible = false

	# 底部对话条
	var strip_bg := _panel(self, STRIP_RECT.position, STRIP_RECT.size, Color(INK, 0.88), 18)
	strip_bg.get_theme_stylebox("panel").set_border_width_all(0)
	_strip = _label(self, "", STRIP_RECT.position + Vector2(24, 0), STRIP_RECT.size - Vector2(48, 0), 24, PAPER, true)
	_llm_status = _label(self, "", Vector2(32, 575), Vector2(240, 28), 17, PAPER, true)
	_reconnect_btn = _make_button("重新连接", Vector2(64, 612), Vector2(180, 40), _on_reconnect_llm)

## 题池：婆婆画 3 题（每库 1）+ 玩家画 3 题（每库 1，与同库婆婆画题不同）
func _prepare_pools(cfg: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for deck_id in cfg["decks"]:
		var pats: Array = cfg["decks"][deck_id]["patterns"].duplicate(true)
		pats.shuffle()
		var a_pick: Dictionary = pats[0]
		_pools["a"].append(a_pick)
		_used_ids[a_pick["id"]] = true
		var b_pick: Dictionary = pats[1]
		_pools["b"].append(b_pick)
		_used_ids[b_pick["id"]] = true
	# 加赛池：所有未用题目
	_pools["extra"] = []
	for deck_id in cfg["decks"]:
		for p in cfg["decks"][deck_id]["patterns"]:
			if not _used_ids.has(p["id"]):
				_pools["extra"].append(p)
	_pools["extra"].shuffle()
	_pools["a"].shuffle()
	_pools["b"].shuffle()

# ---------- 回合流转 ----------

func _start_round() -> void:
	# 网络抖动只影响当前回合；下一回合允许恢复在线。
	if _offline and _llm_retry_next_round:
		_offline = false
		_llm_retry_next_round = false
		_update_llm_status("正在恢复连接…")
	_rounds_played += 1
	_attempts = 0
	_update_progress()
	if _phase == "a":
		_round_a()
	else:
		_round_b()

func _next_round() -> void:
	if _rounds_played >= _total_rounds and _success >= _win_need:
		_win()
		return
	if _rounds_played >= _total_rounds and _success < _win_need:
		_say(_texts.get("extra_round", ""), GOLD)
		await get_tree().create_timer(1.0, false).timeout
	# 阶段切换：前 3 轮婆婆画，第 4 轮起玩家画；加赛交替
	if _rounds_played < 3:
		_phase = "a"
	elif _rounds_played < _total_rounds:
		_phase = "b"
	else:
		_phase = "b" if _phase == "a" else "a"
	_start_round()

func _draw_topic() -> Dictionary:
	var pool: Array = _pools[_phase]
	if pool.is_empty():
		pool = _pools["extra"]
		if pool.is_empty():
			# 全部用过了（极端加赛）：从全库随机
			for deck_id in config["decks"]:
				pool.append_array(config["decks"][deck_id]["patterns"])
	_topic = pool.pop_back()
	_used_ids[_topic["id"]] = true
	return _topic

# ---------- 婆婆画（阶段 A）----------

func _round_a() -> void:
	_busy = true
	_phase_a_chrome(true)
	var topic := _draw_topic()
	_set_expression("normal")
	_say(_texts.get("a_open", ""), PAPER)
	_charcoal.modulate.a = 1.0
	await _paint_popo_topic(topic, false)
	_charcoal.modulate.a = 0.0
	_show_options(topic)
	_busy = false

## 作画使用 SSE：完整曲线命令到达就进入落笔队列，无需等待整幅 JSON。
func _paint_popo_topic(topic: Dictionary, extra: bool) -> void:
	_draw_topic_name = str(topic.get("name", ""))
	var base_count := _popo_strokes.size() if extra else 0
	var base_commands := _draw_commands.size() if extra else 0
	if not extra:
		_draw_commands.clear()
		_used_brushes.clear()
		_brush_catalogue = INK_BRUSHES.recipe(str(topic["id"]))
		_reset_popo_ink(0)
	var base_brush_count := _used_brushes.size()
	_stream_stats = {"started_ms": Time.get_ticks_msec(), "first_visible_ms": -1, "finished_ms": -1, "commands": 0, "invalid": 0, "fallback": false}
	if _offline:
		if not extra:
			await _animate_strokes(_fallback_topic_strokes(topic))
		return
	var reason := "画稿格式无效"
	var retryable := true
	for attempt in 2:
		var parser = INK_GEOMETRY.new()
		var stream = INK_STREAM.new()
		add_child(stream)
		stream.text_received.connect(_accept_popo_commands.bind(parser))
		# 两笔基础轮廓立即落纸；模型同时生成剩余笔法，开场不空等网络。
		if not extra and bool(_llm_cfg.get("instant_outline", true)):
			for i in mini(2, _brush_catalogue.size()):
				_used_brushes.append(i)
				_draw_commands.append(_brush_catalogue[i])
				_queue_popo_stroke(INK_GEOMETRY.command_to_stroke(_brush_catalogue[i]))
			_stream_stats["local_outline"] = mini(2, _brush_catalogue.size())
		_update_llm_status("婆婆正在落笔…" if attempt == 0 else "正在重新连接…")
		var prompt: String = _llm_cfg.get("draw_stream_user", "")
		prompt = prompt.replace("{name}", topic["name"]).replace("{keywords}", topic["keywords"])
		var available: Array = []
		for i in _brush_catalogue.size():
			if not _used_brushes.has(i):
				available.append(i)
		if available.is_empty():
			stream.queue_free()
			_stream_stats["finished_ms"] = Time.get_ticks_msec()
			_update_llm_status("在线 · 细节已画全")
			return
		prompt += "\n可用笔法编号：" + JSON.stringify(available) + "，共%d笔。编号越小越接近主体轮廓，大编号是局部细节。" % available.size()
		if extra:
			prompt += "\n只选剩余编号的2~3笔补充细节。"
		else:
			prompt += "\n请至少选择前%d笔，预留最后2笔供学徒没认出时补画。编号不重复。" % maxi(6, available.size() - 2)
		var result: Dictionary = await stream.chat(str(_llm_cfg.get("endpoint", "")), _api_key, {
			"model": _llm_cfg.get("model", "glm-4v-flash"), "stream": true, "temperature": 0.35, "max_tokens": 1024,
			"messages": [
				{"role": "user", "content": str(_llm_cfg.get("draw_stream_system", "")) + "\n" + prompt},
			],
		}, maxf(1, float(_llm_cfg.get("timeout_sec", 30))))
		stream.queue_free()
		_stream_stats["raw_content"] = result["content"]
		_stream_stats["finished_ms"] = Time.get_ticks_msec()
		var minimum := 1 if extra else mini(int(_llm_cfg.get("draw_min_strokes", 6)), maxi(1, available.size() - 2))
		if result["ok"] and int(_stream_stats["commands"]) >= minimum:
			await _wait_popo_ink()
			_offline_noticed = false
			_llm_last_error = ""
			_llm_retry_next_round = false
			_update_llm_status("在线 · 曲线画稿已完成")
			return
		reason = result["reason"] if not result["ok"] else "画稿格式无效"
		retryable = result["retryable"] if not result["ok"] else true
		_reset_popo_ink(base_count)
		_draw_commands.resize(base_commands)
		_used_brushes.resize(base_brush_count)
		_stream_stats["commands"] = 0
		_stream_stats["first_visible_ms"] = -1
		if not retryable:
			break
		if attempt == 0:
			await get_tree().create_timer(1.0, true, false, true).timeout
	_llm_fallback(reason, retryable)
	_stream_stats["fallback"] = true
	if not extra:
		await _animate_strokes(_fallback_topic_strokes(topic))

func _fallback_topic_strokes(topic: Dictionary) -> Array:
	var out: Array = []
	for command in INK_BRUSHES.recipe(str(topic["id"])):
		var stroke: PackedVector2Array = INK_GEOMETRY.command_to_stroke(command)
		if stroke.size() >= 2:
			out.append(stroke)
	return out if not out.is_empty() else _scale_strokes(topic["strokes"]["strokes"])

func _accept_popo_commands(text: String, parser: RefCounted) -> void:
	if _exiting or _finished:
		return
	for command in parser.feed_commands(text):
		if command.get("op", "") == "comment":
			var comment := str(command.get("text", ""))
			var technical := false
			for word in ["工具", "编号", "JSON", "程序", "模型", "选择"]:
				technical = technical or comment.contains(word)
			if technical or (not _draw_topic_name.is_empty() and comment.contains(_draw_topic_name)):
				comment = "弯处慢些，花样就活了。"
			_say(comment.left(20), PAPER)
			continue
		if int(_stream_stats["commands"]) >= 24:
			continue
		if command.get("op", "") == "part":
			var id: Variant = command.get("id", null)
			if not (id is int or id is float) or float(id) != floorf(float(id)) or int(id) < 0 or int(id) >= _brush_catalogue.size():
				_stream_stats["invalid"] += 1
				continue
			if _used_brushes.has(int(id)):
				continue
			_used_brushes.append(int(id))
			command = _brush_catalogue[int(id)]
		var stroke: PackedVector2Array = INK_GEOMETRY.command_to_stroke(command)
		if stroke.size() < 2:
			_stream_stats["invalid"] += 1
			continue
		_stream_stats["commands"] += 1
		_draw_commands.append(command)
		_queue_popo_stroke(stroke)

func _reset_popo_ink(keep_count: int) -> void:
	_ink_generation += 1
	_ink_queue.clear()
	_partial_ink.clear()
	_inking = false
	_popo_strokes.resize(keep_count)
	_reveal_count = keep_count
	_board.queue_redraw()

func _queue_popo_stroke(stroke: PackedVector2Array) -> void:
	_ink_queue.append(stroke)
	if not _inking:
		_ink_popo_queue()

func _ink_popo_queue() -> void:
	_inking = true
	var generation := _ink_generation
	while not _ink_queue.is_empty():
		var stroke: PackedVector2Array = _ink_queue.pop_front()
		var length := 0.0
		for i in range(1, stroke.size()):
			length += stroke[i-1].distance_to(stroke[i])
		var speed := maxf(100, float(_llm_cfg.get("ink_speed", 1100)))
		var duration := clampf(length / speed, 0.12, 0.65)
		var start := Time.get_ticks_msec()
		_play_sfx("draw")
		while Time.get_ticks_msec() - start < duration * 1000:
			if generation != _ink_generation or _exiting:
				return
			var fraction := (Time.get_ticks_msec() - start) / (duration * 1000.0)
			_partial_ink = INK_GEOMETRY.prefix(stroke, fraction)
			if fraction > 0 and _stream_stats.get("first_visible_ms", -1) < 0:
				_stream_stats["first_visible_ms"] = Time.get_ticks_msec()
			_board.queue_redraw()
			await get_tree().process_frame
		if generation != _ink_generation or _exiting:
			return
		_popo_strokes.append(stroke)
		_reveal_count = _popo_strokes.size()
		_partial_ink.clear()
		_board.queue_redraw()
	_inking = false

func _wait_popo_ink() -> void:
	while _inking or not _ink_queue.is_empty():
		await get_tree().process_frame

func _scale_strokes(raw: Array) -> Array:
	var out: Array = []
	for stroke in raw:
		var line := PackedVector2Array()
		for pt in stroke:
			line.append(INK_GEOMETRY.to_board(Vector2(float(pt[0]), float(pt[1]))))
		if line.size() >= 2:
			out.append(_smooth(line))
	return out

## Catmull-Rom 样条平滑：稀疏折线点 → 毛笔曲线（首尾重合的按闭环处理）
func _smooth(points: PackedVector2Array) -> PackedVector2Array:
	if points.size() < 3:
		return points
	const SEG := 8
	var closed: bool = points[0].distance_to(points[points.size() - 1]) < 3.0
	var src := points
	if closed:
		src = points.slice(0, points.size() - 1)
	var n := src.size()
	var out := PackedVector2Array()
	var seg_count := n if closed else n - 1
	for i in seg_count:
		var p0: Vector2 = src[(i - 1 + n) % n] if (closed or i > 0) else src[0]
		var p1: Vector2 = src[i]
		var p2: Vector2 = src[(i + 1) % n]
		var p3: Vector2 = src[(i + 2) % n] if (closed or i + 2 < n) else src[n - 1]
		for j in SEG:
			var t := float(j) / SEG
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t3))
	out.append(src[0] if closed else src[n - 1])
	return out

func _animate_strokes(strokes: Array) -> void:
	for stroke in strokes:
		_queue_popo_stroke(stroke)
	await _wait_popo_ink()

func _show_options(topic: Dictionary) -> void:
	_option_ids = [topic["id"]]
	var deck_id := _deck_of(topic["id"])
	var pool: Array = []
	for p in config["decks"][deck_id]["patterns"]:
		if p["id"] != topic["id"]:
			pool.append(p)
	pool.shuffle()
	for p in pool.slice(0, 3):
		_option_ids.append(p["id"])
	_option_ids.shuffle()
	for i in _option_ids.size():
		var pid: String = _option_ids[i]
		var pat := _pattern_by_id(pid)
		var cell := Control.new()
		cell.position = Vector2(OPTION_X0 + i * OPTION_STEP, OPTION_Y)
		cell.size = Vector2(OPTION_CARD, OPTION_CARD + 30)
		_options_root.add_child(cell)
		var btn := Button.new()
		btn.size = Vector2(OPTION_CARD, OPTION_CARD)
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			btn.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		var tex := TextureRect.new()
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.texture = _optional_texture(_assets_dir + pat["card"])
		tex.size = Vector2(OPTION_CARD, OPTION_CARD)
		tex.stretch_mode = TextureRect.STRETCH_SCALE
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(tex)
		var rim := Panel.new()
		rim.size = Vector2(OPTION_CARD, OPTION_CARD)
		rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rim_style := StyleBoxFlat.new()
		rim_style.bg_color = Color(0, 0, 0, 0)
		rim_style.set_border_width_all(2)
		rim_style.border_color = Color(GOLD, 0.65)
		rim_style.set_corner_radius_all(8)
		rim.add_theme_stylebox_override("panel", rim_style)
		btn.add_child(rim)
		btn.pressed.connect(_on_option.bind(pid))
		cell.add_child(btn)
		_label(cell, pat["name"], Vector2(-15, OPTION_CARD + 2), Vector2(OPTION_CARD + 30, 26), 22, PAPER, true)
		_reveal(cell, i * 0.06, 10.0)

const OPTION_X0 := (1280 - 4 * 130.0 + 40.0) / 2.0

func _on_option(pid: String) -> void:
	if _phase != "a" or _busy or _finished or _solved or _option_ids.is_empty():
		return
	if pid == _topic["id"]:
		_attempts += 1
		_round_success()
		return
	_attempts += 1
	_set_expression("confused")
	_play_sfx("match_bad")
	_say(_texts.get("a_wrong", ""), Color("#FFD1BC"))
	for cell in _options_root.get_children():
		for btn in cell.get_children():
			if btn is Button:
				_shake(btn)
	if _attempts >= 3:
		_say(_texts.get("a_hint3", ""), GOLD)
		var idx := _option_ids.find(_topic["id"])
		if idx >= 0 and idx < _options_root.get_child_count():
			_pulse_gold(_options_root.get_child(idx), Vector2(OPTION_CARD, OPTION_CARD + 30))
	else:
		# 补画同样流式落笔，不重新等待完整坐标列表。
		_busy = true
		await _paint_popo_topic(_topic, true)
		_busy = false

# ---------- 玩家画（阶段 B）----------

func _round_b() -> void:
	_phase_a_chrome(false)
	var topic := _draw_topic()
	_set_expression("normal")
	_player_strokes = []
	_current = PackedVector2Array()
	_popo_strokes = []
	_reveal_count = 0
	_board.queue_redraw()
	_show_topic_card(topic)
	_submit_btn.visible = true
	_clear_btn.visible = true
	_submit_btn.disabled = false
	_clear_btn.disabled = false
	_say(_texts.get("b_open", "") + ("　" + _texts.get("offline_notice", "") if _offline else ""), PAPER)

func _on_board_input(event: InputEvent) -> void:
	if _phase != "b" or _busy or _finished or _solved:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drawing_now = true
			_current = PackedVector2Array()
			_current.append(event.position)
			_board.queue_redraw()
		elif _drawing_now:
			_drawing_now = false
			if _current.size() >= 2:
				_player_strokes.append(_current)
			_current = PackedVector2Array()
			_board.queue_redraw()
	elif event is InputEventMouseMotion and _drawing_now:
		var pos: Vector2 = event.position
		if _current.is_empty() or _current[_current.size() - 1].distance_to(pos) > 3.0:
			_current.append(pos)
			_board.queue_redraw()

func _on_board_draw() -> void:
	# 婆婆画的笔触（按 reveal 数显示）
	for i in mini(_reveal_count, _popo_strokes.size()):
		_draw_ink_stroke(_popo_strokes[i])
	if _partial_ink.size() >= 2:
		_draw_ink_stroke(_partial_ink)
	# 玩家笔触（只在玩家画阶段显示）
	if _phase != "b":
		return
	for line in _player_strokes:
		_board.draw_polyline(line, INDIGO, 5.0, true)
	if _current.size() >= 2:
		_board.draw_polyline(_current, INDIGO, 5.0, true)

func _draw_ink_stroke(line: PackedVector2Array) -> void:
	# 细线与圆润收笔，保留清楚的白纸留白；不把曲线画成粗折线。
	_board.draw_polyline(line, Color(INDIGO, 0.95), 3.0, true)
	_board.draw_circle(line[0], 1.5, Color(INDIGO, 0.95), true, -1, true)
	_board.draw_circle(line[line.size()-1], 1.5, Color(INDIGO, 0.95), true, -1, true)

func _on_clear() -> void:
	if _phase != "b" or _busy or _finished:
		return
	_player_strokes = []
	_current = PackedVector2Array()
	_board.queue_redraw()

func _on_submit() -> void:
	if _phase != "b" or _busy or _finished or _solved:
		return
	var need := 3 if _offline else 1
	if _player_strokes.size() < need:
		_say(_texts.get("b_need_more", ""), Color("#FFD1BC"))
		return
	_busy = true
	_submit_btn.disabled = true
	_clear_btn.disabled = true
	_set_expression("thinking")
	if _offline:
		await get_tree().create_timer(0.9, false).timeout
		_say(_texts.get("b_offline_ok", ""), PAPER)
		_round_success()
		return
	var b64 := await _capture_board_b64()
	var content: Variant = await _llm_chat(_build_guess_messages(b64))
	if content == null:
		# 连接失败明确走离线保底，不能冒充婆婆认出了答案。
		_say(_texts.get("b_offline_ok", ""), PAPER)
		_round_success()
		return
	_apply_guess_response(content)

func _build_guess_messages(b64: String) -> Array:
	var candidates := ""
	var deck_id := _deck_of(_topic["id"])
	for p in config["decks"][deck_id]["patterns"]:
		candidates += "%s（%s）｜" % [p["name"], p["keywords"]]
	candidates = candidates.trim_suffix("｜")
	var user_tmpl: String = _llm_cfg.get("guess_user", "")
	var user := user_tmpl.replace("{candidates}", candidates)
	# 不包含本题名、目标卡或正确性结论；模型只能看玩家画纸及完整候选清单。
	return [
		{"role": "system", "content": _llm_cfg.get("guess_system", "")},
		{"role": "user", "content": [
			{"type": "text", "text": user},
			{"type": "image_url", "image_url": {"url": "data:image/png;base64," + b64}},
		]},
	]

func _apply_guess_response(content: Variant) -> void:
	var parsed: Variant = _extract_json(str(content))
	if parsed == null or not (parsed is Dictionary):
		_attempts += 1
		_say(_texts.get("b_wrong_fallback", ""), Color("#FFD1BC"))
		_after_wrong_b()
		return
	if bool(parsed.get("is_text", false)):
		_say(_texts.get("b_text", ""), GOLD)
		_set_expression("confused")
		_busy = false
		_submit_btn.disabled = false
		_clear_btn.disabled = false
		return
	var guess := str(parsed.get("guess", "")).strip_edges()
	var valid_guess := false
	for pattern in config["decks"][_deck_of(_topic["id"])]["patterns"]:
		valid_guess = valid_guess or guess == pattern["name"]
	if bool(parsed.get("uncertain", false)) or not valid_guess:
		guess = ""
	# 固定显示识别结果，模型comment不能用泛泛鼓励覆盖猜测。
	var feedback: String = _texts.get("b_wrong_fallback", "这回我没看出来，你再补几笔。")
	if not guess.is_empty():
		feedback = str(_texts.get("b_guess_named", "我猜是「%s」，对不对？")).replace("%s", guess)
	if guess == _topic["name"]:
		_say(feedback, PAPER)
		_round_success()
		return
	_attempts += 1
	_set_expression("confused")
	_play_sfx("match_bad")
	_say(feedback, Color("#FFD1BC"))
	_after_wrong_b()

func _after_wrong_b() -> void:
	if _attempts >= 3:
		# 本轮结果由游戏提示；婆婆仍保留刚才的实际猜测，不突然知道正确答案。
		_prompt.text = _texts.get("b_round_missed", "本轮未猜中，稍后进入下一题。")
		_results.append(false)
		_update_progress()
		await get_tree().create_timer(2.2, false).timeout
		_hide_topic_card()
		_busy = false
		_next_round()
		return
	_busy = false
	_submit_btn.disabled = false
	_clear_btn.disabled = false

# ---------- 共用收尾 ----------

func _round_success() -> void:
	_busy = true
	_results.append(true)
	_success += 1
	_update_progress()
	_set_expression("happy")
	_play_sfx("match_ok")
	if _phase == "a":
		var praises: Array = _texts.get("a_correct", ["嗯，眼力不错！"])
		_say(praises[randi() % praises.size()], GOLD_HI)
		for cell in _options_root.get_children():
			_border(cell, GOLD_HI, 0.6, Vector2(OPTION_CARD, OPTION_CARD + 30))
	else:
		_border(_board, GOLD_HI, 0.8, BOARD_SIZE)
	await get_tree().create_timer(1.2, false).timeout
	_clear_round_chrome()
	_busy = false
	_next_round()

func _clear_round_chrome() -> void:
	_reset_popo_ink(0)
	for cell in _options_root.get_children():
		cell.queue_free()
	_option_ids = []
	_hide_topic_card()
	_submit_btn.visible = false
	_clear_btn.visible = false
	_popo_strokes = []
	_reveal_count = 0
	_player_strokes = []
	_current = PackedVector2Array()
	_board.queue_redraw()

func _phase_a_chrome(is_a: bool) -> void:
	_title.text = _texts.get("phase_a_title", "") if is_a else _texts.get("phase_b_title", "")
	_prompt.text = _texts.get("phase_a_prompt", "") if is_a else _texts.get("phase_b_prompt", "")

func _show_topic_card(topic: Dictionary) -> void:
	for child in _topic_box.get_children():
		child.queue_free()
	_topic_box.visible = true
	var frame := _panel(_topic_box, Vector2(-8, -8), TOPIC_SIZE + Vector2(16, 46), Color(INK, 0.85), 14)
	frame.get_theme_stylebox("panel").set_border_width_all(2)
	var tex := TextureRect.new()
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.texture = _optional_texture(_assets_dir + topic["card"])
	tex.size = TOPIC_SIZE
	tex.stretch_mode = TextureRect.STRETCH_SCALE
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_topic_box.add_child(tex)
	_label(_topic_box, "照着画 · " + topic["name"], Vector2(-8, TOPIC_SIZE.y + 6), Vector2(TOPIC_SIZE.x + 16, 30), 22, GOLD, true)
	_reveal(_topic_box, 0.0, 12.0)

func _hide_topic_card() -> void:
	_topic_box.visible = false

func _update_progress() -> void:
	_progress.text = _texts.get("progress_fmt", "第 %d 轮 · 认对 %d / %d") % [mini(_rounds_played, _total_rounds), _success, _win_need]
	for i in _dots.size():
		if i < _results.size():
			_dots[i].modulate = GOLD_HI if _results[i] else Color(RED, 0.85)
		else:
			_dots[i].modulate = Color(1, 1, 1, 0.35)

func _set_expression(expr: String) -> void:
	if _expr_tex.has(expr):
		_popo.texture = _expr_tex[expr]

# ---------- 通关 ----------

func _win() -> void:
	if _solved:
		return
	_solved = true
	_busy = true
	_set_expression("laugh")
	if _defer_city_reward():
		_say("这一批花样核对好了，咱们一起整理记录。", GOLD_HI)
		_complete()
		return
	var layer := CanvasLayer.new()
	layer.layer = 40
	add_child(layer)
	_win_card_layer = layer
	var viewport_size := get_viewport().get_visible_rect().size
	var dim := ColorRect.new()
	dim.color = Color(INK, 0.80)
	dim.size = viewport_size
	dim.modulate.a = 0.0
	layer.add_child(dim)
	var card := Control.new()
	card.size = Vector2(900, 440)
	card.position = (viewport_size - card.size) * 0.5
	card.pivot_offset = card.size * 0.5
	layer.add_child(card)
	var paper := TextureRect.new()
	paper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	paper.texture = _optional_texture("res://assets/shared/paper_base.png")
	paper.size = card.size
	paper.stretch_mode = TextureRect.STRETCH_SCALE
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(paper)
	_label(card, "大理 · 扎染坊", Vector2(60, 40), Vector2(780, 26), 19, Color(INK, 0.8), true)
	_label(card, _texts.get("win_card_title", ""), Vector2(60, 72), Vector2(780, 52), 40, INK, true)
	var quote_plate := Panel.new()
	quote_plate.position = Vector2(80, 150)
	quote_plate.size = Vector2(740, 130)
	quote_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var plate_style := _style(Color(GOLD, 0.13), 14)
	plate_style.set_border_width_all(2)
	plate_style.border_color = Color(GOLD, 0.75)
	quote_plate.add_theme_stylebox_override("panel", plate_style)
	card.add_child(quote_plate)
	var quote := Label.new()
	quote.text = _wrap_cjk(_texts.get("win_quote", ""), 26)
	quote.position = Vector2(100, 158)
	quote.size = Vector2(700, 114)
	quote.add_theme_font_override("font", EMPHASIS_FONT)
	quote.add_theme_font_size_override("font_size", 26)
	quote.add_theme_color_override("font_color", Color("#8A5A1E"))
	quote.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quote.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	quote.autowrap_mode = TextServer.AUTOWRAP_OFF
	quote.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(quote)
	var btn := Button.new()
	btn.text = _texts.get("win_button", "")
	btn.position = Vector2(280, 330)
	btn.size = Vector2(340, 58)
	btn.add_theme_font_size_override("font_size", 25)
	_style_button(btn)
	btn.pressed.connect(func() -> void:
		layer.queue_free()
		_complete()
	)
	card.add_child(btn)
	card.scale = Vector2.ONE * 0.9
	card.modulate.a = 0.0
	var show := create_tween().set_parallel()
	show.tween_property(dim, "modulate:a", 1.0, 0.28)
	show.tween_property(card, "modulate:a", 1.0, 0.26)
	show.tween_property(card, "scale", Vector2.ONE, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## 结算页（替换基类占位）
func _show_win_placeholder(fragment_ids: Array) -> void:
	if _defer_city_reward():
		puzzle_completed.emit(station_id, fragment_ids)
		_back_to_map.call_deferred()
		return
	_win_layer = CanvasLayer.new()
	_win_layer.layer = 60
	add_child(_win_layer)
	var viewport_size := get_viewport().get_visible_rect().size
	var dim := ColorRect.new()
	dim.color = Color(INK, 0.86)
	dim.size = viewport_size
	_win_layer.add_child(dim)
	var card := Control.new()
	card.size = Vector2(900, 460)
	card.position = (viewport_size - card.size) * 0.5
	card.pivot_offset = card.size * 0.5
	dim.add_child(card)
	var paper := TextureRect.new()
	paper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	paper.texture = _optional_texture("res://assets/shared/paper_base.png")
	paper.size = card.size
	paper.stretch_mode = TextureRect.STRETCH_SCALE
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(paper)
	_label(card, _texts.get("summary_title", ""), Vector2(60, 48), Vector2(780, 52), 40, INK, true)
	# 六轮成绩点
	for i in _results.size():
		var d := _dot(card, Vector2(340 + i * 46, 150), 10.0, GOLD_HI if _results[i] else Color(RED, 0.85), Color(INK, 0.5))
		d.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(d, "modulate:a", 1.0, 0.2).set_delay(0.3 + i * 0.08)
	_label(card, _texts.get("summary_line", "") % [_success, _rounds_played], Vector2(60, 200), Vector2(780, 36), 26, INK, true)
	# 获得的纹样卡展示（本轮出题卡）
	var shown := 0
	for pid in _used_ids:
		if shown >= 6:
			break
		var pat := _pattern_by_id(pid)
		if pat.is_empty():
			continue
		var tex := TextureRect.new()
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.texture = _optional_texture(_assets_dir + pat["card"])
		tex.position = Vector2(140 + shown * 106, 256)
		tex.size = Vector2(92, 92)
		tex.stretch_mode = TextureRect.STRETCH_SCALE
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tex.modulate.a = 0.0
		card.add_child(tex)
		var tw2 := create_tween()
		tw2.tween_property(tex, "modulate:a", 1.0, 0.25).set_delay(0.5 + shown * 0.07)
		shown += 1
	var btn := Button.new()
	btn.text = _texts.get("summary_button", "")
	btn.position = Vector2(290, 380)
	btn.size = Vector2(320, 56)
	btn.add_theme_font_size_override("font_size", 25)
	_style_button(btn)
	btn.pressed.connect(func() -> void:
		puzzle_completed.emit(station_id, fragment_ids)
		_back_to_map()
	)
	card.add_child(btn)
	card.scale = Vector2.ONE * 0.88
	card.modulate.a = 0.0
	var tween := create_tween().set_parallel()
	tween.tween_property(card, "modulate:a", 1.0, 0.28)
	tween.tween_property(card, "scale", Vector2.ONE, 0.46).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# ---------- LLM 接入 ----------

func _defer_city_reward() -> bool:
	return _gs == get_node_or_null("/root/GameState") and SceneRouter.params.get("defer_reward", false)

func _load_api_key() -> String:
	for env_name in ["BIGMODEL_API_KEY", "ZHIPU_API_KEY", "LLM_API_KEY"]:
		var key := OS.get_environment(env_name).strip_edges()
		if not key.is_empty():
			return key
	# 仅从开发者环境或用户数据目录读取，不从项目内携带凭据。
	for path in ["user://llm.cfg"]:
		if not FileAccess.file_exists(path):
			continue
		var cf := ConfigFile.new()
		if cf.load(path) == OK:
			var key := str(cf.get_value("llm", "api_key", "")).strip_edges()
			if not key.is_empty():
				return key
	push_warning("[PuzzlePattern] 未配置密钥：" + ProjectSettings.globalize_path("user://llm.cfg"))
	return ""

func _update_llm_status(text: String) -> void:
	if is_instance_valid(_llm_status):
		_llm_status.text = text
		_llm_status.tooltip_text = _llm_last_error
	if is_instance_valid(_reconnect_btn):
		_reconnect_btn.visible = _offline

func _on_reconnect_llm() -> void:
	if _busy or _finished or _solved:
		return
	_api_key = _load_api_key()
	_offline = _api_key.is_empty()
	_llm_retry_next_round = false
	_llm_last_error = ""
	_offline_noticed = false
	_update_llm_status("离线 · 未配置密钥" if _offline else "已就绪 · 下次作画时连接")

func _llm_fallback(reason: String, retryable: bool) -> void:
	_llm_last_error = reason
	_llm_retry_next_round = retryable
	_offline = true
	_update_llm_status("离线 · " + reason)
	push_warning("[PuzzlePattern] " + reason)
	if not _offline_noticed:
		_offline_noticed = true
		_say(_texts.get("offline_notice", ""), GOLD)

func _llm_transport_error(result: int) -> String:
	match result:
		HTTPRequest.RESULT_TIMEOUT: return "等待模型超时"
		HTTPRequest.RESULT_CANT_RESOLVE: return "域名解析失败"
		HTTPRequest.RESULT_CANT_CONNECT: return "无法连接服务"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR: return "安全连接失败"
		_: return "网络请求失败（%d）" % result

func _llm_response_content(body: PackedByteArray) -> Variant:
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (data is Dictionary):
		return null
	var choices: Variant = data.get("choices", [])
	if not (choices is Array) or choices.is_empty() or not (choices[0] is Dictionary):
		return null
	var message: Variant = choices[0].get("message", {})
	if not (message is Dictionary):
		return null
	var content: Variant = message.get("content", null)
	return content if content is String and not content.strip_edges().is_empty() else null

## 返回 content 字符串；临时失败仅本轮降级，下一回合恢复尝试。
func _llm_chat(messages: Array) -> Variant:
	if _offline or _api_key == "":
		return null
	var endpoint: String = str(_llm_cfg.get("endpoint", "")).strip_edges()
	if not endpoint.begins_with("https://") and not endpoint.begins_with("http://"):
		_llm_fallback("服务地址配置错误", false)
		return null
	var timeout_sec: float = maxf(1.0, float(_llm_cfg.get("timeout_sec", 30)))
	var reason := "模型未返回有效内容"
	var retryable := true
	for attempt in 2:
		_update_llm_status("婆婆正在想…" if attempt == 0 else "正在重新连接…")
		var http := HTTPRequest.new()
		http.timeout = timeout_sec
		http.use_threads = true
		add_child(http)
		var payload := {"model": _llm_cfg.get("model", "glm-4v-flash"), "messages": messages, "stream": false}
		var headers := PackedStringArray([
			"Content-Type: application/json",
			"Authorization: Bearer " + _api_key,
		])
		var err := http.request(endpoint, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
		if err != OK:
			http.queue_free()
			_llm_fallback("请求配置错误（%d）" % err, false)
			return null
		var response: Array = await http.request_completed
		http.queue_free()
		var result: int = response[0]
		var code: int = response[1]
		var body: PackedByteArray = response[3]
		if result != HTTPRequest.RESULT_SUCCESS:
			reason = _llm_transport_error(result)
		elif code == 200:
			var content: Variant = _llm_response_content(body)
			if content != null:
				_offline_noticed = false
				_llm_last_error = ""
				_llm_retry_next_round = false
				_update_llm_status("在线 · 已收到回应")
				return content
			reason = "模型未返回有效内容"
		else:
			reason = "服务返回 HTTP %d" % code
			if code == 401 or code == 403:
				reason = "密钥或访问权限无效"
			retryable = code == 408 or code == 429 or code >= 500
			# 日志保留服务端错误，过滤密钥，便于区分余额/模型/限流错误。
			push_warning("[PuzzlePattern] LLM HTTP %d: %s" % [code, body.get_string_from_utf8().replace(_api_key, "[redacted]").left(200)])
		push_warning("[PuzzlePattern] 第 %d 次调用失败：%s" % [attempt + 1, reason])
		if not retryable:
			break
		if attempt == 0:
			await get_tree().create_timer(1.0, true, false, true).timeout
	_llm_fallback(reason, retryable)
	return null

func _extract_json(text: String) -> Variant:
	var start := text.find("{")
	var end := text.rfind("}")
	if start < 0 or end <= start:
		return null
	return JSON.parse_string(text.substr(start, end - start + 1))

func _validate_strokes(parsed: Variant) -> Array:
	if parsed == null or not (parsed is Dictionary):
		return []
	var raw: Variant = parsed.get("strokes", null)
	if raw == null or not (raw is Array) or raw.is_empty() or raw.size() > 20:
		return []
	var out: Array = []
	for stroke in raw:
		if not (stroke is Array) or stroke.size() < 2:
			return []
		var line: Array = []
		for pt in stroke:
			if not (pt is Array) or pt.size() < 2:
				return []
			var x := float(pt[0])
			var y := float(pt[1])
			if x < 0.0 or x > 100.0 or y < 0.0 or y > 100.0:
				return []
			line.append([x, y])
		out.append(line)
	return out

## 画布截图 → PNG base64（截图必须等帧尾，经验#15）
func _capture_board_b64() -> String:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var rect := Rect2i(_board.get_global_rect())
	rect = rect.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var crop := img.get_region(rect)
	crop.resize(512, int(512.0 * rect.size.y / maxf(1.0, rect.size.x)), Image.INTERPOLATE_LANCZOS)
	return Marshalls.raw_to_base64(crop.save_png_to_buffer())

# ---------- 通用小组件（沿用普洱模式） ----------

func _style(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	return style

func _panel(parent: Control, pos: Vector2, dimensions: Vector2, color: Color, radius: int) -> Panel:
	var panel := Panel.new()
	panel.position = pos
	panel.size = dimensions
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := _style(color, radius)
	style.set_border_width_all(1)
	style.border_color = Color(GOLD, 0.35)
	style.shadow_color = Color(0.02, 0.04, 0.03, 0.32)
	style.shadow_size = 12
	style.shadow_offset = Vector2(0, 6)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	return panel

func _label(parent: Control, text: String, pos: Vector2, dimensions: Vector2, font_size: int, color: Color, centered: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.size = dimensions
	label.add_theme_font_size_override("font_size", font_size)
	if font_size >= 24:
		label.add_theme_font_override("font", EMPHASIS_FONT)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if centered:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(label)
	return label

func _style_button(button: Button) -> void:
	var normal := _style(INK, 16)
	normal.set_border_width_all(2)
	normal.border_color = GOLD
	normal.shadow_color = Color(INK, 0.30)
	normal.shadow_size = 4
	normal.shadow_offset = Vector2(0, 4)
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("#31574A")
	button.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("#142D27")
	button.add_theme_stylebox_override("pressed", pressed)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(INK, 0.60)
	disabled.border_color = Color(GOLD, 0.25)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_disabled_color", Color(PAPER, 0.45))

func _make_button(text: String, pos: Vector2, dimensions: Vector2, handler: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.position = pos
	btn.size = dimensions
	btn.add_theme_font_size_override("font_size", 25)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_style_button(btn)
	btn.pressed.connect(handler)
	add_child(btn)
	return btn

func _dot(parent: Control, pos: Vector2, radius: float, fill: Color, ring: Color) -> Panel:
	var dot := Panel.new()
	dot.size = Vector2(radius * 2, radius * 2)
	dot.position = pos - Vector2(radius, radius)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(int(radius))
	style.set_border_width_all(2)
	style.border_color = ring
	dot.add_theme_stylebox_override("panel", style)
	dot.pivot_offset = dot.size * 0.5
	parent.add_child(dot)
	return dot

func _say(text: String, color: Color) -> void:
	_strip.text = _wrap_cjk(text, 48)
	_strip.add_theme_color_override("font_color", color)

func _wrap_cjk(text: String, max_chars: int) -> String:
	if text.length() <= max_chars:
		return text
	var lines: Array = []
	var rest := text
	while rest.length() > max_chars:
		var cut := -1
		for i in range(max_chars, 0, -1):
			var ch := rest.substr(i - 1, 1)
			if ch == "，" or ch == "。" or ch == "；" or ch == "、":
				cut = i
				break
		if cut <= 0:
			cut = max_chars
		lines.append(rest.substr(0, cut))
		rest = rest.substr(cut)
	if rest != "":
		lines.append(rest)
	return "\n".join(lines)

func _border(row: Control, color: Color, duration: float, dimensions: Vector2) -> void:
	var border := Panel.new()
	border.set_meta("feedback", true)
	border.position = Vector2(-4, -4)
	border.size = dimensions + Vector2(8, 8)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := _style(Color(color, 0.05), 14)
	style.set_border_width_all(4)
	style.border_color = color
	border.add_theme_stylebox_override("panel", style)
	row.add_child(border)
	var tween := create_tween()
	tween.tween_interval(duration * 0.6)
	tween.tween_property(border, "modulate:a", 0.0, duration * 0.4)
	tween.tween_callback(border.queue_free)

func _shake(row: Control) -> void:
	var home: Vector2 = row.get_meta("home", row.position)
	var tween := create_tween()
	tween.tween_property(row, "position", home + Vector2(-7, 0), 0.06)
	tween.tween_property(row, "position", home + Vector2(7, 0), 0.08)
	tween.tween_property(row, "position", home + Vector2(-4, 0), 0.07)
	tween.tween_property(row, "position", home, 0.08)

func _pulse_gold(row: Control, dimensions: Vector2) -> void:
	var ring := Panel.new()
	ring.set_meta("feedback", true)
	ring.position = Vector2(-6, -6)
	ring.size = dimensions + Vector2(12, 12)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := _style(Color(0.0, 0.0, 0.0, 0.0), 16)
	style.set_border_width_all(5)
	style.border_color = GOLD_HI
	ring.add_theme_stylebox_override("panel", style)
	row.add_child(ring)
	var tween := create_tween().set_loops(4)
	tween.tween_property(ring, "modulate:a", 0.25, 0.22)
	tween.tween_property(ring, "modulate:a", 1.0, 0.22)
	tween.finished.connect(ring.queue_free)

func _reveal(node: Control, delay: float, lift: float) -> void:
	var home := node.position
	node.position.y += lift
	node.modulate.a = 0.0
	var motion := create_tween().set_parallel()
	motion.tween_property(node, "position", home, 0.42).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	motion.tween_property(node, "modulate:a", 1.0, 0.32).set_delay(delay)

func _deck_of(pid: String) -> String:
	for deck_id in config["decks"]:
		for p in config["decks"][deck_id]["patterns"]:
			if p["id"] == pid:
				return deck_id
	return "animals"

func _pattern_by_id(pid: String) -> Dictionary:
	for deck_id in config["decks"]:
		for p in config["decks"][deck_id]["patterns"]:
			if p["id"] == pid:
				return p
	return {}

# ---------- 调试接口（截图跑测用） ----------

func _debug_doodle() -> void:
	if _phase != "b":
		return
	# 模拟玩家画几笔（一个简单的圈+两笔）
	var circle := PackedVector2Array()
	for i in 25:
		var a := TAU * float(i) / 24.0
		circle.append(BOARD_SIZE * 0.5 + Vector2(cos(a), sin(a)) * 120.0)
	_player_strokes.append(circle)
	var l1 := PackedVector2Array([BOARD_SIZE * Vector2(0.3, 0.7), BOARD_SIZE * Vector2(0.5, 0.3)])
	_player_strokes.append(l1)
	var l2 := PackedVector2Array([BOARD_SIZE * Vector2(0.5, 0.3), BOARD_SIZE * Vector2(0.7, 0.7)])
	_player_strokes.append(l2)
	_board.queue_redraw()

func _debug_force_offline() -> void:
	_offline = true
	_api_key = ""
	_llm_retry_next_round = false
	_update_llm_status("离线 · 本地画法")

func _debug_accept_win() -> void:
	if _win_card_layer != null and is_instance_valid(_win_card_layer):
		_win_card_layer.queue_free()
	_complete()

# 公开副本不携带图片；无图时仍允许执行协议与离线规则测试。
func _optional_texture(path: String) -> Texture2D:
	return load(path) as Texture2D if ResourceLoader.exists(path) else null
