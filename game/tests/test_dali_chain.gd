extends Node
## 真实地图物理、完整对话及原版离线小游戏，不直接置通过标记。
var failures := 0
var checks := 0
var original_save := ""
var evidence := ""
var verified_lines := 0
var text_overflows := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	print("PASS: " if ok else "FAIL: ", message)
	if not ok: failures += 1

func physics(frames: int = 4) -> void:
	for i in frames: await get_tree().physics_frame

func settle() -> void:
	await get_tree().process_frame
	while SceneRouter.is_switching(): await get_tree().process_frame
	await get_tree().process_frame

func city_ready() -> Node3D:
	await settle()
	var city := get_tree().current_scene
	while not city.walk_guide.ready: await get_tree().physics_frame
	await get_tree().process_frame
	return city

func key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func motion(pos: Vector2, relative: Vector2 = Vector2.ZERO) -> void:
	var event := InputEventMouseMotion.new()
	event.position = pos
	event.global_position = pos
	event.relative = relative
	event.screen_relative = event.relative
	get_viewport().push_input(event, true)

func click(pos: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = pos
	event.global_position = pos
	event.pressed = pressed
	get_viewport().push_input(event, true)

func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless" or evidence.is_empty(): return
	await get_tree().process_frame
	RenderingServer.force_draw()
	var err := get_viewport().get_texture().get_image().save_png(evidence.path_join(name+".png"))
	check(err == OK, "窗口截图 " + name)

func finish_talk(city: Node3D) -> void:
	var guard := 0
	while city.dialogue != null and guard < 240:
		if city.dialogue._typing:
			city.dialogue._continue()
			await get_tree().process_frame
			await get_tree().process_frame
			var label: RichTextLabel=city.dialogue._text_label
			verified_lines+=1
			if label.get_content_height()>label.size.y+2 or label.get_global_rect().end.y>get_viewport().get_visible_rect().size.y:text_overflows+=1
		else:
			var stage: Control = city.dialogue.lijiang_stage
			if stage != null and stage.blocks_continue():
				await operate_phone(stage)
			else: city.dialogue._continue()
		guard += 1
	await get_tree().process_frame

	if is_instance_valid(city) and city.reward_panel is ClueCard:
		city.reward_panel.close_button.pressed.emit()
		for frame_index in 4: await get_tree().process_frame
		if city.dialogue != null: await finish_talk(city)

func operate_phone(stage: Control) -> void:
	# 走GUI真实滑杆点击、放大按钮、确认按钮，不直接设置confirmed。
	var slider_rect: Rect2 = stage.slider.get_global_rect()
	click(Vector2(slider_rect.position.x + slider_rect.size.x * 0.88, slider_rect.get_center().y), true)
	click(Vector2(slider_rect.position.x + slider_rect.size.x * 0.88, slider_rect.get_center().y), false)
	await get_tree().process_frame
	if stage.config.get("require_zoom", false) and not stage.zoomed:
		click(stage.zoom_button.get_global_rect().get_center(), true)
		click(stage.zoom_button.get_global_rect().get_center(), false)
		await get_tree().process_frame
	click(stage.confirm_button.get_global_rect().get_center(), true)
	click(stage.confirm_button.get_global_rect().get_center(), false)
	await get_tree().process_frame
	check(stage.confirmed, "照片GUI亮度/放大/确认 " + stage._dialogue_id)

func teleport(city: Node3D, pos: Vector3) -> void:
	city.player.position = pos + Vector3(0,0.10,0)
	city.player.velocity = Vector3.ZERO
	await physics(8)

func hotspot(city: Node3D, id: String) -> Dictionary:
	for item in city.hotspots:
		if item["id"] == id: return item
	return {}

func walk(city: Node3D, target: Vector3, message: String) -> bool:
	var route: PackedVector3Array = city.walk_guide.path(city.player.position,target)
	check(not route.is_empty(), message + " 有物理路径")
	if route.is_empty(): return false
	var stuck := false
	key(KEY_W,true)
	for point in route:
		var frames := 0
		while Vector2(city.player.position.x-point.x,city.player.position.z-point.z).length() > 0.22 and frames < 100:
			var direction: Vector3 = point-city.player.position
			city.yaw = atan2(-direction.x,-direction.z)
			# 原生窗口失焦会释放长按；每次继续步行都重新发送被释放的键。
			if not Input.is_physical_key_pressed(KEY_W): key(KEY_W,true)
			await get_tree().physics_frame
			frames += 1
		if frames >= 100:
			printerr("STUCK ",message," at ",city.player.position," wanted ",point," W=",Input.is_physical_key_pressed(KEY_W)," enabled=",city.player.enabled," focus=",city.window_focused," velocity=",city.player.velocity)
			var collision := KinematicCollision3D.new()
			if city.player.test_move(city.player.global_transform,(point-city.player.position).normalized()*0.7,collision):
				var obstacle: Object=collision.get_collider()
				var names: Array=obstacle.get_meta("shape_names",[])
				var index: int=collision.get_collider_shape_index()
				printerr("OBSTACLE ",obstacle," shape=",names[index] if index>=0 and index<names.size() else index," normal=",collision.get_normal())
			stuck = true
			break
	key(KEY_W,false)
	await physics(3)
	var arrived := not stuck and Vector2(city.player.position.x-target.x,city.player.position.z-target.z).length() < 1.5
	check(arrived,message+" 真实WASD连续抵达")
	return arrived

func check_text_bounds(talk: Control) -> void:
	check(not is_instance_valid(GameUI._toast),"进入对话清掉线索浮条，不遮住正文")
	talk._continue()
	await get_tree().process_frame
	await get_tree().process_frame
	var rect: Rect2 = talk._text_label.get_global_rect()
	check(rect.position.y >= 0 and rect.end.y <= get_viewport().get_visible_rect().size.y, "36字号正文完整留在屏幕内")
	check(talk._text_label.get_content_height() <= rect.size.y+2, "当前正文行高不溢出")

func _ready() -> void:
	get_tree().current_scene = null
	original_save = GameState.save_path
	evidence = OS.get_environment("DALI_TEST_EVIDENCE")
	if not evidence.is_empty(): DirAccess.make_dir_recursive_absolute(evidence)
	_watchdog()
	GameState.save_path = "user://dali-chain-test-"+DisplayServer.get_name()+".cfg"
	GameState.reset_game()
	GameState.unlocked.assign(["lijiang","xianggelila","dali"])
	SceneRouter.goto_station("dali")
	var city := await city_ready()
	await physics(25)
	check(city.player.is_on_floor(),"大理出生点实际落地")
	check(city.dialogue != null and city.dialogue.dialogue_id == "dali_arrival","出生自动接已确认大理旁白")
	check(city.dialogue._name_chip.visible and city.dialogue._name_label.text == "旁白","旁白姓名卡存在")
	check(city.dialogue._text_label.get_theme_font_size("normal_font_size") == 36,"使用共用36字号对话")
	check(not city.player.enabled and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,"对话冻结探索且释放光标")
	await check_text_bounds(city.dialogue)
	await shot("01-arrival")
	city.dialogue._leave()
	await get_tree().process_frame
	check(not city.done("arrival"),"开场中断不记完成")
	city.interact()
	var talk: Control = city.dialogue
	var panel := talk._body_slot.get_parent().get_parent() as Control
	click(panel.get_global_rect().get_center(),true)
	click(panel.get_global_rect().get_center(),false)
	await get_tree().process_frame
	check(not talk._typing and talk.line_idx == 0,"真实点击补全文字")
	talk.find_children("*","Button",true,false)[0].grab_focus()
	key(KEY_SPACE,true)
	key(KEY_SPACE,false)
	await get_tree().process_frame
	check(talk.line_idx == 1,"按钮焦点下空格仍继续")
	await finish_talk(city)
	check(city.done("arrival") and city.clue_count() == 0,"开场完整结束才认领任务")
	city._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)
	await get_tree().process_frame
	var before_yaw: float = city.yaw
	motion(Vector2(600,350),Vector2(50,20))
	check(absf(city.yaw-before_yaw)>0.1,"直接鼠标移动转视角")
	key(KEY_TAB,true); key(KEY_TAB,false)
	await get_tree().process_frame
	check(not city.mouse_look and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,"Tab释放光标")
	before_yaw = city.yaw
	motion(Vector2(600,350),Vector2(30,10))
	check(is_equal_approx(before_yaw,city.yaw),"光标模式不误转镜头")
	var young := hotspot(city,"youngster")
	var mini: Control = city.minimap
	click(mini.global_position+mini.screen_point(young["position"]),true)
	click(mini.global_position+mini.screen_point(young["position"]),false)
	await get_tree().process_frame
	check(city.target_id == "youngster","真实点击小地图选择大理目标")
	city.checklist.get_child(0).grab_focus()
	key(KEY_TAB,true); key(KEY_TAB,false)
	await get_tree().process_frame
	check(city.mouse_look,"按钮焦点不吞Tab")
	GameUI.open_pause()
	var paused_position: Vector3 = city.player.position
	key(KEY_W,true)
	for i in 8: await get_tree().process_frame
	key(KEY_W,false)
	check(get_tree().paused and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and city.player.position == paused_position,"暂停不走路且释放光标")
	GameUI.close_modal()
	await get_tree().process_frame
	city._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	before_yaw = city.yaw
	motion(Vector2(600,350),Vector2(50,20))
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and is_equal_approx(before_yaw,city.yaw),"失焦释放光标且不转镜头")
	city._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)
	key(KEY_R,true); key(KEY_R,false)
	await get_tree().process_frame
	check(city.distance == 12 and is_equal_approx(city.pitch,0.70) and city.camera.fov == 50,"大理专用斜俯视配置")
	check(city.minimap.floor_texture != null and city.hotspots.size() == 4,"物理小地图仅保留四位主线人物")
	check(hotspot(city,"zhaobi").is_empty() and hotspot(city,"pagodas").is_empty(),"两处风物不再生成标记和交互")
	await shot("02-map-guide")
	await teleport(city,city.goal_position+Vector3(0,0,-1.2))
	city.interact()
	check(city.dialogue == null and not city.done("popo_visit"),"提前到坊门不能跳过走访")
	await teleport(city,city.spawn_position)
	for id in ["vendor","youngster","granny"]:
		var item := hotspot(city,id)
		if not await walk(city,item["position"],"出生/上一访谈 → "+item["name"]):
			_restore_save(); get_tree().quit(1); return
		check(city.near_hotspot().get("id","")==id,"到位可与"+item["name"]+"交谈")
		await get_tree().process_frame
		check(city.interaction_prompt.visible and city.interaction_text.text == "E 对话","人物旁E提示 "+id)
		await shot("03-npc-"+id)
		city.interact()
		check(city.dialogue != null and city.dialogue.dialogue_id==item["dialogue"],"对应已确认访谈 "+id)
		if city.dialogue == null: _restore_save(); get_tree().quit(1); return
		if id=="vendor":
			city.dialogue._continue(); city.dialogue._leave()
			await get_tree().process_frame
			check(city.clue_count()==0,"访谈中断不发线索")
			city.interact()
		if id=="granny": check(city.dialogue.lines[3]["text"].ends_with("也认不得。"),"D05采用用户修订原句")
		await finish_talk(city)
		var count: int = city.clue_count()
		check(GameState.has_flag("clue/dali/"+id),"完整访谈才记唯一线索 "+id)
		city.interact()
		check(city.dialogue.dialogue_id==item["repeat"],"重访使用已审核短对白 "+id)
		await finish_talk(city)
		check(city.clue_count()==count,"重访不重复计数 "+id)
	check(city.clue_count()==3 and city.done("interviews") and city.target_id=="popo","三处齐全后引导婆婆")
	GameState.load_game()
	check(city.clue_count()==3,"存档恢复三处线索")
	if not await walk(city,city.goal_position,"民居巷 → 周城扎染坊"):
		_restore_save(); get_tree().quit(1); return
	city.interact()
	check(city.dialogue != null and city.dialogue.lines.size()==20,"婆婆核心采用入口两句＋精简18句")
	if city.dialogue == null: _restore_save(); get_tree().quit(1); return
	await check_text_bounds(city.dialogue)
	await shot("04-popo-visit")
	city.dialogue._leave()
	await get_tree().process_frame
	check(not city.done("popo_visit"),"核心中断不启动小游戏")
	var position: Vector3 = city.player.position
	var saved_yaw: float = city.yaw
	var saved_pitch: float = city.pitch
	var saved_distance: float = city.distance
	city.interact()
	await finish_talk(city)
	await settle()
	var puzzle := get_tree().current_scene
	check(SceneRouter.current_key=="puzzle_pattern" and SceneRouter.params.get("defer_reward",false),"核心正常结束自动进入原大理小游戏并延后奖励")
	puzzle._exit()
	city=await city_ready()
	check(city.player.position.distance_to(position)<0.3 and absf(city.yaw-saved_yaw)<0.01 and absf(city.pitch-saved_pitch)<0.01 and absf(city.distance-saved_distance)<0.01,"退出小游戏回原位置与完整视角")
	check(not city.done("pattern") and not GameState.has_fragment("frag_zharan_pattern"),"小游戏中断不记通过不领奖")
	city.interact()
	await settle()
	puzzle=get_tree().current_scene
	# 使用正式支持的本地模式，走真实逐笔作画、卡片选择和玩家笔画提交。
	puzzle._offline=true
	puzzle._api_key=""
	puzzle._on_intro_start()
	for round in 6:
		var guard:=0
		while puzzle._busy and guard<1200:
			await get_tree().process_frame
			guard+=1
		check(guard<1200,"小游戏本轮准备完成 "+str(round+1))
		if puzzle._phase=="a":
			if round==0: await shot("05-popo-draw")
			var correct: int = puzzle._option_ids.find(puzzle._topic["id"])
			var cell: Control=puzzle._options_root.get_child(correct)
			var button: Button=cell.find_children("*","Button",true,false)[0]
			click(button.get_global_rect().get_center(),true)
			click(button.get_global_rect().get_center(),false)
		else:
			for stroke in 3:
				var a: Vector2=puzzle._board.global_position+Vector2(120+stroke*80,110+stroke*50)
				motion(a)
				await get_tree().process_frame
				click(a,true)
				await get_tree().process_frame
				for part in 5:
					motion(a+Vector2(part*22,part*12))
					await get_tree().process_frame
				click(a+Vector2(88,48),false)
				await get_tree().process_frame
				print("DRAW_LOCAL ",puzzle._board.get_local_mouse_position()," strokes=",puzzle._player_strokes.size()," phase=",puzzle._phase," busy=",puzzle._busy)
			check(puzzle._player_strokes.size()==3,"画布实际接收三笔 "+str(round+1))
			if round==3: await shot("06-player-draw")
			click(puzzle._submit_btn.get_global_rect().get_center(),true)
			click(puzzle._submit_btn.get_global_rect().get_center(),false)
		var prev: int=puzzle._rounds_played
		guard=0
		while not puzzle._finished and puzzle._rounds_played==prev and guard<600:
			await get_tree().process_frame; guard+=1
	check(puzzle._finished and puzzle._success==6,"真实完成原版双三轮小游戏")
	check(GameState.has_flag("flow/dali/pattern") and not GameState.has_fragment("frag_zharan_pattern") and not GameState.is_unlocked("puer"),"游戏通过只记pattern，收尾前无碎片无下一站")
	while SceneRouter.current_key != "city" or SceneRouter.is_switching(): await get_tree().process_frame
	city=await city_ready()
	check(city.dialogue != null and city.dialogue.dialogue_id=="dali_popo_farewell","通关自动返回并进入收尾，不需额外E或结算按钮")
	check(city.player.position.distance_to(position)<0.3 and absf(city.yaw-saved_yaw)<0.01,"通关返回仍保留位置视角")
	await check_text_bounds(city.dialogue)
	await shot("07-farewell")
	city.dialogue._leave()
	await get_tree().process_frame
	check(not city.done("farewell") and not GameState.has_fragment("frag_zharan_pattern"),"收尾中断不领奖")
	GameState.load_game()
	check(city.done("pattern") and not city.done("farewell"),"存档区分游戏通过与奖励完成")
	SceneRouter.goto_map(); await settle()
	SceneRouter.goto_station("dali"); city=await city_ready()
	check(city.dialogue != null and city.done("pattern"),"重进自动恢复收尾，不重玩小游戏")
	await finish_talk(city)
	check(GameState.has_fragment("frag_zharan_pattern") and GameState.is_completed("dali") and GameState.is_unlocked("puer"),"收尾完整结束才领原碎片ID并解锁普洱")
	check(city.reward_panel != null,"大理奖励卡出现")
	await shot("08-reward")
	city.reward_panel.get_parent().queue_free(); city.reward_panel=null; city.player.enabled=true
	await get_tree().process_frame
	SceneRouter.goto_codex(); await settle()
	get_tree().current_scene._back(); city=await city_ready()
	check(city.dialogue==null and GameState.get_fragment_count()==1,"图鉴返回保留位置、不重复领奖")
	# 桥测试使用每座桥独立的模型轴向；从同一位置持续走到桥入口再跨桥。
	for bridge in city.story["bridges"]:
		var middle: Vector3=city.bridge_center(bridge)
		var axis_data: Array=bridge["across"]
		var across:=Vector3(axis_data[0],0,axis_data[2])
		await walk(city,middle-across*3.4,"到桥入口 "+bridge["id"])
		await walk(city,middle,"走到真实桥面 "+bridge["id"])
		check(Vector2(city.player.position.x-middle.x,city.player.position.z-middle.z).length()<0.8 and city.player.position.y>0.28,"脚底真实落在桥心而非绕路 "+bridge["id"])
		await shot("09-bridge-"+bridge["id"])
		await walk(city,middle+across*3.4,"跨桥 "+bridge["id"])
	# 选取一处距NPC足够近但视线被实体墙挡住的位置，验证不能隔墙交谈。
	var blocked_point: Vector3=city.goal_position+Vector3(0,0,2.3)
	var ray:=PhysicsRayQueryParameters3D.create(blocked_point+Vector3(0,0.85,0),city.goal_position+Vector3(0,0.85,0),1)
	ray.exclude=[hotspot(city,"popo")["actor"].get_node("NpcCollision").get_rid(),city.player.get_rid()]
	check(not city.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(),"婆婆与近距离站位之间有真实照壁")
	city.player.position=blocked_point;city.player.velocity=Vector3.ZERO
	check(city.near_hotspot().get("id","")!="popo","实体照壁挡住近距离交谈")
	var guarded_samples:=0
	var unguarded_samples:=0
	for segment in city.story["canal"].size()-1:
		var aa: Array=city.story["canal"][segment]
		var bb: Array=city.story["canal"][segment+1]
		var start:=Vector3(aa[0],0,aa[1]);var end:=Vector3(bb[0],0,bb[1])
		var side: Vector3=(end-start).normalized().cross(Vector3.UP)
		for sample in 11:
			var center: Vector3=start.lerp(end,sample/10.0)
			var on_bridge:=false
			for bridge in city.story["bridges"]:
				if not bridge.get("water",false):continue
				var axis_data: Array=bridge["across"]
				var axis:=Vector3(axis_data[0],0,axis_data[2])
				var local: Vector3=center-city.bridge_center(bridge)
				if absf(local.dot(axis))<2.85 and absf(local.dot(axis.cross(Vector3.UP)))<1.45:on_bridge=true
			if on_bridge:continue
			guarded_samples+=1
			var water_ray:=PhysicsRayQueryParameters3D.create(center+side*2+Vector3(0,0.85,0),center-side*2+Vector3(0,0.85,0),1)
			water_ray.exclude=[city.player.get_rid()]
			if city.get_world_3d().direct_space_state.intersect_ray(water_ray).is_empty():unguarded_samples+=1
	check(guarded_samples>30 and unguarded_samples==0,"桥面之外河道阻挡检查 "+str(guarded_samples)+" 点，无缺口 "+str(unguarded_samples))
	# 无桥渠段，连续前行和跳跃都受安全阻挡。
	var a: Array=city.story["canal"][4]
	var b: Array=city.story["canal"][5]
	var middle:=Vector3((a[0]+b[0])*0.5,0,(a[1]+b[1])*0.5)
	var tangent:=Vector3(b[0]-a[0],0,b[1]-a[1]).normalized()
	var across:=Vector3(-tangent.z,0,tangent.x)
	await teleport(city,middle-across*2.4)
	city.yaw=atan2(-across.x,-across.z)
	key(KEY_W,true);key(KEY_SPACE,true)
	await physics(85)
	key(KEY_W,false);key(KEY_SPACE,false)
	check((city.player.position-middle).dot(across)<-0.9,"非桥渠段不能走或跳穿")
	for angle in [0.0,1.3,3.14,-1.2]:
		city.yaw=angle;city.pitch=0.70;city._update_camera()
		check(absf(city.camera.position.distance_to(city.follow_camera.focus_position)-city.distance)<0.001,"墙边镜头保持用户设定距离 "+str(angle))
	# 第二轮反向实际走访，验证自由顺序。
	GameState.reset_game();GameState.unlocked.assign(["lijiang","xianggelila","dali"])
	SceneRouter.goto_station("dali");city=await city_ready();await finish_talk(city)
	for id in ["granny","youngster","vendor"]:
		var item:=hotspot(city,id)
		await walk(city,item["position"],"反向走访 "+id)
		city.interact();check(city.dialogue!=null,"自由顺序能交谈 "+id)
		await finish_talk(city)
	check(city.clue_count()==3 and city.target_id=="popo","反向顺序完成同一三处条件")
	# 模拟已有碎片而无新剧情标记的旧完成档。
	GameState.flags.clear();GameState.collect_fragment("frag_zharan_pattern")
	GameState.load_game();SceneRouter.goto_station("dali");city=await city_ready()
	check(city.dialogue==null and GameState.is_completed("dali"),"旧完成档不要求重访或重玩")
	await teleport(city,city.goal_position+Vector3(0,0,-1.2));city.interact()
	check(city.dialogue!=null and city.dialogue.dialogue_id=="dali_popo_repeat","旧完成档可重访婆婆")
	await finish_talk(city)
	check(GameState.get_fragment_count()==1,"重访婆婆不重复奖励")
	check(verified_lines>80 and text_overflows==0,"逐句核对正文 "+str(verified_lines)+" 句，溢出 "+str(text_overflows))
	_restore_save()
	print("DALI_CHAIN_TEST checks=",checks," failures=",failures," renderer=",DisplayServer.get_name())
	get_tree().quit(failures)

func _restore_save() -> void:
	var used_save:=GameState.save_path
	GameState.save_path=original_save
	GameState.load_game()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(used_save))

func _watchdog() -> void:
	await get_tree().create_timer(600.0).timeout
	printerr("FAIL: 大理检查超时")
	_restore_save();get_tree().quit(1)
