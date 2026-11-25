extends Node
func _ready() -> void:
	get_tree().current_scene = null
	GameState.save_path = "user://xianggelila-preview.cfg"
	GameState.reset_game()
	GameState.collect_fragment("frag_dongba_tea")
	SceneRouter.goto_station("xianggelila")
	await get_tree().process_frame
	while SceneRouter.is_switching(): await get_tree().process_frame
	var city := get_tree().current_scene
	while not city.walk_guide.ready: await get_tree().physics_frame
	await get_tree().create_timer(0.3).timeout
	city._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	var mode := OS.get_environment("XIANGGELILA_SHOT")
	if mode != "arrival" and city.dialogue != null:
		while city.dialogue != null: city.dialogue._continue()
		await get_tree().process_frame
	if mode in ["cloth", "visitor", "son"]:
		for item in city.hotspots:
			if item["id"] == mode:
				city.player.position = item["position"] + Vector3(0,0.1,1.4)
				city.camera_initialized = false
	elif mode in ["core", "farewell", "reward", "gate"]:
		for item in city.story["interviews"]: GameState.set_flag("clue/xianggelila/"+item["id"])
		city._refresh_progress()
		city.player.position = city.goal_position + Vector3(-1.4,0.1,0)
		city.camera_initialized = false
		await get_tree().physics_frame
		city._update_camera()
		if mode != "gate":
			if mode in ["farewell", "reward"]:
				for step in ["visit", "dye"]: GameState.set_flag("flow/xianggelila/"+step)
			city.interact()
			if mode == "reward":
				while city.dialogue != null: city.dialogue._continue()
			else:
				for i in 6: city.dialogue._continue()
	elif mode == "bridge":
		city.player.position = Vector3(-28.2,-0.1,12.3)
		city.yaw = -0.8
		city.camera_initialized = false
	elif mode == "pause":
		GameUI.open_pause()
	await get_tree().create_timer(0.6).timeout
	if is_instance_valid(GameUI._toast): GameUI._toast.hide()
	RenderingServer.force_draw()
	var dir := OS.get_environment("XIANGGELILA_SHOT_DIR")
	if dir.is_empty(): dir = "res://../drafts/xianggelila-chain-2026-10-10"
	var file := dir.path_join(("spawn" if mode.is_empty() else mode)+".png")
	var error := get_viewport().get_texture().get_image().save_png(file)
	print("XIANGGELILA_SHOT mode=",mode," error=",error," points=",city.guide_path.size()," player=",city.player.position," camera=",city.camera.position)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.save_path))
	get_tree().quit(error)
