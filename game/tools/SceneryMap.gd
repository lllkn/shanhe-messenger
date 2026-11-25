extends "res://scenes/cities/CityScene.gd"
## 复用游戏地图与环境，省略玩家、任务和剧情。
func _ready() -> void:
	spec = ContentDB.station(station_id).get("city", {})
	if not _load_map():
		push_error("地图载入失败：" + station_id)
		return
	_build_environment()
	if station_id in ["lijiang", "gucheng"]:
		for mesh in map_root.find_children("B_05_*", "MeshInstance3D", true, false):
			mesh.hide()
	_build_map_dynamics.call_deferred()
func _process(_delta: float) -> void:
	pass
func _unhandled_input(_event: InputEvent) -> void:
	pass
