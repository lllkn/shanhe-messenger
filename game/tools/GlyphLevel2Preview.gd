extends Control
const OUT := "user://technical-previews/"

func _ready() -> void:
	var scene = load("res://scenes/puzzles/PuzzleGlyph.tscn").instantiate()
	add_child(scene)
	scene._gs = PuzzleBase.MockGameState.new()
	scene.add_child(scene._gs)
	scene._intro_layer.queue_free()
	scene._level = 2
	scene._l1_root.visible = false
	scene._l2_root.visible = true
	await get_tree().create_timer(0.4).timeout
	await _shot("glyph_level2_polished.png")
	if "--interactive" in OS.get_cmdline_user_args():
		return
	var pids: Array = scene._page_correct_order.keys()
	var page: TextureRect = scene._pages[pids[0]]
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	scene._on_page_gui_input(down, page)
	page.position = scene._slots[1]["rect"].position - Vector2(0, 18)
	scene._refresh_slots(1)
	await get_tree().create_timer(0.1).timeout
	await _shot("glyph_level2_drag.png")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	scene._input(release)
	await get_tree().create_timer(0.35).timeout
	for pid in pids:
		var wrong_slot: int = 4 - int(scene._page_correct_order[pid])
		scene._pages[pid].position = scene._slots[wrong_slot]["rect"].position
		scene._drop_page(scene._pages[pid])
		await get_tree().create_timer(0.30).timeout
	scene._on_submit()
	await get_tree().create_timer(0.18).timeout
	await _shot("glyph_level2_wrong.png")
	await get_tree().create_timer(0.6).timeout
	for pid in pids:
		var correct: int = scene._page_correct_order[pid] - 1
		scene._pages[pid].position = scene._slots[correct]["rect"].position
		scene._drop_page(scene._pages[pid])
		await get_tree().create_timer(0.30).timeout
	scene._on_submit()
	await get_tree().create_timer(0.32).timeout
	await _shot("glyph_level2_success.png")
	await get_tree().create_timer(2.35).timeout
	await _shot("glyph_level2_result.png")
	get_tree().quit()

func _shot(file_name: String) -> void:
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OUT + file_name)
	print("saved ", file_name)
