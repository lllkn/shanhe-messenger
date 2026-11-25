class_name CityArrivalScreen
extends CanvasLayer
## 首次进入先呈现旁白：3D在后台准备，旁白关闭后才显示地图。
var active := false
var backdrop: Control

func _init() -> void:
	name = "CityArrivalScreen"
	layer = 19
	visible = false

func prepare(city: Node3D) -> void:
	var id: String = SceneRouter.params.get("station", city.station_id) if SceneRouter.current_key == "city" else city.station_id
	if GameState.is_unlocked(id) and not GameState.is_completed(id) and not GameState.has_flag("flow/"+id+"/arrival"):
		begin(city, id)

func begin(city: Node3D, station: String) -> void:
	if backdrop == null:
		backdrop = Control.new()
		backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(backdrop)
		# UiKit.background先铺完全不透明底色，背景图透明或缺失也不会露地图。
		UiKit.background(backdrop, ContentDB.station(station).get("preview", ""))
	active = true
	show()
	city.hide()

func finish(city: Node3D) -> void:
	if not active: return
	active = false
	hide()
	city.show()
