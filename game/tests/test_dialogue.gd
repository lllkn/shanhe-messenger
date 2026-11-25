extends SceneTree
## 无头测试：DialogueScene 全流程（打字机/选项/跳转/结束回调）

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var sr: Node = root.get_node_or_null("/root/SceneRouter")
	var gs: Node = root.get_node_or_null("/root/GameState")
	print("[A] autoload: SceneRouter=", sr != null, " GameState=", gs != null)
	if sr == null:
		quit()
		return
	sr.params = {"dialogue_id": "sample_lijiang"}

	var dlg: Control = (load("res://scenes/DialogueScene.tscn") as PackedScene).instantiate()
	root.add_child(dlg)
	await process_frame
	await process_frame
	print("[B] 载入: dialogue_id=", dlg.dialogue_id, " 行数=", dlg.lines.size(),
		" 当前行=", dlg.line_idx)

	var guard := 0
	while not dlg._finished and guard < 60:
		if dlg._has_choices():
			print("    [选项] 行 ", dlg.line_idx, " → 选 0")
			dlg._choose(0)
		else:
			dlg._continue()
		await process_frame
		guard += 1

	print("[C] 结束: finished=", dlg._finished, " 步数=", guard)
	if gs:
		print("[D] flags=", gs.flags, " fragments=", gs.fragments.size())
	quit()
