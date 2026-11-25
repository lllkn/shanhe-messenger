extends Node
## GameState —— 全局状态中心（autoload）
## 管：站点解锁/完成、碎片收集、影游抉择记录、存档读写
## 数据来源：res://data/stations.json（站点顺序与碎片归属全由配置决定）

signal fragment_collected(fragment_id: String)
signal station_completed(station_id: String)
signal station_unlocked(station_id: String)
signal choice_recorded(cine_id: String, choice_index: int)
signal progress_changed

const SAVE_PATH := "user://save.cfg"
var save_path: String = SAVE_PATH  # 测试可切换到独立存档，玩家仍使用原路径
const STATIONS_PATH := "res://data/stations.json"

## 站点配置（从 JSON 读入，运行时只读）
var stations: Array = []          # [{id, name, puzzle, fragments, cine}, ...] 按解锁顺序
var station_index: Dictionary = {}  # id -> 下标

## 运行时进度
var unlocked: Array[String] = []    # 已解锁站点 id（按顺序）
var completed: Array[String] = []   # 已完成（碎片集齐）站点 id
var fragments: Dictionary = {}      # fragment_id -> true
var choices: Dictionary = {}        # cine_id -> choice_index
var current_station: String = ""    # 玩家当前所在站
var flags: Dictionary = {}          # 剧情标记（对话分支用，如"已递介绍信"）

func _ready() -> void:
	_load_stations()
	load_game()

# ---------- 配置 ----------

func _load_stations() -> void:
	var file := FileAccess.open(STATIONS_PATH, FileAccess.READ)
	if file == null:
		push_error("GameState: 找不到 " + STATIONS_PATH)
		return
	var data: Variant = JSON.parse_string(file.get_as_text())
	if data == null or not data.has("stations"):
		push_error("GameState: stations.json 解析失败")
		return
	stations = data["stations"]
	for i in stations.size():
		station_index[stations[i]["id"]] = i

# ---------- 进度操作 ----------

func is_unlocked(station_id: String) -> bool:
	return station_id in unlocked

func is_completed(station_id: String) -> bool:
	return station_id in completed

## 进站（从地图热点调用）
func enter_station(station_id: String) -> void:
	if not is_unlocked(station_id):
		push_warning("GameState: 站点未解锁 " + station_id)
		return
	current_station = station_id
	save_game()

## 收集碎片（小游戏通关 / 影游分支奖励时调用）
func collect_fragment(fragment_id: String) -> void:
	var owner := ""
	for st in stations:
		if fragment_id in st.get("fragments", []):
			owner = st["id"]
			break
	if owner.is_empty() or not is_unlocked(owner):
		return
	if fragments.has(fragment_id):
		return
	fragments[fragment_id] = true
	fragment_collected.emit(fragment_id)
	# 检查所在站是否集齐
	if station_fragments_complete(owner):
		complete_station(owner)
	progress_changed.emit()
	save_game()

## 记录影游抉择（不影响碎片能否拿到，只影响结局变体）
func record_choice(cine_id: String, choice_index: int) -> void:
	choices[cine_id] = choice_index
	choice_recorded.emit(cine_id, choice_index)
	save_game()

## 某站碎片是否集齐
func station_fragments_complete(station_id: String) -> bool:
	var idx: int = station_index.get(station_id, -1)
	if idx < 0:
		return false
	for frag_id in stations[idx].get("fragments", []):
		if not fragments.has(frag_id):
			return false
	return true

## 完成站点 → 解锁下一站
func complete_station(station_id: String) -> void:
	if station_id in completed or not station_index.has(station_id) or not is_unlocked(station_id):
		return
	if not station_fragments_complete(station_id):
		return
	completed.append(station_id)
	station_completed.emit(station_id)
	var idx: int = station_index.get(station_id, -1)
	if idx >= 0 and idx + 1 < stations.size():
		var next_id: String = stations[idx + 1]["id"]
		if next_id not in unlocked:
			unlocked.append(next_id)
			station_unlocked.emit(next_id)
	progress_changed.emit()
	save_game()

## 剧情标记
func set_flag(key: String, value: bool = true) -> void:
	if key.is_empty():
		return
	flags[key] = value
	save_game()

func has_flag(key: String) -> bool:
	return flags.get(key, false)

## 收集率 0.0~1.0（终章结局分档用）
func get_total_fragment_count() -> int:
	var total := 0
	for st in stations:
		total += st.get("fragments", []).size()
	return total

func get_completion_rate() -> float:
	var total := get_total_fragment_count()
	return 0.0 if total == 0 else float(fragments.size()) / float(total)

## 是否可进终章（五站全完成）
func can_enter_finale() -> bool:
	return not stations.is_empty() and completed.size() >= stations.size()

# ---------- 存档 ----------

func save_game() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "unlocked", unlocked)
	cfg.set_value("progress", "completed", completed)
	cfg.set_value("progress", "fragments", fragments.keys())
	cfg.set_value("progress", "choices", choices)
	cfg.set_value("progress", "flags", flags)
	cfg.set_value("progress", "current_station", current_station)
	var err := cfg.save(save_path)
	if err != OK:
		push_error("GameState: 存档写入失败 err=" + str(err))

func load_game() -> void:
	unlocked.clear()
	completed.clear()
	fragments.clear()
	choices.clear()
	flags.clear()
	current_station = ""
	# 首站永远解锁
	if stations.size() > 0 and unlocked.is_empty():
		unlocked.append(stations[0]["id"])
	var cfg := ConfigFile.new()
	if cfg.load(save_path) != OK:
		return  # 无存档 = 新游戏
	unlocked.assign(cfg.get_value("progress", "unlocked", unlocked))
	completed.assign(cfg.get_value("progress", "completed", []))
	for frag_id in cfg.get_value("progress", "fragments", []):
		fragments[frag_id] = true
	choices = cfg.get_value("progress", "choices", {})
	flags = cfg.get_value("progress", "flags", {})
	current_station = cfg.get_value("progress", "current_station", "")
	unlocked.assign(unlocked.filter(func(id): return station_index.has(id)))
	completed.assign(completed.filter(func(id): return station_index.has(id)))
	if not stations.is_empty() and stations[0]["id"] not in unlocked:
		unlocked.push_front(stations[0]["id"])
	var valid_fragments: Array = []
	for st in stations:
		valid_fragments.append_array(st.get("fragments", []))
	for id in fragments.keys():
		if id not in valid_fragments:
			fragments.erase(id)
	if not is_unlocked(current_station):
		current_station = ""

## 重开新档
func reset_game() -> void:
	completed.clear()
	fragments.clear()
	choices.clear()
	flags.clear()
	current_station = ""
	unlocked.clear()
	if stations.size() > 0:
		unlocked.append(stations[0]["id"])
	save_game()  # 把清空后的状态正式写盘（覆盖旧档）
	progress_changed.emit()
	print("GameState: 已重开新档")

# ---------- 小游戏白名单（接口约定 v2 §五，小游戏只允许调用以下函数） ----------

func has_fragment(id: String) -> bool:
	return fragments.has(id)

func get_fragments() -> Array:
	return fragments.keys()

func get_fragment_count() -> int:
	return fragments.size()

func is_puzzle_solved(station_id: String) -> bool:
	return is_completed(station_id)

func add_fragment(id: String) -> void:
	collect_fragment(id)  # 幂等 + 自动存档由 collect_fragment 保证

func mark_puzzle_solved(station_id: String) -> void:
	complete_station(station_id)

## 结局判定（仅古城拼锦完成时调用）
## 接口约定 v2：4 片全 = kaiguan《开馆》；3 片 = zhicheng《织成》；其余 = cundang《存档》
func evaluate_ending() -> String:
	var count := get_fragment_count()
	if count >= 4:
		return "kaiguan"
	elif count == 3:
		return "zhicheng"
	else:
		return "cundang"
