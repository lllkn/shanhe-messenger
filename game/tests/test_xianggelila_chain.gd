extends Node
var failures := 0
var checks := 0
var original_save := ""
func check(ok: bool, message: String) -> void:
	checks += 1
	print("PASS: " if ok else "FAIL: ", message)
	if not ok: failures += 1
func settle() -> void:
	await get_tree().process_frame
	while SceneRouter.is_switching(): await get_tree().process_frame
	await get_tree().process_frame
func physics(frames: int = 4) -> void:
	for i in frames: await get_tree().physics_frame
func key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
func mouse_motion(relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.relative = relative
	event.screen_relative = relative
	get_viewport().push_input(event, true)
func mouse_captured(city: Node3D) -> bool:
	# Dummy DisplayServer没有原生鼠标捕获，窗口版本另验证实际模式。
	return city.mouse_look and city.window_focused and (DisplayServer.get_name() == "headless" or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)
func city_ready() -> Node3D:
	await settle()
	var city := get_tree().current_scene
	while not city.walk_guide.ready: await get_tree().physics_frame
	await get_tree().process_frame
	return city
func finish_talk(city: Node3D) -> void:
	var guard := 0
	while city.dialogue != null and guard < 200:
		city.dialogue._continue()
		guard += 1
	await get_tree().process_frame
	if is_instance_valid(city) and city.reward_panel is ClueCard:
		city.reward_panel.close_button.pressed.emit()
		for frame_index in 4: await get_tree().process_frame
		if city.dialogue != null: await finish_talk(city)

func teleport(city: Node3D, pos: Vector3) -> void:
	city.player.position = pos + Vector3(0, 0.1, 0)
	city.player.velocity = Vector3.ZERO
	await physics(8)
func walk(city: Node3D, target: Vector3, message: String) -> void:
	var route: PackedVector3Array = city.walk_guide.path(city.player.position, target)
	check(not route.is_empty(), message + " 有物理可达引导路径")
	var stuck := false
	var start_time := Time.get_ticks_msec()
	key(KEY_W, true)
	for point in route:
		var frames := 0
		while Vector2(city.player.position.x - point.x, city.player.position.z - point.z).length() > 0.22 and frames < 100:
			var direction: Vector3 = point - city.player.position
			city.yaw = atan2(-direction.x, -direction.z)
			await get_tree().physics_frame
			frames += 1
		if frames >= 100:
			printerr("STUCK ", message, " at ", city.player.position, " wanted ", point)
			stuck = true
			break
	key(KEY_W, false)
	await physics(3)
	check(not stuck and city.player.position.distance_to(target) < 1.5, message + " 真实WASD连续步行抵达")
	print("WALK elapsed_ms=", Time.get_ticks_msec() - start_time, " points=", route.size())
func point_for(city: Node3D, id: String) -> Dictionary:
	for item in city.hotspots:
		if item["id"] == id: return item
	return {}

func pointer(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = position
	get_viewport().push_input(event,true)

func motion_to(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	get_viewport().push_input(event,true)

func fill_point(puzzle: Control, id: String) -> Vector2:
	var poly: Polygon2D = puzzle._region_nodes[id]
	var min_x := INF
	var min_y := INF
	var max_x := -INF
	var max_y := -INF
	for p in poly.polygon:
		min_x = minf(min_x,p.x)
		min_y = minf(min_y,p.y)
		max_x = maxf(max_x,p.x)
		max_y = maxf(max_y,p.y)
	for y in range(int(min_y),int(max_y)+1,2):
		for x in range(int(min_x),int(max_x)+1,2):
			var pos := Vector2(x+0.5,y+0.5)
			if puzzle._hit_region(pos) == id: return pos
	return Vector2(-1,-1)

func _ready() -> void:
	get_tree().current_scene = null
	original_save = GameState.save_path
	_watchdog()
	GameState.save_path = "user://xianggelila-chain-test.cfg"
	GameState.reset_game()
	GameState.collect_fragment("frag_dongba_tea")
	SceneRouter.goto_station("xianggelila")
	var city := await city_ready()
	await physics(25)
	check(city.player.is_on_floor(),"月光广场出生点落地")
	check(city.dialogue != null and city.dialogue.dialogue_id == "xianggelila_arrival","开局自动播放已确认四句旁白")
	check(city.dialogue.lines.size() == 4 and city.dialogue.lines[0]["copy_id"] == "A01","开场编号与确认稿一致")
	check(city.dialogue._name_chip.visible and city.dialogue._name_label.text == "旁白","旁白姓名卡存在")
	check(city.dialogue._text_label.get_theme_font_size("normal_font_size") == 36,"正文36字号")
	check(not city.player.enabled and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,"开场冻结移动并释放光标")
	city.dialogue.find_children("*","Button",true,false)[0].grab_focus()
	key(KEY_SPACE,true)
	await get_tree().process_frame
	key(KEY_SPACE,false)
	await get_tree().process_frame
	check(not city.dialogue._typing and city.dialogue.line_idx == 0,"按钮有焦点时空格仍补全文字")
	city.dialogue._leave()
	await get_tree().process_frame
	check(not city.done("arrival") and city.player.enabled,"开场中断不推进")
	city.interact()
	await finish_talk(city)
	check(city.done("arrival") and city.clue_count() == 0,"完成四句开场后认领任务")
	city._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)
	await get_tree().process_frame
	check(mouse_captured(city),"探索捕获鼠标")
	var yaw_before: float = city.yaw
	mouse_motion(Vector2(50,20))
	check(is_equal_approx(city.yaw, yaw_before - 0.15 * GameSettings.camera_sensitivity),"不按鼠标键也能转视角")
	key(KEY_TAB,true)
	key(KEY_TAB,false)
	await get_tree().process_frame
	check(not city.mouse_look and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,"Tab显示光标")
	yaw_before = city.yaw
	mouse_motion(Vector2(50,20))
	check(is_equal_approx(yaw_before,city.yaw),"光标操作不会转镜头")
	city.checklist.get_child(0).grab_focus()
	key(KEY_TAB,true)
	key(KEY_TAB,false)
	await get_tree().process_frame
	check(mouse_captured(city),"按钮焦点不吃掉Tab")
	GameUI.open_pause()
	var stopped: Vector3 = city.player.position
	await get_tree().create_timer(0.12).timeout
	check(get_tree().paused and city.player.position == stopped and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,"暂停冻结玩家且释放光标")
	GameUI.close_modal()
	await physics(3)
	check(mouse_captured(city),"关闭暂停恢复探索输入")
	city._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	yaw_before = city.yaw
	mouse_motion(Vector2(50,20))
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and is_equal_approx(yaw_before,city.yaw),"窗口失焦释放光标并停转镜头")
	city._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)
	key(KEY_TAB,true)
	await get_tree().process_frame
	key(KEY_TAB,false)
	await physics(3)
	key(KEY_R,true)
	await get_tree().process_frame
	key(KEY_R,false)
	await physics(3)
	check(is_equal_approx(city.pitch,0.70) and city.distance == 12 and city.camera.fov == 50,"本城斜俯视与镜头配置生效")
	check(city.camera.position.distance_to(city.player.position+Vector3(0,0.8,0)) > 11,"出生镜头不被后墙挤近")
	check(city.hotspots.size() == 4 and city.minimap.floor_texture != null,"本城四位人物与物理小地图存在")
	check(city.guide_mesh.mesh.get_surface_count() == 1 and city.guide_path.size() > 1,"金色方向箭头有真实路径")
	if OS.get_environment("XIANGGELILA_INPUT_ONLY") == "1":
		_restore_save()
		print("CAMERA_VALUES yaw=",city.yaw," pitch=",city.pitch," distance=",city.distance," fov=",city.camera.fov)
		print("XIANGGELILA_INPUT_TEST checks=",checks," failures=",failures," renderer=",DisplayServer.get_name())
		get_tree().quit(failures)
		return
	# 提前拜访不绕过走访条件。
	await teleport(city,city.goal_position+Vector3(-1.3,0,0))
	city.interact()
	check(city.dialogue != null and city.dialogue.dialogue_id == "xianggelila_danzeng_locked","提前到染坊只播放门口提示")
	await finish_talk(city)
	check(not city.done("visit") and SceneRouter.current_key == "city","提前拜访不推进或开小游戏")
	await teleport(city,city.spawn_position)
	for id in ["cloth","visitor","son"]:
		var item := point_for(city,id)
		await walk(city,item["position"],"上一点 → "+item["name"])
		check(city.near_hotspot().get("id","") == id,item["name"]+" 连续步行后可交互")
		await get_tree().process_frame
		check(city.interaction_prompt.visible and city.interaction_text.text == "E 对话",item["name"]+" 人物旁E提示")
		check(city.interaction_prompt.size.y < 61,"交互提示横排")
		city.interact()
		check(city.dialogue != null and city.dialogue.dialogue_id == item["dialogue"],"读取本城已确定访谈 "+id)
		if city.dialogue == null:
			get_tree().quit(1)
			return
		if id == "cloth":
			city.dialogue._continue()
			city.dialogue._leave()
			await get_tree().process_frame
			check(city.clue_count() == 0,"访谈中断不计线索")
			city.interact()
		await finish_talk(city)
		var count: int = city.clue_count()
		check(GameState.has_flag("clue/xianggelila/"+id),"完整访谈才记录 "+id)
		city.interact()
		check(city.dialogue.dialogue_id == item["repeat"],"已走访显示已确定重复短句 "+id)
		await finish_talk(city)
		check(city.clue_count() == count,"重温不重复计数 "+id)
	check(city.clue_count() == 3 and city.done("interviews") and city.target_id == "danzeng","三处完成自动指向丹增")
	check(point_for(city,"son")["label"].text.contains("丹增的儿子"),"儿子身份在交谈后揭晓")
	GameState.load_game()
	check(city.clue_count() == 3,"存档重载保留走访")
	await walk(city,city.goal_position,"民居巷 → 丹增染坊")
	city.interact()
	check(city.dialogue != null and city.dialogue.lines.size() == 22,"坊门两句与核心20句完整接入")
	city.dialogue._leave()
	await get_tree().process_frame
	check(not city.done("visit") and SceneRouter.current_key == "city","核心中断不进入小游戏")
	var location: Vector3 = city.player.position
	var saved_yaw: float = city.yaw
	var saved_pitch: float = city.pitch
	var saved_distance: float = city.distance
	city.interact()
	await finish_talk(city)
	await settle()
	var puzzle: Control = get_tree().current_scene
	check(SceneRouter.current_key == "puzzle_dye" and SceneRouter.params.get("flow_step") == "dye" and SceneRouter.params.get("defer_reward",false),"核心结束自动进入原dye小游戏并延后领奖")
	puzzle._exit()
	city = await city_ready()
	check(city.player.position.distance_to(location)<0.3 and absf(city.yaw-saved_yaw)<0.01 and absf(city.pitch-saved_pitch)<0.01 and city.distance == saved_distance,"退出小游戏返回原位置与完整视角")
	check(not city.done("dye") and not GameState.has_fragment("frag_dye_five"),"中途退出不记过关不发碎片")
	city.interact()
	check(city.dialogue != null and city.dialogue.dialogue_id == "xianggelila_retry","小游戏退出后先播放已确认重试短句")
	await finish_talk(city)
	await settle()
	puzzle = get_tree().current_scene
	check(not puzzle._started and puzzle._intro_layer != null and puzzle._start_button.size.x >= 440 and puzzle._start_button.size.y >= 84,"开始页明确未开始，开始按钮至少440×84")
	var first_pos: Vector2 = puzzle._pattern_root.global_position+fill_point(puzzle,puzzle._region_order[0])
	pointer(first_pos,true)
	pointer(first_pos,false)
	key(KEY_2,true)
	await get_tree().process_frame
	key(KEY_2,false)
	check(not puzzle._started and puzzle._filled.is_empty() and puzzle._selected_no == 1,"未开始时棋盘点击和数字键不操作游戏")
	var begin_pos: Vector2 = puzzle._start_button.global_position+puzzle._start_button.size*0.5
	pointer(begin_pos,true)
	await get_tree().process_frame
	pointer(begin_pos,false)
	await get_tree().process_frame
	check(puzzle._started and puzzle._level == 1,"真实开始补锦第一关")
	check(not is_instance_valid(puzzle._intro_layer),"开始点击后移除准备遮罩并露出可操作棋盘")
	# 每一块找实际可点击区域，再经真实鼠标事件填色；不注入通关状态。
	for id in puzzle._region_order:
		var pos := fill_point(puzzle,id)
		check(pos.x >= 0,"纹样区块可点击 "+id)
		var no: int = puzzle._region_no[id]
		key(KEY_1+no-1,true)
		await get_tree().process_frame
		key(KEY_1+no-1,false)
		await get_tree().process_frame
		if id == puzzle._region_order[0]:
			check(puzzle._selected_hint.text.contains("已选 %d 号" % no) and (puzzle._chip_nodes[no].get_meta("mark") as Label).visible,"选色常驻文字与已选标记一致")
			var target_line: Line2D = puzzle._region_outlines[id]
			check(target_line.default_color == puzzle.GOLD and target_line.width >= 3.4,"对应色号的未填区块描金加粗")
			var selected_text: String = puzzle._selected_hint.text
			motion_to(puzzle._pattern_root.global_position+pos)
			await get_tree().create_timer(0.25).timeout
			motion_to(Vector2(690,500))
			await get_tree().process_frame
			check(puzzle._selected_hint.text == selected_text and target_line.default_color == puzzle.GOLD,"悬停提示不覆盖选色卡，移开仍保留对应高亮")
		var screen_pos: Vector2 = puzzle._pattern_root.global_position+pos
		pointer(screen_pos,true)
		pointer(screen_pos,false)
		await get_tree().process_frame
		check(puzzle._filled.has(id),"真实选色点击填入 "+id)
		if id == puzzle._region_order[0]:
			var undo_event := InputEventKey.new()
			undo_event.keycode=KEY_Z
			undo_event.physical_keycode=KEY_Z
			undo_event.ctrl_pressed=true
			undo_event.pressed=true
			Input.parse_input_event(undo_event)
			await get_tree().process_frame
			key(KEY_Z,false)
			await get_tree().process_frame
			check(not puzzle._filled.has(id),"Ctrl+Z撤销真实补色")
			pointer(screen_pos,true)
			pointer(screen_pos,false)
			await get_tree().process_frame
	await get_tree().create_timer(1.7).timeout
	check(puzzle._l1_done and puzzle._filled.size() == 38 and not GameState.has_fragment("frag_dye_five"),"38块实际填色完成且不领奖")
	var next_pos: Vector2 = puzzle._action_button.global_position+puzzle._action_button.size*0.5
	pointer(next_pos,true)
	await get_tree().process_frame
	pointer(next_pos,false)
	await get_tree().process_frame
	check(puzzle._level == 2,"进入原染缸第二关")
	await get_tree().create_timer(0.5).timeout
	motion_to(Vector2(760,430))
	await get_tree().process_frame
	var material_prompt: String = puzzle._speech.get("_last_text")
	var red_card: Control = puzzle._lot_cards["dye_madder"]
	var blue_card: Control = puzzle._lot_cards["dye_indigo"]
	motion_to(red_card.global_position+red_card.size*0.5)
	await get_tree().create_timer(0.6).timeout
	check(puzzle._speech.get("_last_text") == material_prompt,"染料卡停留不足1秒不切换NPC对白")
	motion_to(blue_card.global_position+blue_card.size*0.5)
	await get_tree().create_timer(0.6).timeout
	motion_to(red_card.global_position+red_card.size*0.5)
	await get_tree().create_timer(0.6).timeout
	check(puzzle._speech.get("_last_text") == material_prompt,"快速换卡和移回重新计时，不累加旧停留")
	await get_tree().create_timer(0.55).timeout
	check(puzzle._speech.get("_last_text") == "%s染赤色。" % puzzle._material_name_of_color["赤"],"同一染料卡持续超过1秒才切换对应提示")
	motion_to(Vector2(760,430))
	await get_tree().create_timer(0.5).timeout
	check(puzzle._speech.get("_last_text") != material_prompt,"移出卡片不立即反复切回口诀")
	await get_tree().create_timer(0.65).timeout
	check(puzzle._speech.get("_last_text") == material_prompt,"移出超过1秒后恢复当前下料提示")
	# 实际拖入错误色料，验证可重试。
	var wrong_card: Control = puzzle._lot_cards["dye_madder"]
	pointer(wrong_card.global_position+wrong_card.size*0.5,true)
	await get_tree().process_frame
	motion_to(puzzle._vat_root.global_position+puzzle._vat_root.size*0.5)
	pointer(puzzle._vat_root.global_position+puzzle._vat_root.size*0.5,false)
	await get_tree().create_timer(1.4).timeout
	check(puzzle._step == 0 and puzzle._phase == "idle","错料不推进，可重新下料")
	for color in puzzle._order:
		var card: Control = puzzle._lot_cards[puzzle._material_of_color[color]]
		pointer(card.global_position+card.size*0.5,true)
		await get_tree().process_frame
		motion_to(puzzle._vat_root.global_position+puzzle._vat_root.size*0.5)
		pointer(puzzle._vat_root.global_position+puzzle._vat_root.size*0.5,false)
		var guard := 0
		while puzzle._phase != "stir" and guard < 180:
			await get_tree().process_frame
			guard += 1
		check(puzzle._phase == "stir","真实拖入色料后看火并进入搅缸 "+color)
		if puzzle._phase != "stir":
			_restore_save()
			get_tree().quit(1)
			return
		if color == "青":
			await get_tree().create_timer(4.2).timeout
			await get_tree().create_timer(1.4).timeout
			check(puzzle._phase == "retry" and puzzle._step == 0,"搅缸超时只重试本轮")
			puzzle._action_button.pressed.emit()
		var center: Vector2 = puzzle._water_center()
		var radius: Vector2 = puzzle._water.size*Vector2(0.32,0.32)
		pointer(center+radius*Vector2(1,0),true)
		var current_step: int = puzzle._step
		for j in 145:
			var angle: float = float(j)*TAU/64.0
			motion_to(center+radius*Vector2(cos(angle),sin(angle)))
			await get_tree().process_frame
			if puzzle._step > current_step: break
		pointer(center,false)
		check(puzzle._step == current_step+1,"真实按住水面画圈完成 "+color)
		if color != "黑": await get_tree().create_timer(0.7).timeout
	await get_tree().create_timer(3.0).timeout
	check(SceneRouter.current_key == "puzzle_dye" and is_instance_valid(puzzle._settlement_continue) and puzzle._settlement_continue.is_visible_in_tree(),"真实完成两关后显示独立胜利结算，等待确认")
	var win_labels: Array[Node] = puzzle._win_layer.find_children("*","Label",true,false)
	var summary_seen := false
	for label in win_labels:
		if label.text.contains("38 / 38") and label.text.contains("5 / 5"): summary_seen=true
	check(summary_seen and GameState.has_flag("flow/xianggelila/dye"),"结算展示实际两关成果，保留dye步骤ID")
	GameUI.open_pause()
	await get_tree().process_frame
	check(get_tree().paused and SceneRouter.current_key == "puzzle_dye","胜利结算可暂停且不触发回城")
	GameUI.close_modal()
	await get_tree().process_frame
	check(not get_tree().paused and puzzle._settlement_continue.is_visible_in_tree(),"恢复暂停仍停留同一结算页")
	await get_tree().create_timer(3.0).timeout
	key(KEY_SPACE,true)
	await get_tree().process_frame
	key(KEY_SPACE,false)
	check(SceneRouter.current_key == "puzzle_dye" and not puzzle._exiting,"结算停留且未聚焦的空格不误触回城")
	check(not GameState.has_fragment("frag_dye_five") and not GameState.is_unlocked("dali"),"收尾前不发碎片、不解锁大理")
	var confirm_pos: Vector2 = puzzle._settlement_continue.global_position+puzzle._settlement_continue.size*0.5
	pointer(confirm_pos,true)
	await get_tree().process_frame
	pointer(confirm_pos,false)
	city = await city_ready()
	check(city.dialogue != null and city.dialogue.dialogue_id == "xianggelila_danzeng_farewell","点击结算确认后才回城接丹增收尾")
	check(city.player.position.distance_to(location)<0.3 and absf(city.yaw-saved_yaw)<0.01,"通关后位置视角保留")
	city.dialogue._leave()
	await get_tree().process_frame
	check(city.done("dye") and not city.done("farewell") and not GameState.has_fragment("frag_dye_five"),"收尾中断保留过关成果但不领奖")
	SceneRouter.goto_map()
	await settle()
	SceneRouter.goto_station("xianggelila")
	city = await city_ready()
	check(city.dialogue != null and city.dialogue.dialogue_id == "xianggelila_danzeng_farewell","存档返回自动恢复未完成收尾")
	await finish_talk(city)
	check(GameState.has_fragment("frag_dye_five") and GameState.is_completed("xianggelila") and GameState.is_unlocked("dali"),"完整收尾才领取原碎片并解锁大理")
	check(city.reward_panel != null,"收尾后显示染坊手记")
	var labels: Array[Node] = city.reward_panel.find_children("*","Label",true,false)
	var reward_seen := false
	var white_seen := false
	for label in labels:
		if label.text == "获得「五色锦纹碎片」· 已放入行囊": reward_seen=true
		if label.text.contains("白 · 西方") and label.text.contains("练白"): white_seen=true
	check(reward_seen and white_seen,"领奖页名称与练白表述正确")
	city.reward_panel.find_children("*","Button",true,false)[0].pressed.emit()
	await get_tree().process_frame
	check(city.reward_panel.find_children("*","Button",true,false).size() == 3,"手记后提供继续探索、去下一个地方、返回旅途长卷")
	city.reward_panel.find_children("*","Button",true,false)[0].pressed.emit()
	await get_tree().process_frame
	var fragments: int = GameState.get_fragment_count()
	SceneRouter.goto_codex()
	await settle()
	get_tree().current_scene._back()
	city = await city_ready()
	check(city.dialogue == null and GameState.get_fragment_count()==fragments,"图鉴往返不重复开场或发奖")
	# 两座真实模型桥都用连续步行跨越，台阶/桥头/水域分别验证。
	for bridge in city.story["bridges"]:
		var middle: Vector3 = city.bridge_center(bridge)
		var v: Array = bridge["across"]
		var across := Vector3(v[0],v[1],v[2]).normalized()
		await teleport(city,middle-across*2.5)
		var route: PackedVector3Array = city.walk_guide.path(city.player.position,middle+across*2.5)
		var crosses := false
		for point in route:
			if Vector2(point.x-middle.x,point.z-middle.z).length()<1.2: crosses = true
		check(crosses,"路线实际经过本桥 "+bridge["id"])
		await walk(city,middle+across*2.5,"跨桥 "+bridge["id"])
	var river_mid := Vector3(-30.5,-0.4,2)
	await teleport(city,river_mid+Vector3(2.1,0,0))
	city.yaw=PI*0.5
	key(KEY_W,true)
	key(KEY_SPACE,true)
	await physics(85)
	key(KEY_W,false)
	key(KEY_SPACE,false)
	await get_tree().process_frame
	check(city.player.position.x > river_mid.x+0.7,"非桥溪水持续前行与跳跃不能横穿")
	await teleport(city,Vector3(-15.5,0,-12.6))
	var wall_ray := PhysicsRayQueryParameters3D.create(Vector3(-15.5,1,-12.6),Vector3(-11,1,-12.6),1)
	var wall_hit := city.get_world_3d().direct_space_state.intersect_ray(wall_ray)
	city.yaw=-PI*0.5
	key(KEY_W,true)
	await physics(42)
	key(KEY_W,false)
	print("WALL_STOP position=",city.player.position)
	var body_point: Vector3 = city.player.position+Vector3.UP
	check(not wall_hit.is_empty() and (body_point-wall_hit.position).dot(wall_hit.normal)>0.25,"布料店墙体不能穿透")
	await teleport(city,Vector3(-13,0,-11.7))
	check(city.near_hotspot().get("id","") != "cloth","近距离隔店墙不能交谈")
	await get_tree().process_frame
	check(not city.interaction_prompt.visible,"隔墙不显示E提示")
	for angle in [0.0,1.3,3.14,-1.2]:
		city.yaw=angle
		city.camera_initialized=false
		city._update_camera()
		var query := PhysicsShapeQueryParameters3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius=0.18
		query.shape=sphere
		query.collision_mask=4
		query.transform=Transform3D(Basis.IDENTITY,city.camera.position)
		var camera_hits := city.get_world_3d().direct_space_state.intersect_shape(query)
		if not camera_hits.is_empty(): print("CAMERA_OVERLAP ",angle," at=",city.camera.position," player=",city.player.position," hits=",camera_hits)
		check(camera_hits.is_empty(),"镜头球形避墙 "+str(angle))
	# 非推荐顺序再次实走，确保不依赖示例路线或已记标记。
	GameState.reset_game()
	GameState.collect_fragment("frag_dongba_tea")
	SceneRouter.goto_station("xianggelila")
	city = await city_ready()
	await finish_talk(city)
	for id in ["son","visitor","cloth"]:
		var item := point_for(city,id)
		await walk(city,item["position"],"自由顺序 → "+id)
		city.interact()
		await finish_talk(city)
	check(city.clue_count()==3 and city.target_id == "danzeng","反向自由顺序完成同一链路")
	GameState.collect_fragment("frag_dye_five")
	SceneRouter.goto_station("xianggelila")
	city = await city_ready()
	check(city.dialogue == null and city.reward_panel == null and GameState.get_fragment_count()==2,"已有碎片的旧完成档不重放、不重发")
	_restore_save()
	print("XIANGGELILA_CHAIN_TEST checks=",checks," failures=",failures)
	get_tree().quit(failures)

func _restore_save() -> void:
	GameState.save_path=original_save
	GameState.load_game()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://xianggelila-chain-test.cfg"))

func _watchdog() -> void:
	await get_tree().create_timer(300.0).timeout
	printerr("FAIL: 香格里拉测试超时")
	_restore_save()
	get_tree().quit(1)
