extends Node
## 使用独立存档，通过真实鼠标与通关奖励验证总览的进度/选中分离。
var failures := 0
var checks := 0
var page: Control
const OUT := "res://../drafts/journey-states-20261014/screenshots/"

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", message)

func frames() -> void:
	for i in 5: await get_tree().process_frame

func click(control: Control) -> void:
	var at := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	get_viewport().push_input(motion, true)
	await get_tree().process_frame
	var event := InputEventMouseButton.new()
	event.position = at
	event.global_position = at
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	get_viewport().push_input(event, true)
	await get_tree().process_frame
	event.pressed = false
	get_viewport().push_input(event, true)
	await frames()

func open_page() -> void:
	if is_instance_valid(page):
		page.queue_free()
		await frames()
	page = load("res://scenes/MapScene.tscn").instantiate()
	add_child(page)
	await frames()
	await get_tree().create_timer(0.3).timeout

func shot(name: String) -> void:
	bounds()
	if not OS.get_cmdline_user_args().has("--screenshots"): return
	RenderingServer.force_draw()
	var dir := ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(dir)
	check(get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png")) == OK, "截图 " + name)

func bounds() -> void:
	var viewport := get_viewport().get_visible_rect()
	check(viewport.encloses(page._detail.get_parent().get_global_rect()), "详情卡完整位于窗口内")
	for i in page._canvas._markers.size():
		check(page._canvas.get_global_rect().encloses(page._canvas._badges[i].get_global_rect()), "站点状态不超出长卷 " + str(i))
	var button: Button = page._detail.get_child(-1)
	check(button.get_global_rect().end.y <= viewport.end.y, "操作按钮不超出窗口")
	check(viewport.encloses(page._progress.get_global_rect()), "底部进度完整位于窗口内")

func _ready() -> void:
	var real_path: String = GameState.save_path
	var real_hash := FileAccess.get_sha256(real_path) if FileAccess.file_exists(real_path) else ""
	GameState.save_path = "user://journey-states-test.cfg"
	GameState.reset_game()
	await open_page()
	check(page._selected == "lijiang" and page._detail.get_child(-1).text == "继续丽江", "新档引导首站并显示继续")
	check(page._canvas._markers[0].get_meta("journey_state") == "active" and page._canvas._markers[1].get_meta("journey_state") == "locked", "新档首站高亮其余锁定")
	await shot("01-new-journey")
	await click(page._canvas._markers[2])
	check(page._selected == "dali" and page._detail.get_child(-1).disabled and page._detail.get_child(-1).text == "尚未解锁", "真实鼠标可预览暗牌且入口禁用")
	check(page._canvas._markers[0].get_theme_stylebox("normal").region_rect == UiKit.surface("gold").region_rect and page._canvas._markers[2].get_theme_stylebox("normal").region_rect == UiKit.surface("wood").region_rect, "预览锁定站不改变金牌归属")
	await click(page._detail.get_child(-1))
	check(GameState.current_station.is_empty() and not SceneRouter.is_switching(), "点击禁用入口不进入不写当前站")
	await shot("02-locked-preview")
	GameState.enter_station("lijiang")
	GameState.collect_fragment("frag_dongba_tea")
	await frames()
	check(page._selected == "xianggelila" and page._detail.get_child(-1).text == "继续香格里拉", "真实通关奖励自动引导下一站")
	check(page._canvas._badges[1].get_child(0).text == "● 下一站", "留在上一站时新站标记下一站")
	await shot("03-next-station")
	await click(page._canvas._markers[0])
	check(page._selected == "lijiang" and page._detail.get_child(-1).text == "重回丽江" and not page._detail.get_child(-1).disabled, "已走过的站显示可用重回入口")
	check(page._canvas._markers[1].get_theme_stylebox("normal").region_rect == UiKit.surface("gold").region_rect and page._canvas._markers[0].get_theme_stylebox("normal").region_rect == UiKit.surface("wood").region_rect, "查看旧站保持下一站金牌与旧站木牌")
	await shot("04-return-preview")
	# 回看已完成城市后重新打开总览，仍优先引导待推进站。
	await open_page()
	check(page._selected == "xianggelila", "总览重新打开优先选择未完成站")
	GameState.enter_station("xianggelila")
	await open_page()
	check(page._canvas._badges[1].get_child(0).text == "● 正在进行", "正在探索的站标记正在进行")
	await shot("05-in-progress")
	GameState.collect_fragment("frag_dye_five")
	GameState.collect_fragment("frag_zharan_pattern")
	GameState.collect_fragment("frag_beiye_oath")
	await frames()
	check(page._selected == "gucheng" and page._detail.get_child(-1).text == "继续古城集场", "四枚信物齐全引导最终站")
	await shot("06-final-station")
	GameState.enter_station("gucheng")
	GameState.complete_station("gucheng")
	await frames()
	check(page._detail.get_child(-1).text == "重回古城集场" and not page._detail.get_child(-1).disabled, "旅程全部完成后最终站可重回")
	check(page._progress.text.begins_with("已走过 5 / 5 站"), "底部旅程完成数正确")
	for b in page._canvas._markers:
		check(b.get_meta("journey_state") == "completed", "全部完成后没有残留进行中金牌")
	await shot("07-completed")
	GameState.reset_game()
	await frames()
	check(page._selected == "lijiang" and page._canvas._markers[1].get_meta("journey_state") == "locked", "进度重置时页面恢复首站和锁定状态")
	GameState.save_path = real_path
	GameState.load_game()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://journey-states-test.cfg"))
	check(real_hash == (FileAccess.get_sha256(real_path) if FileAccess.file_exists(real_path) else ""), "玩家真实存档内容未改动")
	print("JOURNEY STATES CHECKS: ", checks, " FAILURES: ", failures)
	get_tree().quit(failures)
