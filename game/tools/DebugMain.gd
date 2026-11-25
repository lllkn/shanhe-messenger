extends Control
## Main —— 地基冒烟测试场景（临时主场景）
## 验证：GameState 存档 + 进度流转 + SceneRouter 注册表
## 正式 MapScene 做好后，project.godot 的 run/main_scene 改过去即可

@onready var station_list: VBoxContainer = $Panel/Margin/VBox/StationList
@onready var info_label: Label = $Panel/Margin/VBox/InfoLabel

func _ready() -> void:
	GameState.progress_changed.connect(_refresh)
	_refresh()
	info_label.text = "存档路径: " + ProjectSettings.globalize_path(GameState.SAVE_PATH)

func _refresh() -> void:
	for child in station_list.get_children():
		child.queue_free()
	for st in GameState.stations:
		var row := HBoxContainer.new()
		var state_text := "🔒 雾封"
		if GameState.is_completed(st["id"]):
			state_text = "✅ 已完成"
		elif GameState.is_unlocked(st["id"]):
			state_text = "🟢 已解锁"
		var label := Label.new()
		label.text = "%s（%s）  %s" % [st["name"], st["theme"], state_text]
		row.add_child(label)
		# 测试按钮：模拟"集齐本站碎片"
		if GameState.is_unlocked(st["id"]) and not GameState.is_completed(st["id"]):
			var btn := Button.new()
			btn.text = "模拟集齐碎片"
			btn.pressed.connect(_simulate_complete.bind(st["id"]))
			row.add_child(btn)
		station_list.add_child(row)
	var rate := Label.new()
	rate.text = "总收集率：%.0f%%（碎片 %d 片）" % [GameState.get_completion_rate() * 100.0, GameState.fragments.size()]
	station_list.add_child(rate)

func _simulate_complete(station_id: String) -> void:
	GameState.enter_station(station_id)
	var idx: int = GameState.station_index[station_id]
	for frag_id in GameState.stations[idx]["fragments"]:
		GameState.collect_fragment(frag_id)

func _on_reset_button_pressed() -> void:
	print("Main: 重开按钮被点击")
	GameState.reset_game()
	_refresh()

func _on_dialogue_button_pressed() -> void:
	SceneRouter.goto_dialogue("sample_lijiang")
