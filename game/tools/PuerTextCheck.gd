extends Node
func _ready() -> void:
	get_tree().current_scene=null
	var original: String=GameState.save_path
	GameState.save_path="user://puer-text-check.cfg"
	GameState.reset_game()
	GameState.unlocked.assign(["lijiang","xianggelila","dali","puer"])
	SceneRouter.goto_station("puer")
	await get_tree().process_frame
	while SceneRouter.is_switching(): await get_tree().process_frame
	var city := get_tree().current_scene
	while not city.walk_guide.ready: await get_tree().physics_frame
	if city.dialogue!=null: city.dialogue._leave()
	var overflow:=0
	var count:=0
	for id in ["puer_arrival","puer_hostess","puer_farmer","puer_novice","puer_yanxiang_visit","puer_yanxiang_farewell"]:
		city.open_conversation(id,"qa")
		await get_tree().process_frame
		for i in city.dialogue.lines.size():
			city.dialogue._goto_line(i)
			city.dialogue._continue()
			await get_tree().process_frame
			await get_tree().process_frame
			var label: RichTextLabel=city.dialogue._text_label
			var slot: Control=city.dialogue._body_slot
			if label.get_content_height()>label.size.y+1 or label.get_global_rect().end.y>get_viewport().get_visible_rect().size.y-8:
				overflow+=1
				print("TEXT_OVERFLOW ",id," line=",i," height=",label.get_content_height()," available=",label.size.y)
			if absf(label.position.y+label.size.y*0.5-slot.size.y*0.5)>1:
				overflow+=1
				print("TEXT_NOT_CENTERED ",id," line=",i)
			count+=1
		city.dialogue._leave()
		await get_tree().process_frame
	GameState.save_path=original
	GameState.load_game()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://puer-text-check.cfg"))
	print("PUER_TEXT_CHECK lines=",count," overflow=",overflow)
	get_tree().quit(overflow)
