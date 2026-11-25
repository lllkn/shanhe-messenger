extends "res://tests/test_lijiang_chain.gd"
## 继承真实走访与两关通关检查，加入五角色及手机输入门槛检查。
var checked_models := false
var checked_phone := false

func city_ready() -> Node3D:
	var city: Node3D = await super.city_ready()
	if not checked_models:
		checked_models = true
		var visual: Node = city.player.get_node_or_null("CharacterVisual")
		check(visual != null and visual.find_children("*", "MeshInstance3D", true, false).size() > 30, "女主GLB由多部件3D网格组成，替换胶囊")
		for item in city.hotspots:
			visual = item["actor"].get_node_or_null("CharacterVisual")
			check(visual != null and visual.find_children("*", "MeshInstance3D", true, false).size() > 30, item["name"] + " 加载独立3D人物模型")
	return city

func finish_talk(city: Node3D) -> void:
	var guard := 0
	while city.dialogue != null and guard < 200:
		var talk: Control = city.dialogue
		var stage: Control = talk.lijiang_stage
		if stage != null and stage.blocks_continue() and not talk._typing:
			if not checked_phone:
				checked_phone = true
				check(stage.phone.visible and stage.npc.texture != null and stage.protagonist.texture != null, "手机照片、左侧东巴立绘与右侧已有女主剪影同时显示")
				talk._continue()
				check(talk.line_idx == 8 and stage.confirm_button.disabled, "初始暗屏不允许跳过亮度操作")
				stage.slider.value = 60
				stage.confirm_photo()
				check(not stage.confirmed and stage.confirm_button.disabled, "未调足亮度仍不能确认")
				await get_tree().process_frame
				await get_tree().process_frame
				var rect: Rect2 = stage.slider.get_global_rect()
				var point := rect.position + Vector2(rect.size.x * 0.87, rect.size.y * 0.5)
				var click := InputEventMouseButton.new()
				click.position = point
				click.button_index = MOUSE_BUTTON_LEFT
				click.pressed = true
				get_viewport().push_input(click, true)
				await get_tree().process_frame
				click.pressed = false
				get_viewport().push_input(click, true)
				await get_tree().process_frame
				check(stage.slider.value > 75 and talk.line_idx == 8, "真实鼠标事件操作滑杆，不误推进对话")
				check(stage.confirm_button.disabled and stage.screen.modulate.r > 0.8, "拖动滑杆即时调亮，尚未放大仍禁止确认")
				stage._toggle_zoom()
				check(stage.zoomed and stage.screen.scale.x == 2.5 and talk.line_idx == 8, "放大照片可看纹样且不误推进对话")
				stage.confirm_button.pressed.emit()
				check(stage.confirmed and not stage.blocks_continue(), "玩家递交照片后解除继续门槛")
			else:
				stage.slider.value = 85
				if not stage.zoomed: stage._toggle_zoom()
				stage.confirm_button.pressed.emit()
		city.dialogue._continue()
		guard += 1
	await get_tree().process_frame
