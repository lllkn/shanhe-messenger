extends Node
var failures := 0
var checks := 0
var actual_save := ""
var output := ""

func check(ok: bool, message: String) -> void:
	checks += 1
	print("PASS: " if ok else "FAIL: ",message)
	if not ok: failures += 1

func settle() -> void:
	await get_tree().process_frame
	while SceneRouter.is_switching(): await get_tree().process_frame
	await get_tree().process_frame

func physics(count: int = 3) -> void:
	for i in count: await get_tree().physics_frame

func ready_city() -> Node3D:
	await settle()
	var city := get_tree().current_scene
	while not city.walk_guide.ready: await physics(1)
	# 城市建完路径后仍等待路由淡出，随后才自动开启到达/收尾对话。
	for i in 4: await get_tree().process_frame
	return city

func key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func motion(pos: Vector2, relative: Vector2 = Vector2.ZERO, dragging: bool = false) -> void:
	var event := InputEventMouseMotion.new()
	event.position = pos
	event.relative = relative
	event.screen_relative = relative
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if dragging else 0
	get_viewport().push_input(event,true)

func mouse(pos: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = pos
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	get_viewport().push_input(event,true)

func click(pos: Vector2) -> void:
	motion(pos)
	await get_tree().process_frame
	mouse(pos,true)
	await get_tree().process_frame
	mouse(pos,false)
	await get_tree().create_timer(0.08).timeout

func click_control(control: Control) -> void:
	# 原生窗口中的容器布局在渲染前结算，等实际尺寸稳定后注入点击。
	for i in 4: await get_tree().process_frame
	await click(control.get_global_transform()*(control.size*0.5))

func drag(row: Control, destination: Vector2) -> void:
	var start := row.get_global_transform()*(row.size*0.5)
	motion(start)
	await get_tree().process_frame
	mouse(start,true)
	await get_tree().create_timer(0.2).timeout
	var puzzle := get_tree().current_scene
	print("DRAG_BEGIN leaf=",row.get_meta("leaf_id")," start=",start," active=",puzzle._drag_id," offset=",puzzle._drag_offset)
	motion(destination,destination-start,true)
	await get_tree().process_frame
	mouse(destination,false)
	await get_tree().create_timer(0.35).timeout
	print("DRAG_END target=",destination," order=",puzzle._order)

func finish_talk(city: Node3D) -> void:
	var guard := 0
	while is_instance_valid(city) and city.dialogue != null and guard < 200:
		var stage: Control = city.dialogue.lijiang_stage
		if stage != null and stage.blocks_continue() and not city.dialogue._typing:
			var rect: Rect2 = stage.slider.get_global_rect()
			await click(rect.position+Vector2(rect.size.x*0.87,rect.size.y*0.5))
			await click_control(stage.zoom_button)
			await click_control(stage.confirm_button)
		city.dialogue._continue()
		guard += 1
	await get_tree().process_frame

	if is_instance_valid(city) and city.reward_panel is ClueCard:
		city.reward_panel.close_button.pressed.emit()
		for frame_index in 4: await get_tree().process_frame
		if city.dialogue != null: await finish_talk(city)

func point(city: Node3D, id: String) -> Dictionary:
	for item in city.hotspots:
		if item["id"] == id: return item
	return {}

func teleport(city: Node3D, pos: Vector3) -> void:
	city.player.position = pos+Vector3(0,0.1,0)
	city.player.velocity = Vector3.ZERO
	await physics(6)

func walk(city: Node3D, target: Vector3, message: String) -> void:
	var path: PackedVector3Array = city.walk_guide.path(city.player.position,target)
	check(path.size()>1,message+"：物理路径存在")
	var stuck := false
	key(KEY_W,true)
	for waypoint in path:
		var frames := 0
		while Vector2(city.player.position.x-waypoint.x,city.player.position.z-waypoint.z).length()>0.28 and frames<110:
			var direction: Vector3 = waypoint-city.player.position
			city.yaw = atan2(-direction.x,-direction.z)
			# 原生窗口一帧可含多次物理帧，测试驾驶员同步实际移动朝向。
			city.player.heading = city.yaw
			# 原生窗口失焦会清除按键状态；持续驾驶时每帧重发真实按下事件。
			key(KEY_W,true)
			await physics(1)
			frames += 1
		if frames >= 110:
			printerr("STUCK ",message," position=",city.player.position," target=",waypoint," enabled=",city.player.enabled," W=",Input.is_physical_key_pressed(KEY_W)," heading=",city.player.heading," velocity=",city.player.velocity)
			stuck = true
			break
	key(KEY_W,false)
	await physics(3)
	check(not stuck and city.player.position.distance_to(target)<1.5,message+"：真实W键连续步行抵达")

func shot(name: String) -> void:
	if DisplayServer.get_name()=="headless" or output.is_empty(): return
	await get_tree().process_frame
	RenderingServer.force_draw()
	get_viewport().get_texture().get_image().save_png(output+"/"+name+".png")

func _ready() -> void:
	get_tree().current_scene = null
	actual_save = GameState.save_path
	output = OS.get_environment("PUER_EVIDENCE")
	_watchdog()
	GameState.save_path = "user://puer-chain-test.cfg"
	GameState.reset_game()
	GameState.unlocked.assign(["lijiang","xianggelila","dali","puer"])
	GameState.save_game()
	SceneRouter.goto_station("puer")
	var city := await ready_city()
	await physics(15)
	check(city.player.is_on_floor(),"寨口出生点正常落地")
	check(city.dialogue != null and city.dialogue.dialogue_id=="puer_arrival","普洱开场自动播放")
	check(city.dialogue._name_label.text=="旁白" and city.dialogue._name_chip.visible,"旁白姓名卡显示")
	check(city.dialogue._text_label.get_theme_font_size("normal_font_size")==36,"共用正文36字号")
	check(not city.player.enabled and Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"对话冻结移动并释放光标")
	await shot("01-arrival")
	await click(Vector2(750,570))
	check(not city.dialogue._typing,"真实点击补全文字")
	city.dialogue.find_children("*","Button",true,false)[0].grab_focus()
	key(KEY_SPACE,true)
	await get_tree().process_frame
	key(KEY_SPACE,false)
	check(city.dialogue.line_idx==1,"按钮焦点不吞空格继续")
	city.dialogue._leave()
	await get_tree().process_frame
	check(not city.done("arrival"),"开场中断不推进")
	for i in 3: await get_tree().process_frame
	check(GameUI._toast.size.y < 100 and GameUI._toast.get_global_rect().end.y < get_viewport().get_visible_rect().size.y-80,"中断提示条完整显示且不遮住地图")
	city.interact()
	await finish_talk(city)
	check(city.done("arrival") and city.clue_count()==0,"完整开场才认领任务")
	city._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)
	await get_tree().process_frame
	var yaw_before: float = city.yaw
	motion(Vector2(640,360),Vector2(50,20))
	check(is_equal_approx(city.yaw, yaw_before - 0.15 * GameSettings.camera_sensitivity),"鼠标无按键直接旋转视角")
	key(KEY_TAB,true)
	await get_tree().process_frame
	key(KEY_TAB,false)
	check(not city.mouse_look and Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"Tab切换光标")
	yaw_before = city.yaw
	motion(Vector2(640,360),Vector2(50,20))
	check(is_equal_approx(yaw_before,city.yaw),"光标模式不旋转镜头")
	await click_control(city.checklist.get_child(1))
	check(city.target_id=="farmer","真实点击清单选择茶农引路")
	await click(city.minimap.global_position+city.minimap.screen_point(point(city,"hostess")["position"]))
	check(city.target_id=="hostess","真实点击小地图选择竹楼")
	city.checklist.get_child(0).grab_focus()
	key(KEY_TAB,true)
	await get_tree().process_frame
	key(KEY_TAB,false)
	check(city.mouse_look,"任务按钮焦点不吞Tab")
	GameUI.open_pause()
	var stopped: Vector3 = city.player.position
	key(KEY_W,true)
	await get_tree().create_timer(0.15).timeout
	key(KEY_W,false)
	check(get_tree().paused and city.player.position==stopped,"暂停冻结真实玩家移动")
	GameUI.close_modal()
	await get_tree().process_frame
	check(city.player.enabled and not get_tree().paused,"恢复继续探索")
	key(KEY_R,true)
	key(KEY_R,false)
	await get_tree().process_frame
	check(is_equal_approx(city.pitch,0.7) and city.distance==12 and city.camera.fov==50,"普洱斜俯视参数与R复位生效")
	await shot("02-spawn")
	print("SPAWN_CAMERA_DISTANCE ",city.camera.position.distance_to(city.player.position+Vector3(0,0.8,0)))
	await teleport(city,city.goal_position+Vector3(0,0,1.3))
	city.interact()
	check(city.dialogue==null and not city.done("yanxiang_visit"),"提前到奘房不能跳过走访")
	await teleport(city,city.spawn_position)
	for id in ["hostess","farmer","novice"]:
		var item := point(city,id)
		await walk(city,item["position"],"沿途 → "+item["name"])
		check(city.near_hotspot().get("id","")==id,item["name"]+"可近距离交互")
		await get_tree().process_frame
		check(city.interaction_prompt.visible and city.interaction_text.text=="E 对话","人物旁E提示："+id)
		await shot("03-npc-"+id)
		city.interact()
		check(city.dialogue!=null and city.dialogue.dialogue_id==item["dialogue"],"本城访谈文字："+id)
		if id=="hostess":
			city.dialogue._continue()
			city.dialogue._leave()
			await get_tree().process_frame
			check(city.clue_count()==0,"访谈中断不记线索")
			city.interact()
		await finish_talk(city)
		if city.dialogue!=null: await finish_talk(city)
		var count: int = city.clue_count()
		check(GameState.has_flag("clue/puer/"+id),"完整访谈记录独立标记："+id)
		city.interact()
		await finish_talk(city)
		check(city.clue_count()==count,"重复交谈不累计："+id)
	check(city.clue_count()==3 and city.done("interviews") and city.target_id=="yanxiang","三处完成自动指向岩香")
	GameState.load_game()
	check(city.clue_count()==3,"重载存档保留三处走访")
	await walk(city,city.goal_position,"小沙弥 → 奘房岩香")
	city.interact()
	check(city.dialogue!=null and city.dialogue.lines.size()==20,"岩香入口与18句核心完整接入")
	await shot("04-core-dialogue")
	city.dialogue._leave()
	await get_tree().process_frame
	check(not city.done("yanxiang_visit"),"核心中断不进小游戏")
	var location: Vector3 = city.player.position
	var orientation: Dictionary = city.city_context()
	city.interact()
	await finish_talk(city)
	await settle()
	var puzzle := get_tree().current_scene
	check(SceneRouter.current_key=="puzzle_script" and SceneRouter.params.get("defer_reward",false),"核心结束自动进入原贝叶小游戏")
	puzzle._exit()
	city = await ready_city()
	print("RETURN_CONTEXT expected=",orientation," actual=",city.city_context())
	check(city.player.position.distance_to(location)<0.3 and is_equal_approx(city.yaw,orientation["yaw"]) and is_equal_approx(city.pitch,orientation["pitch"]) and city.distance==orientation["distance"],"退出小游戏保留原位置与全部视角")
	check(not city.done("script") and GameState.get_fragment_count()==0,"游戏中断不通关、不发碎片")
	city.interact()
	await settle()
	puzzle = get_tree().current_scene
	await click_control(puzzle._intro_layer.find_children("*","Button",true,false)[0])
	check(puzzle._level==1,"真实鼠标点击开始归册")
	await get_tree().create_timer(0.8).timeout
	var decoy: Control = puzzle._l1_cards["decoy_1"]
	for i in 3: await click_control(decoy)
	check(puzzle._hint.text==puzzle.config["level1"]["wrong3_hint"],"三次错误触发金框提示")
	for id in puzzle._volume_ids: await click_control(puzzle._l1_cards[id])
	await get_tree().create_timer(1.0).timeout
	check(puzzle._hole_marks.size()==2,"真实选齐六叶出现两孔")
	await shot("05-punch-ready")
	for mark in puzzle._hole_marks: await click_control(mark)
	await get_tree().create_timer(1.6).timeout
	check(puzzle._level==2,"真实点击两端打孔进入排序")
	# 首先制造错误，然后通过真实拖放拾回和逐叶重排。
	var row: Control = puzzle._l2_rows[puzzle._correct_order[-1]]
	await drag(row,Vector2(puzzle.L2_X+row.size.x*0.5,puzzle.L2_Y0+row.size.y*0.5))
	await click_control(puzzle._verify_btn)
	await get_tree().create_timer(2.0).timeout
	check(puzzle._floor_order.size()==1 and GameState.get_fragment_count()==0,"真实错误排序落叶且不领奖")
	await shot("06-wrong-leaf")
	if not puzzle._floor_order.is_empty():
		var fallen: Control = puzzle._floor_rows[puzzle._floor_order[0]]
		await drag(fallen,Vector2(puzzle.L2_X+fallen.size.x*0.35,puzzle.L2_Y0+5*puzzle.L2_STEP+fallen.size.y*0.35))
	check(puzzle._floor_order.is_empty(),"真实拖放捡回落叶")
	for i in puzzle._correct_order.size():
		row = puzzle._l2_rows[puzzle._correct_order[i]]
		await drag(row,Vector2(puzzle.L2_X+row.size.x*0.5,puzzle.L2_Y0+i*puzzle.L2_STEP+row.size.y*0.5))
	check(puzzle._order==puzzle._correct_order,"实际鼠标拖放完成六叶正确顺序")
	var readable := true
	for leaf in puzzle._order:
		readable = readable and is_equal_approx(puzzle._l2_rows[leaf].modulate.a,1.0)
	check(readable,"快速拖放中止渐显后六叶仍完整可见")
	if puzzle._order != puzzle._correct_order:
		_restore()
		get_tree().quit(1)
		return
	await shot("07-sorted")
	await click_control(puzzle._verify_btn)
	await get_tree().create_timer(0.1).timeout
	GameUI.open_pause()
	await get_tree().create_timer(0.4).timeout
	check(not puzzle._solved and not city.done("script") if is_instance_valid(city) else not puzzle._solved,"暂停时念读与通关计时不推进")
	GameUI.close_modal()
	await get_tree().create_timer(5.5).timeout
	city = await ready_city()
	check(city.done("script") and not GameState.has_fragment("frag_beiye_oath") and not GameState.is_unlocked("gucheng"),"真实通关保存成果，收尾前不领奖和解锁")
	check(city.dialogue!=null and city.dialogue.dialogue_id=="puer_yanxiang_farewell" and city.dialogue.lines.size()==8,"通关自动接用户要求的8句收尾")
	check(city.player.position.distance_to(location)<0.3,"自动收尾返回原地点")
	city.dialogue._continue()
	await shot("08-farewell")
	city.dialogue._leave()
	await get_tree().process_frame
	check(not city.done("farewell") and not GameState.has_fragment("frag_beiye_oath"),"收尾中断不领奖")
	GameState.load_game()
	SceneRouter.goto_map()
	await settle()
	SceneRouter.goto_station("puer")
	city = await ready_city()
	check(city.done("script") and city.dialogue!=null,"读档后恢复收尾，无需重玩")
	await finish_talk(city)
	check(GameState.has_fragment("frag_beiye_oath") and GameState.is_completed("puer") and GameState.is_unlocked("gucheng"),"8句结束才领原碎片并解锁古城")
	check(city.reward_panel!=null and GameUI._toast==null,"最后显示碎片领取卡，无中断提示残留")
	await shot("09-reward")
	if city.reward_panel.find_child("JournalSpread",true,false) != null:
		await click_control(city.reward_panel.find_children("*","Button",true,false)[0])
		check(city.reward_panel.find_child("CompletionChoices",true,false) != null, "真实收好手记显示共用完成选项")
		await shot("10-completion-choices")
	var buttons: Array = city.reward_panel.find_children("*","Button",true,false)
	await click_control(buttons[0])
	check(city.reward_panel==null and city.player.enabled,"领取页关闭回到当前地图")
	location = city.player.position
	orientation = city.city_context()
	SceneRouter.goto_codex()
	await settle()
	get_tree().current_scene._back()
	city = await ready_city()
	check(city.dialogue==null and city.player.position.distance_to(location)<0.3 and is_equal_approx(city.yaw,orientation["yaw"]),"图鉴返回保留位置视角，不重复领奖")
	check(city.story["bridges"].is_empty() and city.story["canal"].is_empty(),"实际地图无河道桥，不套用丽江水渠")
	await walk(city,city.anchor_position("POI_TeaViewDeck"),"奘房 → 观景台台阶")
	check(city.player.position.y>0.3,"真实行走登上观景台高差")
	await walk(city,city.anchor_position("POI_PalmLeafForest"),"观景台 → 贝叶棕林")
	await teleport(city,Vector3(-12.6,0,5.2))
	city.yaw=PI*0.5
	key(KEY_W,true)
	await physics(50)
	key(KEY_W,false)
	check(city.player.position.x>-13.1,"竹楼墙体阻挡连续前行")
	await teleport(city,Vector3(-29.8,0,0))
	city.yaw=PI*0.5
	key(KEY_W,true)
	key(KEY_SPACE,true)
	await physics(60)
	key(KEY_W,false)
	key(KEY_SPACE,false)
	check(city.player.position.x>-31.05,"边界阻挡前行与跳跃")
	await teleport(city,city.spawn_position)
	for angle in [-0.9,0.0,1.3,3.14]:
		city.yaw=angle
		city.camera_initialized=false
		city._update_camera()
		var query := PhysicsShapeQueryParameters3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius=0.18
		query.shape=sphere
		query.collision_mask=4
		query.transform=Transform3D(Basis.IDENTITY,city.camera.position)
		check(city.get_world_3d().direct_space_state.intersect_shape(query).is_empty(),"镜头球体不穿建筑："+str(angle))
	# 实体视线阻挡，证明同半径也不能隔墙交谈。
	var item := point(city,"hostess")
	await teleport(city,item["position"]+Vector3(0,0,1.2))
	var wall := StaticBody3D.new()
	city.add_child(wall)
	city._box(wall,item["position"]+Vector3(0,0.8,0.6),Vector3(1.5,1.6,0.15))
	await physics(2)
	check(city.near_hotspot().get("id","")!="hostess","隔墙不允许交互")
	wall.queue_free()
	# 全新档逆序访谈，不用先完成其他城或虚构碎片。
	GameState.reset_game()
	GameState.unlocked.assign(["lijiang","xianggelila","dali","puer"])
	SceneRouter.goto_station("puer")
	city=await ready_city()
	await finish_talk(city)
	for id in ["novice","farmer","hostess"]:
		item=point(city,id)
		await teleport(city,item["position"]+Vector3(0,0,1.2))
		city.interact()
		check(city.dialogue!=null,"自由逆序访谈："+id)
		await finish_talk(city)
		if city.dialogue!=null: await finish_talk(city)
	check(city.clue_count()==3 and city.target_id=="yanxiang","逆序同样完成全部条件")
	# 旧档：只保留碎片与完成状态，不含本轮任何剧情flag。
	GameState.flags.clear()
	GameState.collect_fragment("frag_beiye_oath")
	SceneRouter.goto_station("puer")
	city=await ready_city()
	check(city.dialogue==null and GameState.get_fragment_count()==1 and city.reward_panel==null,"已有碎片旧档无强制重走或重复奖励")
	await teleport(city,city.goal_position+Vector3(0,0,1.2))
	city.interact()
	check(city.dialogue != null and city.dialogue.dialogue_id=="puer_yanxiang_repeat", "已完成旧档岩香使用简短再访")
	await finish_talk(city)
	check(GameState.get_fragment_count()==1 and city.reward_panel==null, "核心再访不重复发奖")
	_restore()
	print("PUER_CHAIN_TEST checks=",checks," failures=",failures," renderer=",DisplayServer.get_name())
	get_tree().quit(failures)

func _restore() -> void:
	GameState.save_path=actual_save
	GameState.load_game()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://puer-chain-test.cfg"))

func _watchdog() -> void:
	await get_tree().create_timer(260.0).timeout
	printerr("FAIL: PUER_CHAIN_TIMEOUT")
	_restore()
	get_tree().quit(1)
