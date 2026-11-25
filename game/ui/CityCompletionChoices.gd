extends RefCounted
## 城市探索结束后的共用引导；下一站沿用站点配置的旅程顺序。
static func add_to(parent: Control, station: String, on_stay: Callable) -> void:
	var choices := VBoxContainer.new()
	choices.name = "CompletionChoices"
	choices.add_theme_constant_override("separation", 12)
	parent.add_child(choices)
	choices.add_child(UiKit.button("继续探索", on_stay))
	var index: int = GameState.station_index.get(station, -1)
	var next_station: String = GameState.stations[index + 1]["id"] if index >= 0 and index + 1 < GameState.stations.size() else ""
	var next := UiKit.button("去下一个地方", func(): SceneRouter.goto_station(next_station), true)
	next.disabled = next_station.is_empty() or not GameState.is_unlocked(next_station)
	if not next_station.is_empty():
		next.tooltip_text = "前往" + str(GameState.stations[index + 1]["name"])
	choices.add_child(next)
	choices.add_child(UiKit.button("返回旅途长卷", func(): SceneRouter.goto_map()))
