extends SceneTree
## 无头测试：实例化 Main.tscn，检查按钮信号连接并模拟点击
## 运行：Godot --headless --script res://tests/test_main_scene.gd

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	# 手动挂 autoload（--script 模式下不会自动加载）
	var gs: Node = (load("res://autoload/GameState.gd") as GDScript).new()
	gs.name = "GameState"
	root.add_child(gs)
	var sr: Node = (load("res://autoload/SceneRouter.gd") as GDScript).new()
	sr.name = "SceneRouter"
	root.add_child(sr)

	var scene: PackedScene = load("res://tools/DebugMain.tscn")
	var main: Control = scene.instantiate()
	root.add_child(main)

	var btn: Button = main.get_node("Panel/Margin/VBox/ResetButton")
	print("[A] ResetButton 存在: ", btn != null)
	print("[B] pressed 连接数: ", btn.get_signal_connection_list("pressed").size())
	for conn in btn.get_signal_connection_list("pressed"):
		print("    -> ", conn["callable"])

	# 先制造一点进度
	gs.enter_station("lijiang")
	var idx: int = gs.station_index["lijiang"]
	for frag_id in gs.stations[idx]["fragments"]:
		gs.collect_fragment(frag_id)
	print("[C] 造进度: completed=", gs.completed, " fragments=", gs.fragments.size())

	# 模拟点击「重开新档」
	btn.pressed.connect(func(): print("[spy] pressed 信号已发出"))
	btn.pressed.emit()
	print("[D] 信号点击后: unlocked=", gs.unlocked, " completed=", gs.completed,
		" fragments=", gs.fragments.size())

	# 直接调处理函数对比
	main._on_reset_button_pressed()
	print("[D2] 直接调用后: unlocked=", gs.unlocked, " completed=", gs.completed,
		" fragments=", gs.fragments.size())

	# 直接在 gs 上调 reset_game
	gs.enter_station("lijiang")
	for frag_id in gs.stations[gs.station_index["lijiang"]]["fragments"]:
		gs.collect_fragment(frag_id)
	gs.reset_game()
	print("[D3] gs.reset_game 后: unlocked=", gs.unlocked, " completed=", gs.completed)

	# 检查 UI 行数是否重建
	var list: VBoxContainer = main.get_node("Panel/Margin/VBox/StationList")
	print("[E] StationList 子节点数: ", list.get_child_count())

	quit()
