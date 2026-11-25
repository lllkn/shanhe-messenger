extends Node
## 检查六句约定在整理、排序、结算三个尺寸下均不溢出纸面。
func _ready() -> void:
	var puzzle = load("res://scenes/puzzles/PuzzleScript.tscn").instantiate()
	add_child(puzzle)
	var failures := 0
	for dimensions in [Vector2(292, 70), Vector2(326, 78), Vector2(268, 62)]:
		for leaf_id in puzzle._correct_order:
			var leaf: Control = puzzle._make_leaf(puzzle._text_of[leaf_id], dimensions, true, 23)
			puzzle.add_child(leaf)
			await get_tree().process_frame
			await get_tree().process_frame
			for child in leaf.get_children():
				if child is Label:
					var fits: bool = child.size.x <= dimensions.x * 0.8 + 0.1 and child.size.y <= dimensions.y * 0.8 + 0.1
					if not fits:
						failures += 1
						printerr("FAIL: ", leaf_id, " / ", dimensions, " text: ", child.size)
			leaf.queue_free()
	print("PASS: 六句约定在三个尺寸下均完整落在纸面内" if failures == 0 else "FAIL: 文字溢出")
	get_tree().quit(failures)
