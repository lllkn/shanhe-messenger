extends Control
## 旧站点入口兼容：进入城市出生点，主线操作由地图热点负责。
func _ready() -> void:
	var station: String = SceneRouter.params.get("station", GameState.current_station)
	if GameState.station_index.has(station):
		JourneyFlow.return_to_city.call_deferred(station)
	else:
		SceneRouter.goto_map.call_deferred()
