class_name ContentDB
extends RefCounted
## 只读内容访问。各模块配置分开维护，地图和小游戏无需编辑其他模块。
static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed
	return {}

static func station(id: String) -> Dictionary:
	var data := read_json("res://data/journeys.json")
	return data.get("stations", {}).get(id, {})

static func fragment(id: String) -> Dictionary:
	return read_json("res://data/fragments.json").get("fragments", {}).get(id, {})

static func cinematic(id: String) -> Dictionary:
	if not valid_id(id):
		return {}
	return read_json("res://data/cinematics/" + id + ".json")

static func valid_id(id: String) -> bool:
	return not id.is_empty() and id == id.get_file() and not id.contains(".") and not id.contains(":")
