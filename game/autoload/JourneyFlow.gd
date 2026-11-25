extends Node
## 每站 flow 由数据编排。只有模块真实完成才标记步骤，未接素材不能自动跳过。
var active_station := ""
var active_step := ""

func step_done(station: String, step: Dictionary) -> bool:
	if step.get("type") == "puzzle":
		return GameState.is_puzzle_solved(station) or (step.get("defer_reward", false) and GameState.has_flag("flow/" + station + "/" + str(step.get("id", ""))))
	return GameState.has_flag("flow/" + station + "/" + str(step.get("id", "")))

func next_step(station: String) -> Dictionary:
	for step in ContentDB.station(station).get("flow", []):
		if not step_done(station, step):
			return step
	return {}

func begin(station: String) -> void:
	if not GameState.is_unlocked(station) or SceneRouter.is_switching():
		return
	GameState.enter_station(station)
	var step := next_step(station)
	if step.is_empty():
		SceneRouter.goto_station(station)
		return
	active_station = station
	active_step = step.get("id", "")
	var p := {"station": station, "flow_step": active_step}
	if step.get("defer_reward", false):
		p["defer_reward"] = true
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("city_context"):
		p["city_context"] = scene.city_context()
	elif SceneRouter.params.has("city_context"):
		p["city_context"] = SceneRouter.params["city_context"].duplicate(true)
	match step.get("type", ""):
		"dialogue": SceneRouter.goto_dialogue(step.get("content", ""), p)
		"cine": SceneRouter.goto_cine(step.get("content", ""), p)
		"puzzle": SceneRouter.goto_puzzle(station, p)
		"map": open_city(station)
		_: SceneRouter.navigation_failed.emit("这段旅程尚未接入。")

func complete_current() -> void:
	var station: String = SceneRouter.params.get("station", "")
	var step_id: String = SceneRouter.params.get("flow_step", "")
	if station.is_empty() or step_id.is_empty():
		return
	GameState.set_flag("flow/" + station + "/" + step_id)
	active_station = ""
	active_step = ""
	# 完成后回到地图原地点，由地图内交互触发下一步。
	return_to_city(station)

func return_to_city(station: String) -> void:
	var extra := {}
	if SceneRouter.params.has("city_context"):
		extra["city_context"] = SceneRouter.params["city_context"].duplicate(true)
	open_city(station, extra)

func open_city(station: String, extra: Dictionary = {}) -> void:
	if not GameState.is_unlocked(station):
		return
	var path: String = ContentDB.station(station).get("map_scene", "")
	if path.is_empty():
		SceneRouter.navigation_failed.emit("本站地图正在制作，接入后即可漫游。")
		return
	GameState.enter_station(station)
	var p := extra.duplicate(true)
	p["station"] = station
	SceneRouter.goto_path(path, p, "city")

func dispatch(destination: Dictionary) -> void:
	var context: Dictionary = {}
	if SceneRouter.params.has("flow_step"):
		context = {"station": SceneRouter.params.get("station", ""), "flow_step": SceneRouter.params["flow_step"]}
	if SceneRouter.params.has("city_context"):
		context["city_context"] = SceneRouter.params["city_context"].duplicate(true)
	match destination.get("type", "map"):
		"map": SceneRouter.goto_map()
		"station": SceneRouter.goto_station(destination.get("station", GameState.current_station))
		"puzzle": SceneRouter.goto_puzzle(destination.get("station", GameState.current_station), context)
		"cine": SceneRouter.goto_cine(destination.get("cine_id", ""), context)
		"dialogue": SceneRouter.goto_dialogue(destination.get("dialogue_id", ""), context)
		"finale": SceneRouter.goto_finale()

func apply_action(action: Dictionary) -> void:
	match action.get("type", ""):
		"flag": GameState.set_flag(action.get("key", ""), action.get("value", true))
		"fragment": GameState.collect_fragment(action.get("id", ""))
		"choice": GameState.record_choice(action.get("cine", ""), int(action.get("index", 0)))
