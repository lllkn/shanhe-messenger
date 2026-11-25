extends Node
func _ready() -> void:
	get_tree().current_scene = null
	GameState.save_path = "user://lijiang-text-check.cfg"
	GameState.reset_game()
	SceneRouter.goto_station("lijiang")
	await get_tree().process_frame
	while SceneRouter.is_switching(): await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	var city := get_tree().current_scene
	if city.dialogue != null: city.dialogue._leave()
	var overflow := 0
	for id in ["lijiang_silver","lijiang_student","lijiang_inn","lijiang_dongba_visit","lijiang_dongba_farewell"]:
		city.open_conversation(id,"qa")
		await get_tree().process_frame
		for i in city.dialogue.lines.size():
			city.dialogue._goto_line(i)
			city.dialogue._continue()
			await get_tree().process_frame
			var text: RichTextLabel = city.dialogue._text_label
			if text.get_content_height() > text.size.y + 1:
				overflow += 1
				print("TEXT_SCROLL ", id, " line=",i," content=",text.get_content_height()," visible=",text.size.y)
			if text.get_global_rect().end.y > get_viewport().get_visible_rect().size.y - 8:
				overflow += 1
				print("TEXT_OUTSIDE_VIEWPORT ", id, " line=",i)
		city.dialogue._leave()
		await get_tree().process_frame
	print("TEXT_CHECK overflow=",overflow)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.save_path))
	get_tree().quit(overflow)
