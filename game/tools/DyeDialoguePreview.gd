extends Control
var puzzle: Node
const OUTPUT := "res://visual-previews/dye-dialogue/"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	puzzle = load("res://scenes/puzzles/PuzzleDye.tscn").instantiate()
	add_child(puzzle)
	if OS.get_cmdline_user_args().has("--knowledge-only"):
		puzzle._on_intro_start()
		puzzle._l1_done = true
		puzzle._enter_level2()
		puzzle._l2_all_done = true
		puzzle._complete()
		await get_tree().create_timer(2.5).timeout
		await _shot("07-knowledge-cards")
		get_tree().quit()
		return
	await _shot("01-start-bubble")
	puzzle._on_intro_start()
	puzzle._select_no(4)
	await _shot("02-color-bubble")
	puzzle._debug_fill_all()
	await get_tree().create_timer(1.8).timeout
	await _shot("03-stage-bubble")
	puzzle._enter_level2()
	await _shot("04-dye-bubble")
	puzzle._debug_commit("青")
	await get_tree().create_timer(1.3).timeout
	puzzle._mouse_pressed = true
	puzzle._mouse_position = puzzle._water_center() + Vector2(52, 0)
	puzzle._stir_acc = TAU
	puzzle._stir_impulse = 0.12
	await _shot("05-stir-bubble")
	puzzle._mouse_pressed = false
	puzzle._stir_timeout()
	await get_tree().create_timer(0.55).timeout
	await _shot("06-retry-bubble")
	puzzle._action_button.visible = false
	puzzle._phase = "done"
	puzzle._l2_all_done = true
	puzzle._step = puzzle._order.size()
	puzzle._update_progress()
	puzzle._complete()
	await get_tree().create_timer(2.5).timeout
	await _shot("07-knowledge-cards")
	get_tree().quit()

func _shot(name: String) -> void:
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUTPUT + name + ".png")
	print("SHOT ", name)
