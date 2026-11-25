extends Node
func _ready() -> void:
	get_tree().current_scene = null
	GameState.save_path = "user://lijiang-preview.cfg"
	GameState.reset_game()
	SceneRouter.goto_station("lijiang")
	await get_tree().process_frame
	while SceneRouter.is_switching(): await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout
	var city := get_tree().current_scene
	city._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	var mode := OS.get_environment("LIJIANG_SHOT")
	print("PREVIEW_STEP mode=", mode, " dialog=", city.dialogue)
	if mode != "arrival" and city.dialogue != null:
		while city.dialogue != null: city.dialogue._continue()
		await get_tree().process_frame
	if mode == "silver":
		city.player.position = city.anchor_position("NPC_01_SilverShopSister") + Vector3(0, 0.1, 1.5)
		city.camera_initialized = false
	elif mode in ["dongba", "core"]:
		for item in city.story["interviews"]: GameState.set_flag("clue/lijiang/" + item["id"])
		city._refresh_progress()
		city.player.position = city.goal_position + Vector3(0, 0.1, 1.5)
		city.camera_initialized = false
		await get_tree().physics_frame
		city._update_camera()
		if mode == "core":
			city.interact()
			for i in 3: city.dialogue._continue()
			print("PREVIEW_STEP opened=", city.dialogue)
	elif mode in ["farewell", "reward"]:
		for item in city.story["interviews"]: GameState.set_flag("clue/lijiang/" + item["id"])
		for step in ["arrival", "interviews", "dongba_visit", "glyph"]: GameState.set_flag("flow/lijiang/" + step)
		city._refresh_progress()
		city.player.position = city.goal_position + Vector3(0, 0.1, 1.5)
		city.camera_initialized = false
		await get_tree().physics_frame
		city._update_camera()
		city.interact()
		if mode == "reward":
			while city.dialogue != null: city.dialogue._continue()
		else:
			for i in 3: city.dialogue._continue()
	elif mode == "square":
		city.player.position = city.anchor_position("HUB_SifangSquare") + Vector3(0, 0.2, 1.5)
		city.camera_initialized = false
	elif mode == "pause":
		GameUI.open_pause()
	print("PREVIEW_STEP waiting_draw paused=", get_tree().paused)
	await get_tree().create_timer(0.6).timeout
	if is_instance_valid(GameUI._toast): GameUI._toast.hide()
	print("PREVIEW_STEP drawing")
	RenderingServer.force_draw()
	var output_dir := OS.get_environment("LIJIANG_SHOT_DIR")
	if output_dir.is_empty(): output_dir = "res://../drafts/lijiang-chain-2026-10-09"
	var output := output_dir.path_join("%s.png" % ("spawn" if mode.is_empty() else mode))
	var err := get_viewport().get_texture().get_image().save_png(output)
	print("LIJIANG_SHOT ", mode, " error=", err, " guide_points=", city.guide_path.size())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.save_path))
	get_tree().quit(err)
