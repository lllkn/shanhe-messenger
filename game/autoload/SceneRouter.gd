extends Node
## 单一场景切换入口；先验证资源再提交参数，失败留在原场景。
signal scene_changed(scene_path: String)
signal navigation_failed(message: String)

const SCENES := {
	"home": "res://Main.tscn",
	"map": "res://scenes/MapScene.tscn",
	"station": "res://scenes/StationScene.tscn",
	"cine": "res://scenes/CineScene.tscn",
	"dialogue": "res://scenes/DialogueScene.tscn",
	"codex": "res://scenes/CodexScene.tscn",
	"finale": "res://scenes/FinaleScene.tscn",
	"puzzle_glyph": "res://scenes/puzzles/PuzzleGlyph.tscn",
	"puzzle_dye": "res://scenes/puzzles/PuzzleDye.tscn",
	"puzzle_pattern": "res://scenes/puzzles/PuzzlePattern.tscn",
	"puzzle_script": "res://scenes/puzzles/PuzzleScript.tscn",
	"puzzle_quilt": "res://scenes/puzzles/PuzzleQuilt.tscn",
}
const FADE_TIME := 0.25
var params: Dictionary = {}
var current_key := "home"
var _fade_rect: ColorRect
var _switching := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color.BLACK
	_fade_rect.modulate.a = 0.0
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade_rect)
	_resize()
	get_viewport().size_changed.connect(_resize)

func _resize() -> void:
	_fade_rect.size = get_viewport().get_visible_rect().size

func is_available(key: String) -> bool:
	return SCENES.has(key) and ResourceLoader.exists(SCENES[key])

func is_switching() -> bool:
	return _switching

func goto(key: String, p: Dictionary = {}) -> void:
	if not SCENES.has(key):
		navigation_failed.emit("尚未接入这个场景。")
		return
	goto_path(SCENES[key], p, key)

## 城市场景由 journeys.json 登记，必须是主工程内部资源。
func goto_path(path: String, p: Dictionary = {}, key: String = "city") -> void:
	if _switching:
		return
	if not path.begins_with("res://") or not ResourceLoader.exists(path):
		navigation_failed.emit("这段内容正在制作，接入后即可继续。")
		return
	var target := load(path) as PackedScene
	if target == null:
		navigation_failed.emit("场景暂时无法载入，请返回后重试。")
		return
	_switching = true
	get_tree().paused = false
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	await _fade(1.0)
	var previous := params.duplicate(true)
	params = p.duplicate(true)
	var previous_key := current_key
	current_key = key
	var err := get_tree().change_scene_to_packed(target)
	if err == OK:
		await get_tree().scene_changed
		current_key = key
	else:
		params = previous
		current_key = previous_key
		navigation_failed.emit("场景切换失败，请重试。")
	await _fade(0.0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_switching = false
	if err == OK:
		scene_changed.emit(path)

func _fade(alpha: float) -> void:
	var tween := create_tween()
	tween.tween_property(_fade_rect, "modulate:a", alpha, FADE_TIME)
	await tween.finished

func goto_map() -> void:
	goto("map")

func goto_station(id: String) -> void:
	if not GameState.is_unlocked(id):
		navigation_failed.emit("先完成前一站，再沿古道前行。")
		return
	JourneyFlow.open_city(id)

func goto_cine(id: String, extra: Dictionary = {}) -> void:
	var p := extra.duplicate(true)
	p["cine_id"] = id
	goto("cine", p)

func goto_dialogue(id: String, extra: Dictionary = {}) -> void:
	var p := extra.duplicate(true)
	p["dialogue_id"] = id
	goto("dialogue", p)

func goto_puzzle(id: String, extra: Dictionary = {}) -> void:
	var idx: int = GameState.station_index.get(id, -1)
	if idx < 0 or not GameState.is_unlocked(id):
		navigation_failed.emit("这处手艺还未解锁。")
		return
	var key: String = GameState.stations[idx].get("puzzle", "")
	if not is_available(key):
		navigation_failed.emit("本站小游戏正在制作，接入后即可体验。")
		return
	GameState.enter_station(id)
	var p := extra.duplicate(true)
	p["station"] = id
	goto(key, p)

func goto_codex() -> void:
	var return_params := params.duplicate(true)
	var scene := get_tree().current_scene
	if current_key == "city" and scene != null and scene.has_method("city_context"):
		return_params["city_context"] = scene.city_context()
	goto("codex", {"return_key": current_key, "return_params": return_params})

func goto_finale() -> void:
	if GameState.can_enter_finale():
		goto("finale")
	else:
		navigation_failed.emit("沿途的故事还未收齐。")
