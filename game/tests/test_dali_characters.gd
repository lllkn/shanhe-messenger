extends "res://tests/test_dali_chain.gd"
## 大理人物、全部ID、照片GUI和中断的专项检查；日志/截图在候选包外。

func model_bounds(model: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = mesh.mesh.get_aabb()
		var transform: Transform3D = model.global_transform.affine_inverse() * mesh.global_transform
		for corner in 8:
			var point: Vector3 = transform * box.get_endpoint(corner)
			if first:
				result = AABB(point, Vector3.ZERO)
				first = false
			else: result = result.expand(point)
	return result

func press_button(button: Button) -> void:
	click(button.get_global_rect().get_center(), true)
	click(button.get_global_rect().get_center(), false)
	await get_tree().process_frame

func _ready() -> void:
	get_tree().current_scene = null
	original_save = GameState.save_path
	evidence = OS.get_environment("DALI_TEST_EVIDENCE")
	if not evidence.is_empty(): DirAccess.make_dir_recursive_absolute(evidence)
	_watchdog()
	GameState.save_path = "user://dali-characters-test-" + DisplayServer.get_name() + ".cfg"
	GameState.reset_game()
	GameState.unlocked.assign(["lijiang", "xianggelila", "dali"])
	SceneRouter.goto_station("dali")
	var city := await city_ready()
	await physics(20)
	await finish_talk(city)
	var player_model: Node3D = city.player.get_node_or_null("CharacterVisual")
	check(player_model != null, "女主使用大理独立GLB")
	var box := model_bounds(player_model)
	check(absf(box.size.y - 1.65) < 0.03 and absf(box.position.y) < 0.025, "女主实测高度1.65米与脚底0")
	check(player_model.find_child("*LowPonytail*", true, false) != null and player_model.find_child("*Glasses*", true, false) != null, "低马尾与黑框眼镜身份保留")
	check(player_model.find_child("*LongSkirt*", true, false) != null, "本城月白裙装模型")
	check(city.player.find_children("*", "CollisionShape3D", true, false).size() > 0, "替换女主保留玩家碰撞")
	for item in city.hotspots:
		if item.get("observation", false): continue
		var model: Node3D = item["actor"].get_node_or_null("CharacterVisual")
		check(model != null, "NPC独立3D " + item["id"])
		box = model_bounds(model)
		check(absf(box.size.y - item["height"]) < 0.03 and absf(box.position.y) < 0.025, "实际Godot模型高度脚底 " + item["id"])
		check(absf(model.rotation.y - item["facing"]) < 0.01, "NPC朝向配置 " + item["id"])
		var body: StaticBody3D = item["actor"].get_node("NpcCollision")
		check(body.get_child_count() == 1 and body.collision_layer == 1, "NPC实体碰撞保留 " + item["id"])
		var ray := PhysicsRayQueryParameters3D.create(item["position"] + Vector3(0, 0.4, 0), item["position"] - Vector3(0, 0.4, 0), 1)
		ray.exclude = [body.get_rid(), city.player.get_rid()]
		var hit := city.get_world_3d().direct_space_state.intersect_ray(ray)
		check(not hit.is_empty() and absf(hit.position.y - item["actor"].position.y) < 0.025, "NPC真实脚底贴地 " + item["id"])
		check(item["position"] == item["actor"].position and item["label"].position.y > box.size.y, "模型标签互动路线站位一致 " + item["id"])
	var direction := Vector3(-1, 0, 0)
	city.yaw = atan2(-direction.x, -direction.z)
	key(KEY_W, true)
	await physics(30)
	check((player_model.basis * Vector3.BACK).normalized().dot(direction) > 0.9, "真实步行模型+Z正面跟随速度")
	check(absf(player_model.left_leg.rotation.x) > 0.01, "实际分件步行动作")
	key(KEY_W, false)
	await physics(3)
	var stage_script: Script = load("res://ui/DaliDialogueStage.gd")
	for id in stage_script.PORTRAITS:
		city.open_conversation(id, "repeat")
		await get_tree().process_frame
		var talk: Control = city.dialogue
		var stage: Control = talk.lijiang_stage
		check(stage != null, "全ID接入人物舞台 " + id)
		check(stage.protagonist.texture.resource_path == "res://assets/puzzles/dali/player_silhouette.png", "既有女主剪影 " + id)
		check(not player_model.visible and not hotspot(city, "vendor")["actor"].visible, "对话隐藏3D人物与姓名 " + id)
		var expected: String = stage_script.PORTRAITS[id]
		check((stage.npc.texture != null and stage.npc.texture.resource_path == expected) if not expected.is_empty() else not stage.npc.visible, "左侧本城NPC映射 " + id)
		if not stage.config.has("photo"): check(stage.phone == null and stage.screen == null, "无照片对话不加载手机 " + id)
		while city.dialogue != null:
			talk = city.dialogue
			if talk._typing: talk._continue()
			await get_tree().process_frame
			await get_tree().process_frame
			check(talk._text_label.get_content_height() <= talk._text_label.size.y + 2, "36字号逐句排版 " + id + "/" + str(talk.line_idx))
			var speaker: String = talk.lines[talk.line_idx].get("speaker", "")
			if speaker in stage.config.get("speaker_portraits", {}):
				check(stage.npc.texture.resource_path == stage.config["speaker_portraits"][speaker], "当前NPC随发言切换 " + speaker)
			if stage.phone != null and stage.phone.visible:
				check(stage.settings_panel == null and stage.slider == null and not stage.blocks_continue(), "照片只展示，无调整控件或继续门槛 " + id)
				check(stage.screen.modulate == Color.WHITE and stage.screen.scale == Vector2.ONE, "清晰完整照片 " + id)
			if id == "dali_popo_farewell" and talk.lines[talk.line_idx].get("source_line", "") == "H09": await shot("farewell-youngster-speaking")
			if talk.line_idx == 0 and stage.phone == null: await shot(id + "-stage")
			talk._continue()
			await get_tree().process_frame
		check(player_model.visible and hotspot(city, "vendor")["actor"].visible, "完成恢复人物 " + id)
	check(city.clue_count() == 0 and not city.done("popo_visit") and not GameState.has_fragment("frag_zharan_pattern"), "舞台单独阅览不偷记剧情或奖励")
	# 中断真实访谈的照片展示，再访仍为首次全文。
	await walk(city, hotspot(city, "vendor")["position"], "照片中断前实走摊主")
	city.interact()
	city.dialogue._goto_line(1)
	city.dialogue._continue()
	await get_tree().process_frame
	check(city.dialogue.lijiang_stage.settings_panel == null and not city.dialogue.lijiang_stage.blocks_continue(), "照片展示无需调整")
	city.dialogue._leave()
	await get_tree().process_frame
	check(city.clue_count() == 0 and player_model.visible, "照片展示后退出仍不记访谈完成")
	city.interact()
	check(city.dialogue.dialogue_id == "dali_vendor" and not city.dialogue.lijiang_stage.confirmed and city.dialogue.lijiang_stage.photo_brightness == 35, "首次重开全文，仍只展示照片")
	city.dialogue._leave()
	await get_tree().process_frame
	_restore_save()
	print("DALI_CHARACTERS_TEST checks=", checks, " failures=", failures, " renderer=", DisplayServer.get_name())
	get_tree().quit(failures)
