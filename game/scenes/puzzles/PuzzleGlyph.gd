extends PuzzleBase
## PuzzleGlyph —— 丽江·东巴字卡连接（接口约定 v2 注册表 #1）
## 第一关（v3）：阿东巴 NPC 发牌 → 字卡单张出现 → 右侧简笔画流水线（全部常显、
##   循环流动，流水线上直接点选）选对加分 / 选错减分 / 选过的变灰 / 关卡倒计时
## 第二关：4 张残页按「马帮的一天」事理归序
## 关卡内容来自 puzzles.json；第一关视觉布局与动画在本脚本中定义。

const BIG_CARD := Vector2(252, 316)       # 字卡尺寸（4:5）
const BELT_CARD := Vector2(252, 316)      # 流水线卡尺寸（4:5）
const BELT_X := 870                      # 竖向流水线窗口左缘
const BELT_Y := 142                        # 竖向流水线窗口上缘
const BELT_H := 444                       # 竖向流水线窗口高（142..586）
const BELT_PITCH := 336                   # 卡间距（竖向循环周长 = 6 * 336）
const PAGE_PAPER := preload("res://assets/shared/page_paper.gdshader")
const EMPHASIS_FONT := preload("res://assets/shared/fonts/emphasis.tres")
const FEEDBACK_BURST := preload("res://scenes/puzzles/GlyphFeedbackBurst.gd")
const BELT_FADE := preload("res://assets/shared/belt_edge_fade.gdshader")
const PAGE_SIZE := Vector2(280, 190)      # 残页/槽位统一显示尺寸（4:3）
const GOLD := Color("#C9A24B")            # 藤黄金（唯一高亮色）
const RED := Color("#B5482F")             # 灯笼暖红（错误反馈）
const INK := Color("#1E3A34")             # 松烟墨青
const PAPER := Color("#EDE3CB")           # 宣纸米白

var _assets_dir: String = ""
var _level := 0                            # 当前关卡 1/2

# ---- 第一关状态（v3 流水线） ----
var _l1_root: Control
var _pair_of_glyph: Dictionary = {}        # glyph_id -> sketch_id
var _meaning_of_sketch: Dictionary = {}    # sketch_id -> 本义文字
var _deal_queue: Array = []                # 待发 glyph 队列（乱序）
var _current_glyph: String = ""
var _glyph_card: Button = null             # 当前字卡
var _belt_root: Control                    # 流水线窗口（裁剪区）
var _belt_cards: Dictionary = {}           # sketch_id -> Button（全部常在）
var _belt_speed := 120.0                   # 流速 px/s
var _belt_moving := false
var _belt_velocity := 0.0
var _hovered_sketch := ""
var _matched_sketches: Dictionary = {}
var _round_token := 0
var _deal_tween: Tween
var _feedback_tween: Tween
var _l1_result_layer: CanvasLayer
var _l1_result_panel: Control
var _l1_result_score: Label
var _l1_continue_btn: Button
var _transitioning := false
var _wrong_streak := 0
var _score := 0
var _score_label: Label
var _round_label: Label
var _time_bar: ProgressBar
var _time_label: Label
var _countdown := 90.0
var _countdown_total := 90.0
var _timing := false
var _matched_minis: Array = []             # 底部已配对迷你卡
var _hint_label: Label
var _busy := false                         # 结算动画期间锁输入

# ---- 第二关状态 ----
var _l2_root: Control
var _slots: Array = []
var _pages: Dictionary = {}
var _page_correct_order: Dictionary = {}
var _drag_page: TextureRect = null
var _drag_offset := Vector2.ZERO
var _submit_btn: Button
var _fail_count := 0
var _hint2_label: Label
var _placed_label: Label

# ---------- 钩子 ----------

func _on_setup(cfg: Dictionary) -> void:
	_assets_dir = cfg.get("assets_dir", "res://assets/puzzles/lijiang/")
	var bg := TextureRect.new()
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.texture = load(_assets_dir + "bg_dongba_yard.png")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var shade := ColorRect.new()
	shade.color = Color(0.08, 0.12, 0.10, 0.30)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	_setup_level1(cfg["level1"])
	_setup_level2(cfg["level2"])
	# 基类退出按钮始终显示在装饰层上方。
	move_child(get_child(0), -1)
	_l2_root.visible = false

func _on_start() -> void:
	_level = 1
	_l1_root.visible = true
	_start_level1()

func _check_win() -> bool:
	return _level >= 2 and _l2_solved()

func _on_complete() -> void:
	_play_sfx("match_ok")
	for i in _slots.size():
		var page: TextureRect = _pages[_slots[i]["page_id"]]
		_cancel_page_motion(page)
		page.rotation = 0.0
		page.scale = Vector2.ONE
		_page_border(page, Color("#FFE09B"), 1.6)
		var burst := Control.new()
		burst.set_script(FEEDBACK_BURST)
		burst.position = _slots[i]["rect"].position + PAGE_SIZE * 0.5
		burst.mouse_filter = Control.MOUSE_FILTER_IGNORE
		burst.z_index = 16
		_l2_root.add_child(burst)
		var sparkle := create_tween()
		sparkle.tween_property(burst, "progress", 1.0, 1.1).set_delay(i * 0.12)
		sparkle.tween_callback(burst.queue_free)
		var bounce := create_tween()
		page.set_meta("motion", bounce)
		bounce.tween_interval(i * 0.09)
		bounce.tween_property(page, "scale", Vector2.ONE * 1.035, 0.15).set_trans(Tween.TRANS_SINE)
		bounce.tween_property(page, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _process(delta: float) -> void:
	# 倒计时
	if _timing:
		_countdown = maxf(0.0, _countdown - delta)
		_time_bar.value = _countdown
		_time_label.text = "%02d:%02d" % [int(_countdown) / 60, int(_countdown) % 60]
		if _countdown <= 15.0:
			_time_label.add_theme_color_override("font_color", RED)
		if _countdown <= 0.0:
			_timing = false
			_on_timeout()
	# 悬停时平滑减速；固定循环周长，配对后不会突然跳位。
	if _belt_moving:
		var target_speed := _belt_speed * (0.20 if _hovered_sketch != "" or _busy else 1.0)
		_belt_velocity = move_toward(_belt_velocity, target_speed, 300.0 * delta)
		for sid in _belt_cards:
			var card: Button = _belt_cards[sid]
			card.position.y += _belt_velocity * delta
			if card.position.y > BELT_H + 24:
				card.position.y -= BELT_PITCH * _belt_cards.size()
			# 边缘淡化由 shader 逐像素处理，保留相邻卡片的可见部分。
			card.modulate.a = 0.38 if card.disabled else 1.0

# ---------- 第一关 v3：NPC 发牌 + 流水线选卡 ----------

func _setup_level1(l1: Dictionary) -> void:
	_belt_speed = l1.get("belt_speed", 120.0)
	_countdown_total = l1.get("countdown_secs", 90)

	_l1_root = Control.new()
	_l1_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_l1_root.visible = false
	add_child(_l1_root)

	# 半透明墨青面板让文字与画面层次清楚。
	_panel(_l1_root, Vector2(20, 16), Vector2(1240, 84), Color(INK, 0.90), 20)
	_panel(_l1_root, Vector2(846, 112), Vector2(344, 494), Color(INK, 0.75), 24)
	_label(_l1_root, l1.get("title", ""), Vector2(48, 28), Vector2(600, 36), 28, PAPER)
	_label(_l1_root, "象形字卡", Vector2(412, 148), Vector2(288, 34), 22, PAPER, true)
	_label(_l1_root, "寻 找 对 应 的 图 画", Vector2(848, 116), Vector2(340, 28), 18, GOLD, true)
	_panel(_l1_root, Vector2(366, 614), Vector2(530, 92), Color(INK, 0.78), 18)
	_label(_l1_root, "已识 · 六象", Vector2(380, 626), Vector2(100, 60), 18, GOLD)
	# 顶栏
	_score_label = Label.new()
	_score_label.add_theme_font_override("font", EMPHASIS_FONT)
	_score_label.add_theme_font_size_override("font_size", 30)
	_score_label.add_theme_color_override("font_color", GOLD)
	_score_label.position = Vector2(700, 27)
	_score_label.size = Vector2(160, 40)
	_l1_root.add_child(_score_label)

	_time_bar = ProgressBar.new()
	_time_bar.max_value = _countdown_total
	_time_bar.value = _countdown_total
	_time_bar.show_percentage = false
	_time_bar.position = Vector2(48, 76)
	_time_bar.size = Vector2(1008, 6)
	_time_bar.add_theme_stylebox_override("background", _style(Color(PAPER, 0.16), 3))
	_time_bar.add_theme_stylebox_override("fill", _style(GOLD, 3))
	_l1_root.add_child(_time_bar)

	_time_label = Label.new()
	_time_label.add_theme_font_size_override("font_size", 26)
	_time_label.add_theme_color_override("font_color", PAPER)
	_time_label.position = Vector2(988, 29)
	_time_label.size = Vector2(120, 32)
	_l1_root.add_child(_time_label)

	_round_label = Label.new()
	_round_label.add_theme_font_size_override("font_size", 26)
	_round_label.add_theme_color_override("font_color", PAPER)
	_round_label.position = Vector2(820, 30)
	_round_label.size = Vector2(154, 32)
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_l1_root.add_child(_round_label)

	# NPC 阿东巴（左侧，待机浮动）
	var npc := TextureRect.new()
	npc.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	npc.texture = load(_assets_dir + "npc_dongba.png")
	npc.position = Vector2(24, 152)
	npc.size = Vector2(318, 477)
	npc.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	npc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_l1_root.add_child(npc)
	var bob := create_tween().set_loops()
	bob.tween_property(npc, "position:y", 146.0, 2.0).set_trans(Tween.TRANS_SINE)
	bob.tween_property(npc, "position:y", 152.0, 2.0).set_trans(Tween.TRANS_SINE)

	# 流水线窗口（裁剪区）：右侧竖排，所有简笔画卡常在、循环下移
	_belt_root = Control.new()
	_belt_root.position = Vector2(BELT_X, BELT_Y)
	_belt_root.size = Vector2(BELT_CARD.x + 44, BELT_H)
	_belt_root.clip_contents = true
	_l1_root.add_child(_belt_root)

	# 提示语
	_hint_label = Label.new()
	_hint_label.add_theme_font_size_override("font_size", 20)
	_hint_label.add_theme_color_override("font_color", PAPER)
	_hint_label.position = Vector2(340, 565)
	_hint_label.size = Vector2(460, 36)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_l1_root.add_child(_hint_label)

	# 配对表
	for p in l1["pairs"]:
		_pair_of_glyph[p["glyph"]] = p["sketch"]
		_meaning_of_sketch[p["sketch"]] = p["meaning"]

## 开局/超时重置：洗牌、清零、建流水线、发第一张
func _start_level1() -> void:
	_round_token += 1
	_busy = false
	_hovered_sketch = ""
	_matched_sketches.clear()
	_belt_velocity = 0.0
	_score = 0
	_score_label.text = "分数 0"
	_deal_queue = _pair_of_glyph.keys()
	_deal_queue.shuffle()
	_hint_label.text = "看字形，找出右侧对应的图画"
	for mini in _matched_minis:
		mini.queue_free()
	_matched_minis.clear()
	_build_belt()
	_countdown = _countdown_total
	_time_bar.value = _countdown
	_time_label.add_theme_color_override("font_color", PAPER)
	_timing = true
	_belt_moving = true
	_deal_next()

## 建流水线：6 张简笔画卡全部常在，自上而下循环流动
func _build_belt() -> void:
	for sid in _belt_cards:
		_belt_cards[sid].queue_free()
	_belt_cards.clear()
	var sids: Array = _meaning_of_sketch.keys()
	sids.shuffle()
	for i in sids.size():
		var sid: String = sids[i]
		var card := _make_card(_assets_dir + sid + ".png", _meaning_of_sketch[sid], BELT_CARD)
		# 初始竖向铺开，逐张错开，从窗口上缘依次流入
		card.position = Vector2(22, i * BELT_PITCH - 100)
		card.pressed.connect(_on_pick.bind(sid))
		card.mouse_entered.connect(func() -> void:
			if not card.disabled:
				_hovered_sketch = sid
		)
		card.mouse_exited.connect(func() -> void:
			if _hovered_sketch == sid:
				_hovered_sketch = ""
		)
		_belt_root.add_child(card)
		var fade := ShaderMaterial.new()
		fade.shader = BELT_FADE
		fade.set_shader_parameter("belt_top", _belt_root.global_position.y)
		fade.set_shader_parameter("belt_bottom", _belt_root.global_position.y + BELT_H)
		card.material = fade
		for visual in card.get_children():
			if visual is CanvasItem:
				visual.use_parent_material = true
		_belt_cards[sid] = card

## NPC 发牌：字卡从 NPC 手中飞到中央
func _deal_next() -> void:
	if _deal_queue.is_empty():
		_level1_done()
		return
	_round_token += 1
	var token := _round_token
	_busy = true
	for sid in _belt_cards:
		if not _matched_sketches.has(sid):
			_belt_cards[sid].disabled = false
			_belt_cards[sid].modulate = Color.WHITE
	_current_glyph = _deal_queue.pop_back()
	_wrong_streak = 0
	_round_label.text = "第 %d / 6 张" % (_matched_minis.size() / 2 + 1)

	if _glyph_card != null:
		_glyph_card.queue_free()
	_glyph_card = _make_card(_assets_dir + _current_glyph + ".png", "", BIG_CARD)
	_glyph_card.position = Vector2(206, 348)   # NPC 手的位置
	_glyph_card.scale = Vector2(0.4, 0.4)
	_glyph_card.rotation = -0.16
	_glyph_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glyph_card.modulate.a = 0.0
	_l1_root.add_child(_glyph_card)
	var deal_secs: float = config["level1"].get("deal_secs", 0.5)
	_deal_tween = create_tween().set_parallel()
	var tween := _deal_tween
	tween.tween_property(_glyph_card, "position", Vector2(430, 208), deal_secs).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_glyph_card, "scale", Vector2.ONE, deal_secs).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_glyph_card, "modulate:a", 1.0, deal_secs * 0.6)
	tween.tween_property(_glyph_card, "rotation", 0.0, deal_secs).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.chain().tween_callback(func() -> void:
		if token == _round_token and _timing:
			_busy = false
	)

## 通用卡（字卡/流水线卡）：卡牌框 + 内容图 + 可选文字
## TextureRect 必须先设 expand_mode=IGNORE_SIZE 再设 texture/size（否则被原生尺寸钳制）
func _make_card(content_path: String, text: String, card_size: Vector2) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = card_size
	btn.size = card_size
	btn.focus_mode = Control.FOCUS_NONE
	btn.pivot_offset = card_size * 0.5
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		btn.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	var shadow := Panel.new()
	shadow.position = Vector2(card_size.x * 0.10, 9)
	shadow.size = Vector2(card_size.x * 0.80, card_size.y - 12)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shadow.add_theme_stylebox_override("panel", _style(Color(0.03, 0.06, 0.05, 0.30), 12))
	btn.add_child(shadow)
	var frame := TextureRect.new()
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.texture = load("res://assets/shared/frame_card.png")
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(frame)
	var content := TextureRect.new()
	content.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	content.texture = load(content_path)
	# 原图米色纸底保留；只缩小展示留白，让简笔画线条更易读。
	if content_path.get_file().begins_with("sketch_"):
		var atlas := AtlasTexture.new()
		atlas.atlas = content.texture
		var texture_size := content.texture.get_size()
		atlas.region = Rect2(texture_size * 0.14, texture_size * 0.72)
		content.texture = atlas
	var content_h := card_size.y * (0.54 if text != "" else 0.60)
	content.position = Vector2(card_size.x * 0.23, card_size.y * 0.20)
	content.size = Vector2(card_size.x * 0.54, content_h)
	content.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(content)
	if text != "":
		var label := Label.new()
		label.text = text
		label.add_theme_font_override("font", EMPHASIS_FONT)
		label.add_theme_font_size_override("font_size", 26)
		label.add_theme_color_override("font_color", INK)
		label.position = Vector2(0, card_size.y * 0.76)
		label.size = Vector2(card_size.x, 28)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(label)
	var outline := Panel.new()
	outline.position = Vector2(card_size.x * 0.10, 2)
	outline.size = Vector2(card_size.x * 0.80, card_size.y - 4)
	outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var border_style := _style(Color.TRANSPARENT, 9)
	border_style.set_border_width_all(2)
	border_style.border_color = GOLD
	outline.add_theme_stylebox_override("panel", border_style)
	outline.modulate.a = 0.0
	btn.add_child(outline)
	btn.mouse_entered.connect(func() -> void:
		if not btn.disabled:
			_hover_card(btn, frame, outline, true)
	)
	btn.mouse_exited.connect(func() -> void:
		_hover_card(btn, frame, outline, false)
	)
	return btn

## 点选流水线上的卡
func _on_pick(sid: String) -> void:
	if _busy or not _timing or _current_glyph == "" or not _belt_cards.has(sid):
		return
	if _belt_cards[sid].disabled:
		return
	var l1: Dictionary = config["level1"]
	if _pair_of_glyph.get(_current_glyph, "") == sid:
		# ---- 选对 ----
		if _feedback_tween != null and _feedback_tween.is_running():
			_feedback_tween.kill()
			_glyph_card.position = Vector2(430, 208)
			_glyph_card.rotation = 0.0
			_glyph_card.scale = Vector2.ONE
		_clear_card_feedback(_glyph_card)
		_busy = true
		var pts: int = l1.get("score_correct", 10)
		_score += pts
		_score_label.text = "分数 %d" % _score
		_score_popup("+%d" % pts, GOLD, Vector2(756, 300))
		_hint_label.text = "认出了 · " + _meaning_of_sketch[sid]
		_play_sfx("match_ok")
		_match_and_fly(sid)
	else:
		# ---- 选错：变灰，仍在流水线上流动但不可再选
		var pts: int = l1.get("score_wrong", -5)
		_score += pts
		_score_label.text = "分数 %d" % _score
		_score_popup("%d" % pts, RED, Vector2(756, 300))
		_hint_label.text = l1.get("wrong_hint", "")
		_play_sfx("match_bad")
		_hovered_sketch = ""
		_wrong_streak += 1
		if _wrong_streak >= 3:
			# 连错 3 次：正确卡金边脉冲（降级提示）
			var correct: String = _pair_of_glyph[_current_glyph]
			if _belt_cards.has(correct):
				_pulse_gold(_belt_cards[correct])
			_wrong_streak = 0
		var card: Button = _belt_cards[sid]
		card.disabled = true
		var tween := create_tween()
		tween.tween_property(card, "modulate", Color(0.60, 0.60, 0.60, 0.38), 0.25)
		if _glyph_card != null:
			_shake_card(_glyph_card)

## 配对成功：流水线上的卡摘出飞向底部已配对区变灰，字卡同飞
func _match_and_fly(sid: String) -> void:
	var token := _round_token
	var slot_idx := _matched_minis.size() / 2
	var target := Vector2(484 + slot_idx * 66, 630)
	var source: Button = _belt_cards[sid]
	_matched_sketches[sid] = true
	source.disabled = true
	source.modulate = Color(0.6, 0.6, 0.6, 0.38)
	_hovered_sketch = ""
	# 使用飞行副本，原卡继续沿固定轨道移动，不改变其他卡的间距。
	var sc := _make_card(_assets_dir + sid + ".png", "", BELT_CARD)
	_l1_root.add_child(sc)
	sc.global_position = source.global_position
	sc.disabled = true
	sc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gc := _glyph_card
	_glyph_card = null
	for card in [gc, sc]:
		if card == null:
			continue
		card.disabled = true
		card.pivot_offset = Vector2.ZERO
		var destination := target + (Vector2(7, 9) if card == sc else Vector2.ZERO)
		var tween := create_tween().set_parallel()
		tween.tween_property(card, "position", destination, 0.64).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(card, "scale", Vector2.ONE * (52.0 / BIG_CARD.x), 0.64).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(card, "rotation", -0.05 if card == gc else 0.06, 0.64)
		_matched_minis.append(card)
	await get_tree().create_timer(0.76, false).timeout
	if token != _round_token or not _timing:
		return
	_busy = false
	_deal_next()

## 超时：提示后整关重来（无限重试，不卡死）
func _on_timeout() -> void:
	_round_token += 1
	if _deal_tween != null and _deal_tween.is_running():
		_deal_tween.kill()
	_belt_moving = false
	_busy = true
	_hint_label.text = config["level1"].get("timeout_text", "时间到，再来一次")
	if _glyph_card != null:
		_glyph_card.queue_free()
		_glyph_card = null
	_current_glyph = ""
	await get_tree().create_timer(1.5, false).timeout
	_start_level1()

func _score_popup(text: String, color: Color, pos: Vector2) -> void:
	var success := text.begins_with("+")
	var popup := Control.new()
	popup.name = "ScoreFeedback"
	popup.position = pos
	popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	popup.z_index = 20
	_l1_root.add_child(popup)
	var burst := Control.new()
	burst.set_script(FEEDBACK_BURST)
	burst.set("success", success)
	burst.mouse_filter = Control.MOUSE_FILTER_IGNORE
	popup.add_child(burst)
	var sparks := create_tween()
	sparks.tween_property(burst, "progress", 1.0, 0.85).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	var caption := Label.new()
	caption.text = "认对啦！" if success else "再看一眼"
	caption.add_theme_font_override("font", EMPHASIS_FONT)
	caption.add_theme_font_size_override("font_size", 24)
	caption.add_theme_color_override("font_color", Color("#FFF2C9") if success else Color("#FFD4C4"))
	caption.add_theme_color_override("font_outline_color", INK if success else Color("#643D35"))
	caption.add_theme_constant_override("outline_size", 5)
	caption.position = Vector2(-110, -79)
	caption.size = Vector2(220, 36)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	popup.add_child(caption)

	var pop := Label.new()
	pop.text = text
	pop.name = "Points"
	pop.add_theme_font_override("font", EMPHASIS_FONT)
	pop.add_theme_font_size_override("font_size", 96 if success else 72)
	pop.add_theme_color_override("font_color", Color("#FFE296") if success else Color("#FFAA91"))
	pop.add_theme_color_override("font_outline_color", Color("#345348") if success else Color("#744439"))
	pop.add_theme_constant_override("outline_size", 9)
	pop.add_theme_color_override("font_shadow_color", Color(0.10, 0.18, 0.15, 0.5))
	pop.add_theme_constant_override("shadow_offset_x", 0)
	pop.add_theme_constant_override("shadow_offset_y", 5)
	pop.position = Vector2(-128, -50)
	pop.size = Vector2(256, 128)
	pop.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	popup.add_child(pop)
	popup.scale = Vector2.ONE * 0.35
	popup.rotation = -0.09 if success else 0.06
	var tween := create_tween().set_parallel()
	tween.tween_property(popup, "scale", Vector2.ONE, 0.38).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(popup, "rotation", 0.0, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(popup, "position:y", pos.y - 20.0, 0.88).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(popup, "modulate:a", 0.0, 0.28).set_delay(0.72)
	tween.chain().tween_callback(popup.queue_free)

func _clear_card_feedback(card: Button) -> void:
	for effect in card.get_children():
		if effect.has_meta("card_feedback"):
			effect.queue_free()

func _feedback_border(card: Button, color: Color, badge: bool = false) -> Panel:
	# 卡框的透明外边约占左右各 8.5%，反馈沿纸张轮廓对齐。
	var ring := Panel.new()
	ring.name = "CardFeedbackBorder"
	ring.set_meta("card_feedback", true)
	ring.position = Vector2(card.size.x * 0.085, card.size.y * 0.008)
	ring.size = Vector2(card.size.x * 0.83, card.size.y * 0.98)
	ring.pivot_offset = ring.size * 0.5
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.use_parent_material = true
	var style := _style(Color(color, 0.06), 14)
	style.set_border_width_all(5)
	style.border_color = color
	style.shadow_color = Color(color.darkened(0.5), 0.25)
	style.shadow_size = 5
	style.shadow_offset = Vector2(0, 3)
	ring.add_theme_stylebox_override("panel", style)
	card.add_child(ring)
	if badge:
		var bubble := Panel.new()
		bubble.position = Vector2(ring.size.x - 25, -16)
		bubble.size = Vector2(42, 42)
		bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bubble_style := _style(Color("#FFF0D5"), 21)
		bubble_style.set_border_width_all(4)
		bubble_style.border_color = color
		bubble.add_theme_stylebox_override("panel", bubble_style)
		ring.add_child(bubble)
		var mark := Label.new()
		mark.text = "!"
		mark.add_theme_font_override("font", EMPHASIS_FONT)
		mark.add_theme_font_size_override("font_size", 32)
		mark.add_theme_color_override("font_color", Color("#C15A48"))
		mark.size = bubble.size
		mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bubble.add_child(mark)
	return ring

func _shake_card(card: Button) -> void:
	if _feedback_tween != null and _feedback_tween.is_running():
		_feedback_tween.kill()
	_clear_card_feedback(card)
	card.position = Vector2(430, 208)
	card.rotation = 0.0
	card.scale = Vector2.ONE
	var ring := _feedback_border(card, Color("#EF8B73"), true)
	var pulse := create_tween().set_parallel()
	ring.scale = Vector2.ONE * 1.025
	pulse.tween_property(ring, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pulse.tween_property(ring, "modulate:a", 0.0, 0.25).set_delay(0.58)
	pulse.chain().tween_callback(ring.queue_free)
	var tween := create_tween()
	_feedback_tween = tween
	# 轻微转动配合压缩回弹；不移动对齐的红边。
	tween.tween_property(card, "rotation", -0.045, 0.07)
	tween.tween_property(card, "rotation", 0.04, 0.09)
	tween.tween_property(card, "rotation", -0.023, 0.09)
	tween.tween_property(card, "rotation", 0.0, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(card, "scale", Vector2(1.02, 0.98), 0.06)
	tween.tween_property(card, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _pulse_gold(card: Button) -> void:
	var ring := _feedback_border(card, Color("#FFE09B"))
	var tween := create_tween().set_loops(4)
	tween.tween_property(ring, "modulate:a", 0.25, 0.25)
	tween.tween_property(ring, "modulate:a", 1.0, 0.25)
	tween.finished.connect(ring.queue_free)

func _level1_done() -> void:
	if _l1_result_layer != null:
		return
	_busy = true
	_current_glyph = ""
	_timing = false
	_belt_moving = false
	_hovered_sketch = ""
	# 先完成收牌，再展开结算；这里不发碎片、不写最终通关。
	await get_tree().create_timer(0.25, false).timeout
	_show_level1_result()

func _show_level1_result() -> void:
	_l1_result_layer = CanvasLayer.new()
	_l1_result_layer.layer = 30
	add_child(_l1_result_layer)
	var viewport_size := get_viewport().get_visible_rect().size
	var overlay := Control.new()
	overlay.size = viewport_size
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_l1_result_layer.add_child(overlay)
	var dim := ColorRect.new()
	dim.color = Color(INK, 0.78)
	dim.size = viewport_size
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(dim)

	_l1_result_panel = Control.new()
	_l1_result_panel.size = Vector2(960, 560)
	_l1_result_panel.position = (viewport_size - _l1_result_panel.size) * 0.5
	_l1_result_panel.pivot_offset = _l1_result_panel.size * 0.5
	_l1_result_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(_l1_result_panel)
	var paper := TextureRect.new()
	paper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	paper.texture = load("res://assets/shared/paper_base.png")
	paper.size = _l1_result_panel.size
	paper.stretch_mode = TextureRect.STRETCH_SCALE
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_l1_result_panel.add_child(paper)
	_label(_l1_result_panel, "第一关 · 认一认", Vector2(80, 48), Vector2(800, 28), 20, INK, true)
	_label(_l1_result_panel, "六象识成！", Vector2(80, 80), Vector2(800, 60), 46, INK, true)
	_label(_l1_result_panel, "每一个字，都有了自己的模样", Vector2(80, 142), Vector2(800, 28), 21, INK, true)

	_panel(_l1_result_panel, Vector2(82, 181), Vector2(242, 76), Color(INK, 0.08), 16)
	_label(_l1_result_panel, "字画配齐", Vector2(100, 185), Vector2(206, 26), 18, INK, true)
	_label(_l1_result_panel, "%d / %d" % [_matched_sketches.size(), _pair_of_glyph.size()], Vector2(100, 209), Vector2(206, 42), 32, INK, true)
	_panel(_l1_result_panel, Vector2(636, 181), Vector2(242, 76), Color(INK, 0.08), 16)
	var used_secs := int(ceil(_countdown_total - _countdown))
	_label(_l1_result_panel, "本关用时", Vector2(654, 185), Vector2(206, 26), 18, INK, true)
	_label(_l1_result_panel, "%02d:%02d" % [used_secs / 60, used_secs % 60], Vector2(654, 209), Vector2(206, 42), 32, INK, true)
	_l1_result_score = Label.new()
	_l1_result_score.text = "0"
	_l1_result_score.position = Vector2(348, 159)
	_l1_result_score.size = Vector2(264, 90)
	_l1_result_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_l1_result_score.add_theme_font_override("font", EMPHASIS_FONT)
	_l1_result_score.add_theme_font_size_override("font_size", 78)
	_l1_result_score.add_theme_color_override("font_color", INK)
	_l1_result_score.add_theme_color_override("font_outline_color", Color("#FFF0C6"))
	_l1_result_score.add_theme_constant_override("outline_size", 5)
	_l1_result_score.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_l1_result_panel.add_child(_l1_result_score)
	_label(_l1_result_panel, "本 关 得 分", Vector2(348, 245), Vector2(264, 30), 18, INK, true)

	var pairs: Array = config["level1"]["pairs"]
	for i in pairs.size():
		var pair: Dictionary = pairs[i]
		var tile := Panel.new()
		tile.position = Vector2(82 + i * 136, 294)
		tile.size = Vector2(116, 126)
		tile.pivot_offset = tile.size * 0.5
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := _style(Color(0.99, 0.95, 0.84, 0.7), 14)
		style.set_border_width_all(2)
		style.border_color = Color(GOLD, 0.60)
		tile.add_theme_stylebox_override("panel", style)
		_l1_result_panel.add_child(tile)
		for j in 2:
			var icon := TextureRect.new()
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			var asset_id: String = pair["glyph"] if j == 0 else pair["sketch"]
			icon.texture = load(_assets_dir + asset_id + ".png")
			if j == 1:
				var atlas := AtlasTexture.new()
				atlas.atlas = icon.texture
				var texture_size := icon.texture.get_size()
				atlas.region = Rect2(texture_size * 0.14, texture_size * 0.72)
				icon.texture = atlas
			icon.position = Vector2(9 + j * 51, 18)
			icon.size = Vector2(47, 62)
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tile.add_child(icon)
		_label(tile, pair["meaning"], Vector2(0, 84), Vector2(116, 34), 26, INK, true)
		tile.modulate.a = 0.0
		tile.scale = Vector2.ONE * 0.8
		var reveal := create_tween().set_parallel()
		reveal.tween_property(tile, "modulate:a", 1.0, 0.22).set_delay(0.36 + i * 0.08)
		reveal.tween_property(tile, "scale", Vector2.ONE, 0.36).set_delay(0.36 + i * 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	_label(_l1_result_panel, "字画已相认，接下来把马帮的一天排回原序。", Vector2(80, 442), Vector2(800, 30), 21, INK, true)
	_l1_continue_btn = Button.new()
	_l1_continue_btn.text = "翻开残页 · 进入第二关"
	_l1_continue_btn.position = Vector2(320, 488)
	_l1_continue_btn.size = Vector2(320, 52)
	_l1_continue_btn.add_theme_font_size_override("font_size", 24)
	var normal := _style(INK, 16)
	normal.set_border_width_all(2)
	normal.border_color = GOLD
	normal.shadow_color = Color(INK, 0.20)
	normal.shadow_size = 4
	normal.shadow_offset = Vector2(0, 4)
	_l1_continue_btn.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("#31574A")
	_l1_continue_btn.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("#142D27")
	_l1_continue_btn.add_theme_stylebox_override("pressed", pressed)
	_l1_continue_btn.disabled = true
	_l1_continue_btn.modulate.a = 0.0
	_l1_continue_btn.pressed.connect(_continue_to_level2)
	_l1_result_panel.add_child(_l1_continue_btn)
	var exit_btn := Button.new()
	exit_btn.text = "退出"
	exit_btn.position = Vector2(viewport_size.x - 116, 16)
	exit_btn.size = Vector2(96, 48)
	exit_btn.add_theme_font_size_override("font_size", 24)
	exit_btn.pressed.connect(_exit)
	overlay.add_child(exit_btn)

	_l1_result_panel.scale = Vector2.ONE * 0.86
	_l1_result_panel.modulate.a = 0.0
	dim.modulate.a = 0.0
	var entrance := create_tween().set_parallel()
	entrance.tween_property(dim, "modulate:a", 1.0, 0.30)
	entrance.tween_property(_l1_result_panel, "modulate:a", 1.0, 0.28)
	entrance.tween_property(_l1_result_panel, "scale", Vector2.ONE, 0.48).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	entrance.tween_method(_update_result_score, 0.0, float(_score), 0.78).set_delay(0.20).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	entrance.tween_property(_l1_continue_btn, "modulate:a", 1.0, 0.25).set_delay(0.90)
	entrance.chain().tween_callback(func() -> void:
		_l1_continue_btn.disabled = false
		_l1_continue_btn.grab_focus()
	)
	for i in 3:
		var burst := Control.new()
		burst.set_script(FEEDBACK_BURST)
		burst.position = Vector2(320 + i * 160, 94)
		burst.scale = Vector2.ONE * 1.2
		burst.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_l1_result_panel.add_child(burst)
		var spark := create_tween()
		spark.tween_property(burst, "progress", 1.0, 1.05).set_delay(i * 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		spark.tween_callback(burst.queue_free)

func _update_result_score(value: float) -> void:
	if is_instance_valid(_l1_result_score):
		_l1_result_score.text = str(int(round(value)))

func _continue_to_level2() -> void:
	if _level != 1 or _transitioning or not is_instance_valid(_l1_continue_btn) or _l1_continue_btn.disabled:
		return
	_transitioning = true
	_l1_continue_btn.disabled = true
	_l1_root.visible = false
	_l2_root.visible = true
	_l2_root.modulate.a = 0.0
	_l2_root.position.y = 18
	_level = 2
	var layer := _l1_result_layer
	var transition := create_tween().set_parallel()
	transition.tween_property(_l1_result_panel, "scale", Vector2.ONE * 0.95, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	transition.tween_property(layer.get_child(0), "modulate:a", 0.0, 0.45)
	transition.tween_property(_l2_root, "modulate:a", 1.0, 0.45).set_delay(0.15)
	transition.tween_property(_l2_root, "position:y", 0.0, 0.45).set_delay(0.15).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	transition.chain().tween_callback(func() -> void:
		layer.queue_free()
		_l1_result_layer = null
		_transitioning = false
	)

# 第一关视觉组件
func _style(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	return style

func _panel(parent: Control, pos: Vector2, dimensions: Vector2, color: Color, radius: int) -> void:
	var panel := Panel.new()
	panel.position = pos
	panel.size = dimensions
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := _style(color, radius)
	style.set_border_width_all(1)
	style.border_color = Color(GOLD, 0.35)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)

func _label(parent: Control, text: String, pos: Vector2, dimensions: Vector2, font_size: int, color: Color, centered: bool = false) -> void:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.size = dimensions
	label.add_theme_font_size_override("font_size", font_size)
	if font_size >= 26:
		label.add_theme_font_override("font", EMPHASIS_FONT)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if centered:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(label)

func _hover_card(card: Button, frame: TextureRect, outline: Panel, hovered: bool) -> void:
	if card.has_meta("hover_tween"):
		var previous: Tween = card.get_meta("hover_tween")
		if previous.is_running():
			previous.kill()
	var tween := create_tween().set_parallel()
	card.set_meta("hover_tween", tween)
	tween.tween_property(frame, "modulate", Color(1.10, 1.07, 0.96) if hovered else Color.WHITE, 0.18)
	tween.tween_property(outline, "modulate:a", 1.0 if hovered else 0.0, 0.18)

# ---------- 第二关：残页归序 ----------

func _setup_level2(l2: Dictionary) -> void:
	_l2_root = Control.new()
	_l2_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_l2_root)
	_panel(_l2_root, Vector2(20, 16), Vector2(1240, 84), Color(INK, 0.90), 20)
	_label(_l2_root, l2.get("title", ""), Vector2(48, 26), Vector2(800, 40), 30, PAPER)
	_label(_l2_root, "拖动残页，按事情发生的先后放回经书", Vector2(48, 69), Vector2(840, 26), 18, Color(PAPER, 0.82))
	_placed_label = Label.new()
	_placed_label.position = Vector2(936, 29)
	_placed_label.size = Vector2(190, 36)
	_placed_label.add_theme_font_override("font", EMPHASIS_FONT)
	_placed_label.add_theme_font_size_override("font_size", 26)
	_placed_label.add_theme_color_override("font_color", GOLD)
	_l2_root.add_child(_placed_label)
	_label(_l2_root, "待 整 理 的 残 页", Vector2(52, 111), Vector2(600, 28), 18, PAPER)

	var timeline := ColorRect.new()
	timeline.color = Color(GOLD, 0.7)
	timeline.position = Vector2(192, 378)
	timeline.size = Vector2(900, 2)
	timeline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_l2_root.add_child(timeline)
	for i in 4:
		_panel(_l2_root, Vector2(170 + i * 300, 356), Vector2(44, 44), INK, 22)
		_label(_l2_root, str(i + 1), Vector2(170 + i * 300, 357), Vector2(44, 40), 27, GOLD, true)
		var slot := Panel.new()
		slot.position = Vector2(52 + i * 300, 410)
		slot.size = PAGE_SIZE
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_l2_root.add_child(slot)
		_label(slot, "放入第 %d 页" % (i + 1), Vector2(0, 74), Vector2(PAGE_SIZE.x, 34), 22, Color(PAPER, 0.70), true)
		_slots.append({"rect": slot, "page_id": "", "index": i + 1})

	var page_ids: Array = []
	var caption_of: Dictionary = {}
	for entry in l2["pages"]:
		page_ids.append(entry["id"])
		_page_correct_order[entry["id"]] = entry["order"]
		caption_of[entry["id"]] = entry.get("caption", "")
	page_ids.shuffle()
	for i in page_ids.size():
		var pid: String = page_ids[i]
		var page := TextureRect.new()
		page.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		page.texture = _page_texture(pid)
		var paper := ShaderMaterial.new()
		paper.shader = PAGE_PAPER
		page.material = paper
		page.position = Vector2(52 + i * 300, 148)
		page.size = PAGE_SIZE
		page.pivot_offset = PAGE_SIZE * 0.5
		page.stretch_mode = TextureRect.STRETCH_SCALE
		page.mouse_filter = Control.MOUSE_FILTER_STOP
		page.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		page.gui_input.connect(_on_page_gui_input.bind(page))
		page.mouse_entered.connect(_hover_page.bind(page, true))
		page.mouse_exited.connect(_hover_page.bind(page, false))
		page.set_meta("page_id", pid)
		page.set_meta("home", page.position)
		_label(page, caption_of[pid], Vector2(8, PAGE_SIZE.y - 49), Vector2(PAGE_SIZE.x - 16, 36), 22, INK, true)
		_pages[pid] = page
		_l2_root.add_child(page)

	_hint2_label = Label.new()
	_hint2_label.position = Vector2(40, 610)
	_hint2_label.size = Vector2(1200, 32)
	_hint2_label.add_theme_font_size_override("font_size", 22)
	_hint2_label.add_theme_color_override("font_color", PAPER)
	_hint2_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint2_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_l2_root.add_child(_hint2_label)
	_submit_btn = Button.new()
	_submit_btn.text = "拼合经书"
	_submit_btn.add_theme_font_size_override("font_size", 28)
	_submit_btn.position = Vector2(520, 652)
	_submit_btn.size = Vector2(240, 52)
	_submit_btn.pressed.connect(_on_submit)
	_style_story_button(_submit_btn)
	_l2_root.add_child(_submit_btn)
	_refresh_submit()

func _page_texture(pid: String) -> Texture2D:
	var texture: Texture2D = load(_assets_dir + pid + ".png")
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	var dimensions := texture.get_size()
	atlas.region = Rect2(Vector2(dimensions.x * 0.008, dimensions.y * 0.060), Vector2(dimensions.x * 0.984, dimensions.y * 0.880))
	return atlas

func _style_story_button(button: Button) -> void:
	var normal := _style(INK, 16)
	normal.set_border_width_all(2)
	normal.border_color = GOLD
	normal.shadow_color = Color(INK, 0.3)
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
	disabled.bg_color = Color(INK, 0.65)
	disabled.border_color = Color(GOLD, 0.25)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_disabled_color", Color(PAPER, 0.48))

func _hover_page(page: TextureRect, hovered: bool) -> void:
	if _drag_page != null or _finished or _transitioning:
		return
	var tween := create_tween()
	tween.tween_property(page, "modulate", Color(1.06, 1.04, 0.98) if hovered else Color.WHITE, 0.16)

func _on_page_gui_input(event: InputEvent, page: TextureRect) -> void:
	if _level != 2 or _finished or _transitioning:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_cancel_page_motion(page)
		_drag_page = page
		_drag_offset = _l2_root.get_local_mouse_position() - page.position
		page.z_index = 15
		page.rotation = 0.0
		page.scale = Vector2.ONE * 1.055
		page.modulate = Color(1.06, 1.04, 0.98)
		page.mouse_default_cursor_shape = Control.CURSOR_DRAG
		_clear_page_border(page)
		_hint2_label.text = "靠近编号槽位后松手；放到已有残页上可以交换"
		_refresh_slots(_find_drop_slot(page.position + PAGE_SIZE * 0.5))

func _input(event: InputEvent) -> void:
	# 由场景捕捉释放，拖到卡牌外也能正常放下。
	if _drag_page == null:
		return
	if event is InputEventMouseMotion:
		_drag_page.position = _l2_root.get_local_mouse_position() - _drag_offset
		_drag_page.position.x = clampf(_drag_page.position.x, 20.0, 1260.0 - PAGE_SIZE.x)
		_drag_page.position.y = clampf(_drag_page.position.y, 112.0, 610.0 - PAGE_SIZE.y)
		_refresh_slots(_find_drop_slot(_drag_page.position + PAGE_SIZE * 0.5))
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		var page := _drag_page
		_drag_page = null
		_drop_page(page)
		get_viewport().set_input_as_handled()

func _slot_of_page(pid: String) -> int:
	for i in _slots.size():
		if _slots[i]["page_id"] == pid:
			return i
	return -1

func _find_drop_slot(center: Vector2) -> int:
	for i in _slots.size():
		var rect: Control = _slots[i]["rect"]
		if Rect2(rect.position - Vector2(12, 12), rect.size + Vector2(24, 24)).has_point(center):
			return i
	return -1

func _drop_page(page: TextureRect) -> void:
	var pid: String = page.get_meta("page_id")
	var source := _slot_of_page(pid)
	var target := _find_drop_slot(page.position + PAGE_SIZE * 0.5)
	if source >= 0:
		_slots[source]["page_id"] = ""
	if target >= 0:
		var old_pid: String = _slots[target]["page_id"]
		if old_pid != "" and old_pid != pid:
			if source >= 0:
				_slots[source]["page_id"] = old_pid
				_place_page(_pages[old_pid], _slots[source]["rect"].position)
			else:
				_place_page(_pages[old_pid], _pages[old_pid].get_meta("home"))
		_slots[target]["page_id"] = pid
		_place_page(page, _slots[target]["rect"].position)
		_page_border(page, Color("#FFE09B"), 0.55)
	else:
		_place_page(page, page.get_meta("home"))
	_refresh_submit()

func _cancel_page_motion(page: TextureRect) -> void:
	if page.has_meta("motion"):
		var previous: Tween = page.get_meta("motion")
		if previous.is_running():
			previous.kill()

func _place_page(page: TextureRect, destination: Vector2) -> void:
	_cancel_page_motion(page)
	page.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	page.modulate = Color.WHITE
	var tween := create_tween().set_parallel()
	page.set_meta("motion", tween)
	tween.tween_property(page, "position", destination, 0.26).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(page, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(page, "rotation", 0.0, 0.22)
	tween.chain().tween_callback(func() -> void: page.z_index = 0)

func _refresh_slots(hovered: int = -1) -> void:
	for i in _slots.size():
		var slot: Panel = _slots[i]["rect"]
		var occupied: bool = _slots[i]["page_id"] != ""
		var style := _style(Color(INK, 0.76), 18)
		style.set_border_width_all(3 if i == hovered else 2)
		style.border_color = Color("#FFE09B") if i == hovered else Color(GOLD, 0.65 if occupied else 0.32)
		if i == hovered:
			style.bg_color = Color("#456354")
			style.shadow_color = Color(GOLD, 0.35)
			style.shadow_size = 7
		slot.add_theme_stylebox_override("panel", style)

func _refresh_submit() -> void:
	var filled := 0
	for slot in _slots:
		if slot["page_id"] != "":
			filled += 1
	_submit_btn.disabled = filled < _slots.size()
	_placed_label.text = "归位 %d / %d" % [filled, _slots.size()]
	_hint2_label.text = "残页已放齐，试着拼合经书吧" if filled == _slots.size() else "先后顺序藏在画面里 · 放好 %d / %d 页" % [filled, _slots.size()]
	_hint2_label.add_theme_color_override("font_color", PAPER)
	_refresh_slots()

func _l2_solved() -> bool:
	for slot in _slots:
		if slot["page_id"] == "" or _page_correct_order.get(slot["page_id"], -1) != slot["index"]:
			return false
	return true

func _clear_page_border(page: TextureRect) -> void:
	for child in page.get_children():
		if child.has_meta("page_feedback"):
			child.queue_free()

func _page_border(page: TextureRect, color: Color, duration: float) -> void:
	_clear_page_border(page)
	var border := Panel.new()
	border.set_meta("page_feedback", true)
	border.position = Vector2(5, 4)
	border.size = PAGE_SIZE - Vector2(10, 8)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := _style(Color(color, 0.06), 13)
	style.set_border_width_all(4)
	style.border_color = color
	style.shadow_color = Color(color, 0.3)
	style.shadow_size = 4
	border.add_theme_stylebox_override("panel", style)
	page.add_child(border)
	var tween := create_tween()
	tween.tween_interval(duration * 0.65)
	tween.tween_property(border, "modulate:a", 0.0, duration * 0.35)
	tween.tween_callback(border.queue_free)

func _on_submit() -> void:
	if _level != 2 or _finished or _drag_page != null or _submit_btn.disabled:
		return
	if _l2_solved():
		_hint2_label.text = "经书拼好了！马帮的故事又连起来了"
		_submit_btn.disabled = true
		_complete()
		return
	_fail_count += 1
	for slot in _slots:
		var pid: String = slot["page_id"]
		if _page_correct_order.get(pid, -1) == slot["index"]:
			_page_border(_pages[pid], Color("#FFE09B"), 0.8)
			continue
		var page: TextureRect = _pages[pid]
		_cancel_page_motion(page)
		_page_border(page, Color("#EF8B73"), 0.85)
		var tween := create_tween()
		page.set_meta("motion", tween)
		tween.tween_property(page, "rotation", -0.035, 0.07)
		tween.tween_property(page, "rotation", 0.035, 0.09)
		tween.tween_property(page, "rotation", -0.018, 0.09)
		tween.tween_property(page, "rotation", 0.0, 0.12)
	_hint2_label.text = config["level2"].get("wrong_hint", "")
	_hint2_label.add_theme_color_override("font_color", Color("#FFD1BC"))
	_play_sfx("match_bad")
	if _fail_count >= 3:
		var slot: Panel = _slots[0]["rect"]
		var style := _style(Color(INK, 0.82), 18)
		style.set_border_width_all(4)
		style.border_color = Color("#FFE09B")
		slot.add_theme_stylebox_override("panel", style)
		_hint2_label.text = config["level2"].get("fail3_hint", "") + " · 再看看哪一页画着日出"
		_fail_count = 0

func _show_win_placeholder(fragment_ids: Array) -> void:
	# 只替换本小游戏的最终结算，沿用基类的发放与返回接口。
	_win_layer = CanvasLayer.new()
	_win_layer.layer = 60
	add_child(_win_layer)
	var viewport_size := get_viewport().get_visible_rect().size
	var dim := ColorRect.new()
	dim.color = Color(INK, 0.82)
	dim.size = viewport_size
	_win_layer.add_child(dim)
	var card := Control.new()
	card.size = Vector2(960, 550)
	card.position = (viewport_size - card.size) * 0.5
	card.pivot_offset = card.size * 0.5
	dim.add_child(card)
	var paper := TextureRect.new()
	paper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	paper.texture = load("res://assets/shared/paper_base.png")
	paper.size = card.size
	paper.stretch_mode = TextureRect.STRETCH_SCALE
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(paper)
	_label(card, "丽江 · 东巴字卡", Vector2(60, 46), Vector2(840, 28), 20, INK, true)
	_label(card, "马帮记事理顺了！", Vector2(60, 78), Vector2(840, 60), 46, INK, true)
	_label(card, "马帮的一天，重新连成了故事", Vector2(60, 146), Vector2(840, 32), 24, INK, true)
	var ordered: Array = config["level2"]["pages"].duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["order"] < b["order"])
	for i in ordered.size():
		var page := TextureRect.new()
		page.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		page.texture = _page_texture(ordered[i]["id"])
		var paper_material := ShaderMaterial.new()
		paper_material.shader = PAGE_PAPER
		page.material = paper_material
		page.position = Vector2(66 + i * 212, 206)
		page.size = Vector2(192, 130)
		page.stretch_mode = TextureRect.STRETCH_SCALE
		page.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(page)
		_label(card, ["日出启程", "翻越山岭", "渡过河流", "夜宿煮茶"][i], Vector2(66 + i * 212, 346), Vector2(192, 32), 23, INK, true)
	_label(card, "获得 · 东巴茶经碎片" if not fragment_ids.is_empty() else "残页归序完成", Vector2(80, 408), Vector2(800, 38), 28, INK, true)
	var button := Button.new()
	button.text = "请阿东巴核对 · 返回院中" if SceneRouter.params.get("defer_reward", false) else "带上碎片 · 返回地图"
	button.position = Vector2(320, 474)
	button.size = Vector2(320, 54)
	button.add_theme_font_size_override("font_size", 25)
	_style_story_button(button)
	button.pressed.connect(func() -> void:
		puzzle_completed.emit(station_id, fragment_ids)
		_back_to_map()
	)
	card.add_child(button)
	card.scale = Vector2.ONE * 0.88
	card.modulate.a = 0.0
	var tween := create_tween().set_parallel()
	tween.tween_property(card, "modulate:a", 1.0, 0.28)
	tween.tween_property(card, "scale", Vector2.ONE, 0.46).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
