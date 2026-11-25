class_name CityAdapter
extends Node
## 挂在已接入的3D城市场景下。场景自管玩家/碰撞/相机，热点调用此适配器。
signal station_progress_changed
@export var station_id: String = ""

func _ready() -> void:
	if SceneRouter.current_key == "city":
		station_id = SceneRouter.params.get("station", station_id)
	GameState.progress_changed.connect(func(): station_progress_changed.emit())

func is_accessible() -> bool:
	return GameState.is_unlocked(station_id)

func open_puzzle() -> void:
	if is_accessible():
		JourneyFlow.begin(station_id)

func open_dialogue(id: String) -> void:
	if is_accessible():
		SceneRouter.goto_dialogue(id, {"station": station_id})

func open_cine(id: String) -> void:
	if is_accessible():
		SceneRouter.goto_cine(id, {"station": station_id})

func resume_story() -> void:
	if is_accessible():
		JourneyFlow.begin(station_id)

func finish_exploration() -> void:
	# 只在地图负责的探索条件真实达成后调用。不能凭打开地图就记完成。
	var step := JourneyFlow.next_step(station_id)
	if is_accessible() and step.get("type") == "map":
		GameState.set_flag("flow/" + station_id + "/" + str(step.get("id", "")))

func return_to_journey() -> void:
	JourneyFlow.return_to_city(station_id)
