extends SceneTree
## 无头测试：GameState 完整流程（完成站点 → 重开 → 重载）
## 运行：Godot --headless --script res://tests/test_gamestate.gd

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var gs: Node = (load("res://autoload/GameState.gd") as GDScript).new()
	root.add_child(gs)

	print("[1] 初始: unlocked=", gs.unlocked, " completed=", gs.completed)

	# 模拟集齐丽江碎片
	gs.enter_station("lijiang")
	var idx: int = gs.station_index["lijiang"]
	for frag_id in gs.stations[idx]["fragments"]:
		gs.collect_fragment(frag_id)
	print("[2] 丽江完成后: unlocked=", gs.unlocked, " completed=", gs.completed,
		" fragments=", gs.fragments.size(), " 收集率=", gs.get_completion_rate())

	# 重开新档
	gs.reset_game()
	print("[3] reset 后: unlocked=", gs.unlocked, " completed=", gs.completed,
		" fragments=", gs.fragments.size())

	# 模拟重启：新实例从磁盘读档
	var gs2: Node = (load("res://autoload/GameState.gd") as GDScript).new()
	root.add_child(gs2)
	print("[4] 重启读档后: unlocked=", gs2.unlocked, " completed=", gs2.completed,
		" fragments=", gs2.fragments.size())

	quit()
