extends RefCounted
## 借用城市已有弹层门闩阻止移动、镜头和对话输入穿透。
static func open(city: Node, clue_id: String, acquired := false) -> void:
	if city.dialogue != null or city.reward_panel != null or SceneRouter.is_switching(): return
	var item := ClueBook.entry(city.station_id, clue_id)
	if not ClueBook.collected(item): return
	GameUI.clear_notification()
	var previous_focus: Control = city.get_viewport().gui_get_focus_owner()
	var layer := CanvasLayer.new()
	layer.name = "CityClueLayer"
	layer.layer = 35
	city.add_child(layer)
	var card := ClueCard.new()
	layer.add_child(card)
	city.reward_panel = card
	city.player.enabled = false
	city.player.velocity = Vector3.ZERO
	city.dragging = false
	city.interaction_prompt.hide()
	var next_note := ""
	if acquired and city.clue_count() == city.story["interviews"].size():
		next_note = "三处走访已整理好，接下来去拜访" + city.story["core"]["name"] + "。"
	card.prepare(item, func():
		layer.queue_free()
		city.reward_panel = null
		city.player.enabled = true
		city.player.jump_needs_release = true
		if is_instance_valid(previous_focus) and not city.mouse_look: previous_focus.grab_focus()
		elif city.get_viewport().gui_get_focus_owner() != null: city.get_viewport().gui_get_focus_owner().release_focus()
		city._sync_mouse_mode()
		# 普洱三访后的总结对白要在收好最后一张卡后开始。
		if acquired and city.story.has("interviews_end") and city.clue_count() == city.story["interviews"].size() and not city.done("interviews_end"):
			city.open_conversation.call_deferred(city.story["interviews_end"], "interviews_end")
	, acquired, next_note)
	city._sync_mouse_mode()
