extends "res://tests/test_puer_chain.gd"
## 真实行走与两关鼠标链路，加本城人物/全部ID/手机/中断/再访检查。
var checked_characters := false
var checked_phone := false

func ready_city() -> Node3D:
	var city: Node3D = await super.ready_city()
	if checked_characters: return city
	checked_characters = true
	var visual: Node3D = city.player.get_node_or_null("CharacterVisual")
	check(visual != null and visual.find_children("*", "MeshInstance3D", true, false).size() > 30, "普洱女主多部件GLB，茶绿裤装与眼镜低马尾")
	check(city.player.find_children("*", "CollisionShape3D", true, false)[0].shape is CapsuleShape3D, "女主原碰撞胶囊保留")
	for item in city.hotspots:
		visual = item["actor"].get_node_or_null("CharacterVisual")
		check(visual != null and visual.find_children("*", "MeshInstance3D", true, false).size() > 30, item["name"]+"本城独立GLB")
		check(item["actor"].get_node_or_null("NpcCollision") != null and item["actor"].position.distance_to(item["position"]) < 0.01, item["name"]+"模型/碰撞/任务锚点一致")
		var bounds := model_bounds(visual)
		check(absf(bounds.size.y-float(item["height"]))<0.025 and absf(bounds.position.y-item["position"].y)<0.025, item["name"]+"实际网格高度与脚底落地")
		print("PUER_MODEL_BOUNDS ",item["id"]," ",bounds)
	# 每个初次/再次/旁白/收尾ID实际创建舞台与逐行布局。
	city.dialogue._leave()
	await get_tree().process_frame
	var ids: Dictionary = load("res://ui/PuerDialogueStage.gd").PORTRAITS
	for id in ids:
		city.open_conversation(id,"qa")
		for i in 3: await get_tree().process_frame
		var talk: Control = city.dialogue
		var stage: Control = talk.lijiang_stage
		check(stage != null and stage.protagonist.texture.resource_path == "res://assets/puzzles/dali/player_silhouette.png", id+"右侧原女主剪影")
		check(stage.npc.texture != null if not ids[id].is_empty() else not stage.npc.visible, id+"左側对应NPC/独白舞台")
		check(not city.player.get_node("CharacterVisual").visible and not city.hotspots[0]["actor"].visible, id+"地图人物视觉隐藏")
		if "repeat" in id or id in ["puer_novice","puer_interviews_end"]:
			check(stage.phone == null, id+"不创建或加载手机")
		check(stage.get_index() > talk._scene_background.get_index() if talk._scene_background != null else true, id+"人物舞台位于背景上方")
		var layout_ok := true
		for i in talk.lines.size():
			talk._goto_line(i)
			talk._continue()
			for n in 2: await get_tree().process_frame
			var label: RichTextLabel = talk._text_label
			layout_ok = layout_ok and label.get_content_height() <= label.size.y+1 and label.get_global_rect().end.y < 712
			layout_ok = layout_ok and absf(label.position.y+label.size.y*0.5-talk._body_slot.size.y*0.5)<1
			if id == "puer_yanxiang_farewell" and i==5:
				check(stage.npc.texture.resource_path.ends_with("novice-v01.png"), "收尾小沙弥发言显示本城小沙弥")
		check(layout_ok,id+"逐句36字号正文居中且无溢出")
		await shot("stage-"+id)
		if id == "puer_yanxiang_visit":
			talk._goto_line(4)
			talk._continue()
			check(stage.settings_panel == null and stage.slider == null and not stage.blocks_continue(), "岩香照片只展示，不要求重复调整")
			check(stage.screen.modulate == Color.WHITE and stage.screen.scale == Vector2.ONE, "岩香照片清晰完整")
			await shot("phone-display")
			await click(Vector2(750,570))
			check(talk.line_idx==5, "照片展示后真实点击只推进一句")
		city.dialogue._leave()
		await get_tree().process_frame
		check(city.clue_count()==0 and not city.done("yanxiang_visit") and city.player.get_node("CharacterVisual").visible, id+"中断不记完成并恢复地图人物")
	city.open_conversation("puer_yanxiang_visit","qa")
	check(city.dialogue.line_idx==0 and not city.dialogue.lijiang_stage.confirmed and city.dialogue.lijiang_stage.photo_brightness==35, "照片展示后中断再访从首句恢复")
	city.dialogue._leave()
	await get_tree().process_frame
	city.open_conversation("puer_arrival","arrival")
	return city

func model_bounds(root: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for instance in root.find_children("*","MeshInstance3D",true,false):
		var mesh: Mesh = instance.mesh
		for surface in mesh.get_surface_count():
			var vertices: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				var point: Vector3 = instance.global_transform * vertex
				result = AABB(point,Vector3.ZERO) if first else result.expand(point)
				first = false
	return result

func finish_talk(city: Node3D) -> void:
	if city.dialogue != null and "repeat" in city.dialogue.dialogue_id:
		var id: String = city.dialogue.dialogue_id
		check(city.dialogue.lines.size() == (2 if "yanxiang" in id else 1), id+"再次交谈为简短回应")
	var guard := 0
	while is_instance_valid(city) and city.dialogue != null and guard < 200:
		var talk: Control = city.dialogue
		var stage: Control = talk.lijiang_stage
		if stage != null and stage.phone != null and stage.phone.visible:
			check(stage.settings_panel == null and not stage.blocks_continue(), "普洱只展示照片")
		await click(Vector2(750,570))
		guard += 1
	await get_tree().process_frame

func walk(city: Node3D, target: Vector3, message: String) -> void:
	await super.walk(city,target,message)
	check(city.player.get_node("CharacterVisual").visible, message+"行走后女主可见")
	var forward: Vector3 = city.player.get_node("CharacterVisual").basis.z
	check(forward.dot(Vector3(-sin(city.yaw),0,-cos(city.yaw)))>0.7,message+"模型正面跟随实际行走朝向")
	await shot("walk-"+message.replace(" → ","-"))
