extends Node
## 真实鼠标事件回归：独立实例使用基类的内存进度，不写玩家存档。
var puzzle: Control
var failures := 0
func check(ok: bool, title: String) -> void:
	print("PASS " if ok else "FAIL ", title)
	if not ok: failures += 1
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		seed(int(args[0]))
	puzzle = load("res://scenes/puzzles/PuzzleScript.tscn").instantiate()
	add_child(puzzle)
	await get_tree().create_timer(0.7).timeout
	await click(Vector2(640, 536))
	check(puzzle._level == 1, "鼠标点击开始进入第一关")
	await get_tree().create_timer(1.0).timeout
	var id: String = puzzle._volume_ids[0]
	var card: Button = puzzle._l1_cards[id]
	await click(card.get_global_transform() * (card.size * 0.5))
	check(puzzle._l1_picked.has(id), "鼠标点击文字区域选中贝叶")
	await get_tree().create_timer(0.3).timeout
	await click(card.get_global_transform() * (card.size * 0.5))
	check(not puzzle._l1_picked.has(id), "鼠标再次点击取消选中")
	await get_tree().create_timer(0.3).timeout
	await click((card.get_meta("home") as Vector2) + Vector2(card.size.x * 0.5, card.size.y - 2))
	check(puzzle._l1_picked.has(id), "鼠标点击贝叶下缘也能选中")
	await get_tree().create_timer(0.3).timeout
	for leaf_id in puzzle._volume_ids:
		if not puzzle._l1_picked.has(leaf_id):
			var leaf: Button = puzzle._l1_cards[leaf_id]
			await click(leaf.get_global_transform() * (leaf.size * 0.5))
	await get_tree().create_timer(1.0).timeout
	check(puzzle._hole_marks.size() == 2, "选齐后出现两个打孔点")
	for i in 2:
		var mark: Control = puzzle._hole_marks[i]
		var local_center := mark.position + mark.size * 0.5
		var expected := Vector2(puzzle._punch_leaf.size.x * (0.07 if i == 0 else 0.93), puzzle._punch_leaf.size.y * 0.5)
		check(local_center.is_equal_approx(expected), "孔位对齐贝叶端点 %d" % i)
		await click(mark.get_global_transform() * (mark.size * 0.5))
		check(mark.get_meta("done", false), "鼠标点击孔位触发打孔 %d" % i)
	await get_tree().create_timer(2.0).timeout
	check(puzzle._level == 2, "打孔后进入排序")
	get_tree().quit(failures)
func click(pos: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	get_viewport().push_input(motion, true)
	await get_tree().create_timer(0.25).timeout
	get_viewport().push_input(motion, true)
	await get_tree().process_frame
	var down := InputEventMouseButton.new()
	down.position = pos
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	get_viewport().push_input(down, true)
	await get_tree().process_frame
	var up := InputEventMouseButton.new()
	up.position = pos
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	get_viewport().push_input(up, true)
	await get_tree().process_frame
