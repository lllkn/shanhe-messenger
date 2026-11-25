extends Node
const OUT := "res://../drafts/lijiang-characters-20261010/screenshots/"
var destination := ""
func _ready() -> void:
	get_tree().current_scene = null
	GameState.save_path = "user://lijiang-characters-preview.cfg"
	GameState.reset_game()
	destination = ProjectSettings.globalize_path("res://").path_join("../drafts/lijiang-characters-20261010/screenshots/")
	DirAccess.make_dir_recursive_absolute(destination)
	SceneRouter.goto_station("lijiang")
	while SceneRouter.is_switching(): await get_tree().process_frame
	var city := get_tree().current_scene
	while not city.walk_guide.ready: await get_tree().process_frame
	if city.dialogue != null: city.dialogue._leave()
	GameState.set_flag("flow/lijiang/arrival")
	for id in ["silver", "student", "inn", "dongba"]:
		for item in city.hotspots:
			if item["id"] != id: continue
			city.player.position = item["position"] + Vector3(0.9, 0.12, 1.5)
			city.yaw = 0
			city.pitch = 0.35
			city.distance = 5.0
			await get_tree().create_timer(0.3).timeout
			await shot("map-"+id+".png")
		city.open_conversation("lijiang_"+id if id != "dongba" else "lijiang_dongba_visit", "preview")
		await get_tree().process_frame
		city.dialogue._continue()
		await shot("dialogue-"+id+".png")
		if id == "dongba":
			city.dialogue._goto_line(8)
			city.dialogue._continue()
			await shot("phone-dark.png")
			city.dialogue.lijiang_stage.slider.value = 85
			await shot("phone-bright.png")
			city.dialogue.lijiang_stage._toggle_zoom()
			await shot("phone-zoom.png")
		city.dialogue._leave()
		await get_tree().process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.save_path))
	get_tree().quit()

func shot(file: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(destination.path_join(file))
	print("CHARACTER_SCREENSHOT ", file)
