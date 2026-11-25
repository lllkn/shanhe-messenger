extends "res://tests/test_xianggelila_chain.gd"
## 本城真实走访/两关/收尾，附加模型、全部舞台映射及手机真实GUI输入。
var checked_models := false
var checked_phone := false
var mapped: Dictionary = {}
var focus_epoch := 0
var motion_focus_epoch := 0
var skipped_hover := 0
var stage_data: Dictionary

func bounds(model: Node3D) -> AABB:
	var result := AABB()
	var initialized := false
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		result = result.merge(box) if initialized else box
		initialized = true
	return result

func shot(name: String) -> void:
	var dir := OS.get_environment("XIANGGELILA_CHARACTER_SHOTS")
	if dir.is_empty() or DisplayServer.get_name() == "headless": return
	await get_tree().process_frame
	RenderingServer.force_draw()
	get_viewport().get_texture().get_image().save_png(dir.path_join(name+".png"))

func city_ready() -> Node3D:
	var city: Node3D = await super.city_ready()
	if checked_models:
		if GameState.is_completed("xianggelila") and city.reward_panel == null and city.dialogue == null and not mapped.has("xianggelila_danzeng_repeat"):
			var fragments: int = GameState.get_fragment_count()
			city.open_conversation("xianggelila_danzeng_repeat", "repeat")
			await finish_talk(city)
			check(GameState.get_fragment_count()==fragments, "完成后的丹增短回应不重复发奖")
		return city
	checked_models = true
	stage_data = ContentDB.read_json("res://data/xianggelila_dialogue_stage.json")
	for id in stage_data:
		check(id in load("res://ui/XianggelilaDialogueStage.gd").PORTRAITS, "本城对话完整映射 "+id)
	var visual: Node3D = city.player.get_node("CharacterVisual")
	check(visual.find_children("*", "MeshInstance3D", true, false).size() > 30, "女主独立实体GLB，保留移动碰撞")
	check(absf(bounds(visual).size.y-1.65)<0.025, "女主实测地图高度1.65米")
	check(visual.find_child("*LowPonytail*",true,false)!=null and visual.find_child("*Glasses*",true,false)!=null and visual.find_child("*ScarfTail*",true,false)!=null, "女主保留低马尾/眼镜/本站围巾")
	for item in city.hotspots:
		var actor: Node3D = item["actor"]
		visual = actor.get_node("CharacterVisual")
		check(visual.find_children("*", "MeshInstance3D",true,false).size()>30, "本城实体模型 "+item["id"])
		check(absf(bounds(visual).size.y-1.65)<0.025, "模型尺寸 "+item["id"])
		check(is_equal_approx(visual.rotation.y,deg_to_rad(item["facing_degrees"])), "模型朝向 "+item["id"])
		check(actor.get_node("NpcCollision").get_child_count()>0 and actor.position.is_equal_approx(item["position"]), "碰撞/地图/任务使用同一站位 "+item["id"])
		var at: Vector3 = item["position"]
		var query := PhysicsRayQueryParameters3D.create(at+Vector3(0,0.3,0),at-Vector3(0,1.2,0),1)
		query.exclude = [city.player.get_rid(), actor.get_node("NpcCollision").get_rid()]
		var hit := city.get_world_3d().direct_space_state.intersect_ray(query)
		check(not hit.is_empty() and absf(bounds(visual).position.y-hit.position.y)<0.035, "模型脚底落地 "+item["id"])
	for mesh in city.map_root.find_children("NPC_*", "MeshInstance3D",true,false):
		check(not mesh.visible, "原地图占位视觉隐藏 "+mesh.name)
	return city

func click_control(control: Control) -> void:
	await get_tree().process_frame
	var pos := control.get_global_rect().get_center()
	motion_to(pos)
	pointer(pos,true)
	await get_tree().process_frame
	pointer(pos,false)
	await get_tree().process_frame

func finish_talk(city: Node3D) -> void:
	var guard := 0
	while city.dialogue != null and guard < 250:
		var talk: Control = city.dialogue
		var stage: Control = talk.lijiang_stage
		var id: String = talk.dialogue_id
		if not mapped.has(id):
			mapped[id] = true
			check(stage != null and stage.protagonist.texture.resource_path == "res://assets/puzzles/dali/player_silhouette.png", "左右舞台复用同一女主剪影 "+id)
			var expected: String = stage_data[id]["portrait"]
			check((stage.npc.texture == null if expected.is_empty() else stage.npc.texture.resource_path == expected), "正确本城NPC立绘 "+id)
			check(not talk._portrait.visible, "旧单立绘隐藏 "+id)
			check(stage.phone != null if stage_data[id].has("phone") else stage.phone == null, "按实际剧情创建手机 "+id)
			check(not city.player.get_node("CharacterVisual").visible and not city.hotspots[0]["actor"].visible, "对话隐藏地图人物 "+id)
			if talk._typing: await click_control(talk._body_slot)
			await shot(id)
		if stage != null and stage.phone != null and stage.phone.visible:
			check(stage.settings_panel == null and stage.slider == null and not stage.blocks_continue(), "香格里拉只展示照片 " + id)
			check(stage.screen.modulate == Color.WHITE and stage.screen.scale == Vector2.ONE, "香格里拉照片清晰完整 " + id)
		if id == "xianggelila_danzeng_farewell" and talk.lines[talk.line_idx]["copy_id"]=="H10":
			check(stage.npc.texture.resource_path.ends_with("son-v01.png"), "收尾儿子发言显示本城儿子")
			await shot("farewell-son")
		if id == "xianggelila_danzeng_visit" and talk.lines[talk.line_idx]["copy_id"]=="F20":
			check(not stage.phone.visible, "收好手机台词隐藏照片")
		# 通过正文真实GUI点击补全/继续；不直接跳行、不设完成变量。
		await click_control(talk._body_slot)
		if is_instance_valid(talk) and not talk._finished:
			check(talk._text_label.get_content_height()<=talk._body_slot.size.y+1, "正文36字号不溢出 "+id+":"+str(talk.line_idx))
		guard += 1
	check(guard<250, "对话真实点击完成无死锁")
	await get_tree().process_frame
	if city.reward_panel != null: await shot("reward")

func walk(city: Node3D, target: Vector3, message: String) -> void:
	# 窗口可能一帧运行多次物理步，自动转向同步到heading，避免测试器的渲染帧滞后。
	# 仅方向由测试器设置；移动仍使用真实W输入和原碰撞，不传送/放宽抵达判定。
	var route: PackedVector3Array = city.walk_guide.path(city.player.position,target)
	check(not route.is_empty(), message+" 有物理可达引导路径")
	var saved_mouse: bool = city.mouse_look
	city.mouse_look = false
	var stuck := false
	key(KEY_W,true)
	for point in route:
		var frames := 0
		while Vector2(city.player.position.x-point.x,city.player.position.z-point.z).length()>0.22 and frames<100:
			var direction: Vector3 = point-city.player.position
			city.yaw = atan2(-direction.x,-direction.z)
			city.player.heading = city.yaw
			key(KEY_W,true) # 原生窗口失焦可能清空按键，每个物理步持续提交W输入。
			await get_tree().physics_frame
			frames += 1
		if frames>=100:
			printerr("STUCK ",message," at ",city.player.position," wanted ",point," W=",Input.is_physical_key_pressed(KEY_W)," speed=",city.player.velocity)
			stuck=true
			break
	key(KEY_W,false)
	city.mouse_look=saved_mouse
	await physics(3)
	check(not stuck and city.player.position.distance_to(target)<1.5,message+" 真实WASD连续步行抵达")
	for item in city.hotspots:
		if city.player.position.distance_to(item["position"])<2:
			await shot("walk-"+item["id"])

func pointer(position: Vector2, pressed: bool) -> void:
	var dir := OS.get_environment("XIANGGELILA_CHARACTER_SHOTS")
	if pressed and SceneRouter.current_key == "puzzle_dye" and not dir.is_empty() and DisplayServer.get_name() != "headless":
		var puzzle: Control = get_tree().current_scene
		if is_instance_valid(puzzle._settlement_continue) and puzzle._settlement_continue.is_visible_in_tree():
			RenderingServer.force_draw()
			get_viewport().get_texture().get_image().save_png(dir.path_join("dye-settlement.png"))
	super.pointer(position,pressed)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT: focus_epoch += 1

func motion_to(position: Vector2) -> void:
	motion_focus_epoch = focus_epoch
	super.motion_to(position)

func check(ok: bool, message: String) -> void:
	# 游戏规定失焦取消待切换悬停；只有明确收到失焦且停留被打断时，计时断言不适用。
	if not ok and DisplayServer.get_name() != "headless" and focus_epoch > motion_focus_epoch and message in ["染料卡停留不足1秒不切换NPC对白", "快速换卡和移回重新计时，不累加旧停留", "同一染料卡持续超过1秒才切换对应提示", "移出卡片不立即反复切回口诀", "移出超过1秒后恢复当前下料提示"]:
		skipped_hover += 1
		print("SKIP_FOCUS: ", message, " native focus-out interrupted the dwell; covered by independent headless run")
		return
	super.check(ok,message)
