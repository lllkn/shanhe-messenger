extends Node
## 设置单独存储，不跟新游戏一起清空。
signal changed
const PATH := "user://settings.cfg"
var save_path := PATH
const DEFAULT_CAMERA_SENSITIVITY := 0.5
var camera_sensitivity := DEFAULT_CAMERA_SENSITIVITY
var volume := 0.8
var fullscreen := false
var text_speed := 1.0

func _ready() -> void:
	load_settings()

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(save_path) == OK:
		volume = clampf(float(cfg.get_value("ui", "volume", 0.8)), 0.0, 1.0)
		fullscreen = bool(cfg.get_value("ui", "fullscreen", false))
		text_speed = clampf(float(cfg.get_value("ui", "text_speed", 1.0)), 0.5, 3.0)
		camera_sensitivity = clampf(float(cfg.get_value("controls", "camera_sensitivity", DEFAULT_CAMERA_SENSITIVITY)), 0.25, 2.0)
	_apply()

func update(key: String, value: Variant) -> void:
	match key:
		"camera_sensitivity": camera_sensitivity = clampf(float(value), 0.25, 2.0)
		"volume": volume = clampf(float(value), 0.0, 1.0)
		"fullscreen": fullscreen = bool(value)
		"text_speed": text_speed = clampf(float(value), 0.5, 3.0)
	_apply()
	var cfg := ConfigFile.new()
	cfg.set_value("ui", "volume", volume)
	cfg.set_value("ui", "fullscreen", fullscreen)
	cfg.set_value("ui", "text_speed", text_speed)
	cfg.set_value("controls", "camera_sensitivity", camera_sensitivity)
	cfg.save(save_path)
	changed.emit()

func _apply() -> void:
	AudioServer.set_bus_volume_linear(0, volume)
	if DisplayServer.get_name() != "headless":
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)
