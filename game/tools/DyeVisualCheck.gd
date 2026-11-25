extends Control
## Run the real scene with pointer events, collect screenshots, and check state.
const OUTPUT := "res://visual-previews/dye/"
var puzzle: Node
var failed := false

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	puzzle = load("res://scenes/puzzles/PuzzleDye.tscn").instantiate()
	add_child(puzzle)
	await _wait(0.6)
	_check(puzzle._intro_layer != null and puzzle._start_button.is_visible_in_tree(), "start has a clear instruction page and large button")
	await _shot("01-start")
	await _click_action()
	await _wait(0.5)
	_check(puzzle._started and puzzle._level == 1, "start button opens level one")
	var local_point := Vector2(282, 190)
	var id: String = puzzle._hit_region(local_point)
	var point: Vector2 = local_point + puzzle._pattern_root.position
	puzzle._select_no(puzzle._region_no[id])
	await _move(point)
	await _wait(0.25)
	_check(str(puzzle._speech.get("_last_text")).contains(puzzle._color_of_no[puzzle._region_no[id]]), "NPC bubble describes the hovered color")
	await _shot("02-fill-hover")
	await _press(point)
	await _release(point)
	_check(puzzle._filled.has(id), "pointer fills the matching region")
	# Undo before the fill tween has finished.
	puzzle._undo()
	await _wait(0.25)
	_check(not puzzle._filled.has(id) and puzzle._region_labels[id].visible, "immediate undo restores region and number")
	puzzle._select_no(5 if puzzle._region_no[id] != 5 else 1)
	await _press(point)
	await _release(point)
	_check(not puzzle._filled.has(id), "wrong paint leaves the region unfilled")
	_check(str(puzzle._speech.get("_last_text")).contains("需要"), "wrong paint is explained by the NPC")
	puzzle._debug_fill_first(24)
	await _wait(0.35)
	await _shot("03-fill-mid")
	puzzle._debug_fill_all()
	await _wait(2.2)
	_check(puzzle._filled.size() == puzzle._region_order.size(), "all regions filled without duplicate count")
	_check(puzzle._modal_layer == null and puzzle._action_button.visible, "stage transition stays in the scene with a speech bubble")
	await _shot("04-stage-clear")
	await _click_action()
	await _wait(0.5)
	_check(puzzle._level == 2 and puzzle._phase == "idle", "stage button opens level two")
	_check(puzzle._modal_layer == null and str(puzzle._speech.get("_last_text")).contains("蓝靛"), "NPC names the next ingredient without a permanent chant card")
	await _shot("05-vat-idle")
	# Wrong ingredient is locked while feedback runs.
	puzzle._debug_commit("黑")
	puzzle._debug_commit("青")
	await _wait(0.6)
	_check(puzzle._step == 0 and puzzle._phase == "idle", "wrong ingredient cannot race a correct one")
	# Drag the material with actual GUI pointer events.
	var card: Control = puzzle._lot_cards["dye_indigo"]
	var source := card.global_position + card.size * 0.5
	var target: Vector2 = puzzle._water_center()
	await _move(source)
	await _press(source)
	await _move((source + target) * 0.5)
	await _move(target)
	await _release(target)
	await _wait(1.4)
	_check(puzzle._phase == "stir", "material drag starts the stirring phase")
	_check(str(puzzle._speech.get("_last_text")).contains("按住"), "NPC explains stirring as the phase begins")
	# Stationary press cannot earn progress.
	var start: Vector2 = puzzle._water_center() + Vector2(puzzle._water.size.x * 0.35, 0)
	await _move(start)
	await _press(start)
	await _wait(0.2)
	var earned: float = puzzle._stir_acc
	await _wait(0.2)
	_check(is_equal_approx(earned, puzzle._stir_acc), "stationary press does not stir")
	await _release(start)
	await _drive_stir(false, true)
	await _wait(0.8)
	_check(puzzle._step == 1 and puzzle._phase == "idle", "clockwise mouse orbit completes one color")
	await _shot("07-color-complete")
	puzzle._debug_commit("赤")
	await _wait(1.4)
	puzzle._stir_left = 0.01
	await _wait(0.75)
	_check(puzzle._phase == "retry" and puzzle._step == 1, "timeout opens one retry and keeps previous color")
	_check(puzzle._modal_layer == null and puzzle._action_button.visible, "retry uses a short NPC bubble and button")
	var retry_action: Callable = puzzle._action
	await _wait(0.3)
	_check(puzzle._action == retry_action, "retry action is not recreated each frame")
	await _shot("08-retry")
	await _click_action()
	await _wait(0.1)
	_check(puzzle._phase == "stir" and puzzle._step == 1, "retry continues the same ingredient")
	await _drive_stir(true, false)
	await _wait(0.8)
	_check(puzzle._step == 2, "counterclockwise orbit also works")
	for color in ["黄", "白", "黑"]:
		puzzle._debug_commit(color)
		await _wait(1.4)
		await _drive_stir(false, false)
		await _wait(0.8)
	await _wait(2.1)
	_check(puzzle._check_win() and puzzle._finished, "all five colors reach victory")
	_check(puzzle._gs.get_fragment_count() == 1, "completion awards exactly one fragment")
	puzzle._complete()
	_check(puzzle._gs.get_fragment_count() == 1, "duplicate completion does not award again")
	await _wait(0.5)
	_check(is_instance_valid(puzzle._modal_layer) and is_instance_valid(puzzle._knowledge_continue), "knowledge cards appear only after both levels are complete")
	await _shot("09-win")
	print("DYE_CHECK ", "FAIL" if failed else "PASS")
	get_tree().quit(1 if failed else 0)

func _check(condition: bool, message: String) -> void:
	print("PASS " if condition else "FAIL ", message)
	failed = failed or not condition

func _click_action() -> void:
	var button: Button = puzzle._action_button if puzzle._started else puzzle._start_button
	if not is_instance_valid(button) or not button.visible:
		_check(false, "NPC action button exists")
		return
	var point := button.get_global_transform() * (button.size * 0.5)
	await _move(point)
	await _press(point)
	await _release(point)

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func _motion_at(pos: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = pos
	event.global_position = pos
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if puzzle._mouse_pressed else 0
	get_viewport().push_input(event, true)

func _move(pos: Vector2) -> void:
	_motion_at(pos)
	await get_tree().process_frame

func _press(pos: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = pos
	event.global_position = pos
	get_viewport().push_input(event, true)
	await get_tree().process_frame

func _release(pos: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = false
	event.position = pos
	event.global_position = pos
	get_viewport().push_input(event, true)
	await get_tree().process_frame

func _drive_stir(reverse: bool, capture: bool) -> void:
	var center: Vector2 = puzzle._water_center()
	var radius: Vector2 = puzzle._water.size * Vector2(0.35, 0.34)
	await _move(center + Vector2(radius.x, 0))
	await _press(center + Vector2(radius.x, 0))
	var started_at := Time.get_ticks_msec()
	var captured := false
	var previous_angle := 0.0
	while puzzle._phase == "stir" and Time.get_ticks_msec() - started_at < 3000:
		var seconds := float(Time.get_ticks_msec() - started_at) / 1000.0
		var angle := seconds * TAU * 1.1 * (-1.0 if reverse else 1.0)
		var segments := maxi(1, ceili(absf(angle - previous_angle) / 0.1))
		for j in segments:
			var intermediate := lerpf(previous_angle, angle, float(j + 1) / segments)
			_motion_at(center + Vector2(cos(intermediate), sin(intermediate)) * radius)
		previous_angle = angle
		await get_tree().process_frame
		if capture and not captured and puzzle._stir_acc / TAU >= 0.9:
			await _shot("06-stir-active")
			captured = true

	await _release(center + Vector2(radius.x, 0))

func _shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUTPUT + name + ".png")
	print("SHOT ", name)
