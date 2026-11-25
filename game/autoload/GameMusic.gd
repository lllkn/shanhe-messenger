extends Node
## 常驻单轨配乐；相同曲目不断播，换曲先淡出再淡入，视频使用自身音轨。
const TRACKS := {
	"home": "res://assets/audio/bgm/home.ogg",
	"lijiang": "res://assets/audio/bgm/lijiang.ogg",
	"dali": "res://assets/audio/bgm/dali.ogg",
	"puer": "res://assets/audio/bgm/puer.ogg",
	"xianggelila": "res://assets/audio/bgm/xianggelila.ogg",
}
const MUSIC_DB := -12.0
const SILENCE_DB := -60.0
var current_track := ""
var player: AudioStreamPlayer
var _transition: Tween
var _closing := false

func _ready() -> void:
	player = AudioStreamPlayer.new()
	player.name = "BackgroundMusic"
	player.volume_db = SILENCE_DB
	add_child(player)
	get_tree().scene_changed.connect(_sync_scene)
	# 播放器的 stop 需经过音频线程处理，再退出可释放正在解码的 Ogg。
	get_tree().auto_accept_quit = false
	get_tree().root.close_requested.connect(_close_game)
	_sync_scene.call_deferred()

func _close_game() -> void:
	if _closing:
		return
	_closing = true
	stop()
	await get_tree().create_timer(0.15, true).timeout
	get_tree().quit()

func play(track: String) -> void:
	if not TRACKS.has(track):
		return
	if current_track == track:
		return
	if not ResourceLoader.exists(TRACKS[track]):
		return
	var stream := load(TRACKS[track]) as AudioStreamOggVorbis
	if stream == null:
		push_warning("配乐无法载入：" + track)
		return
	stream.loop = true
	current_track = track
	if _transition != null:
		_transition.kill()
	_transition = create_tween()
	if player.playing:
		_transition.tween_property(player, "volume_db", SILENCE_DB, 0.45)
	_transition.tween_callback(_start.bind(stream))
	_transition.tween_property(player, "volume_db", MUSIC_DB, 1.2)

func _start(stream: AudioStreamOggVorbis) -> void:
	player.stop()
	player.stream = stream
	player.volume_db = SILENCE_DB
	player.play()

func stop() -> void:
	if _transition != null:
		_transition.kill()
	current_track = ""
	player.stop()
	player.stream = null
	player.volume_db = SILENCE_DB

func _sync_scene() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var path := scene.scene_file_path
	if path in ["res://scenes/OpeningScene.tscn", "res://scenes/CineScene.tscn"]:
		stop()
	elif path.begins_with("res://scenes/cities/"):
		play(_station_track(scene.station_id))
	elif path in ["res://Main.tscn", "res://scenes/MapScene.tscn", "res://scenes/FinaleScene.tscn"]:
		play("home")
	elif path == "res://scenes/CodexScene.tscn":
		var return_key: String = SceneRouter.params.get("return_key", "map")
		var context: Dictionary = SceneRouter.params.get("return_params", {})
		play(_station_track(context.get("station", "")) if return_key in ["city", "dialogue", "station"] or return_key.begins_with("puzzle_") else "home")
	elif path in ["res://scenes/DialogueScene.tscn", "res://scenes/StationScene.tscn"]:
		play(_station_track(SceneRouter.params.get("station", "lijiang")))
	elif path.begins_with("res://scenes/puzzles/"):
		# 独立 F6 试玩也使用本小游戏对应城市，不读取上一次的路由参数。
		var station: String = {"PuzzleGlyph": "lijiang", "PuzzleDye": "xianggelila", "PuzzlePattern": "dali", "PuzzleScript": "puer"}.get(path.get_file().get_basename(), "")
		play(_station_track(station))

func _station_track(station: String) -> String:
	# 古城集场沿用丽江地图，尚无独立配乐，继续使用丽江曲。
	if station == "gucheng":
		return "lijiang"
	return station if TRACKS.has(station) else "home"

func _exit_tree() -> void:
	stop()
