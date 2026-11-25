extends Control
## 独立的第一关反馈截图，避免更改共用 ShotRunner。
const OUT := "user://technical-previews/"

func _ready() -> void:
	var scene = load("res://scenes/puzzles/PuzzleGlyph.tscn").instantiate()
	add_child(scene)
	scene._gs = PuzzleBase.MockGameState.new()
	scene.add_child(scene._gs)
	await get_tree().process_frame
	await get_tree().process_frame
	await _shot("glyph_font_intro.png")
	scene._on_intro_start()
	await get_tree().create_timer(0.8).timeout
	var correct: String = scene._pair_of_glyph[scene._current_glyph]
	for sid in scene._belt_cards:
		if sid != correct:
			scene._belt_cards[sid].position.y = 44
			scene._on_pick(sid)
			break
	await get_tree().create_timer(0.24).timeout
	await _shot("glyph_feedback_wrong.png")
	await get_tree().create_timer(0.95).timeout
	scene._belt_cards[correct].position.y = 44
	scene._on_pick(correct)
	await get_tree().create_timer(0.28).timeout
	await _shot("glyph_feedback_correct.png")
	await get_tree().create_timer(1.3).timeout
	for i in 5:
		scene._on_pick(scene._pair_of_glyph[scene._current_glyph])
		await get_tree().create_timer(1.5).timeout
	await get_tree().create_timer(0.9).timeout
	await _shot("glyph_level1_result.png")
	scene._continue_to_level2()
	await get_tree().create_timer(0.7).timeout
	await _shot("glyph_font_level2.png")
	for pid in scene._page_correct_order:
		scene._slots[scene._page_correct_order[pid] - 1]["page_id"] = pid
	scene._on_submit()
	await get_tree().create_timer(2.2).timeout
	await _shot("glyph_font_win.png")
	get_tree().quit()

func _shot(file_name: String) -> void:
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OUT + file_name)
	print("saved ", file_name)
