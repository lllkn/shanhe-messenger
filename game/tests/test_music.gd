extends Node
## 实际场景和混音输出回归；独立存档，不写玩家设置。
var failures := 0
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	print("PASS: " if ok else "FAIL: ", message)
	if not ok: failures += 1

func settle() -> void:
	await get_tree().process_frame
	while SceneRouter.is_switching(): await get_tree().process_frame
	await get_tree().create_timer(1.8).timeout

func _ready() -> void:
	get_tree().current_scene = null
	var actual_path: String = GameState.save_path
	var actual_volume: float = GameSettings.volume
	GameState.save_path = "user://music-test.cfg"
	GameState.reset_game()
	GameState.unlocked.assign(["lijiang", "xianggelila", "dali", "puer", "gucheng"])
	for id in ["lijiang", "xianggelila", "dali", "puer"]:
		GameState.set_flag("flow/" + id + "/arrival")
	SceneRouter.goto("home")
	await settle()
	check(GameMusic.current_track == "home" and GameMusic.player.playing, "主页面播放山河有信")
	check(is_equal_approx(GameMusic.player.volume_db, -12.0), "配乐独立降低12dB，不覆盖玩家总音量")
	var capture := AudioEffectCapture.new()
	AudioServer.add_bus_effect(0, capture)
	var effect_index := AudioServer.get_bus_effect_count(0) - 1
	GameMusic.player.seek(20.0)
	capture.clear_buffer()
	await get_tree().create_timer(0.3).timeout
	var peak := _peak(capture)
	check(peak > 0.00001 and peak < 0.2, "主页面真实混音有低音量输出：" + str(peak))
	GameSettings.volume = 0.0
	GameSettings._apply()
	await get_tree().create_timer(0.15).timeout
	capture.clear_buffer()
	await get_tree().create_timer(0.2).timeout
	check(is_zero_approx(AudioServer.get_bus_volume_linear(0)), "原音量设置为零时主输出总线静音")
	GameSettings.volume = actual_volume
	GameSettings._apply()
	AudioServer.remove_bus_effect(0, effect_index)
	GameUI.open_pause()
	var position: float = GameMusic.player.get_playback_position()
	await get_tree().create_timer(0.25).timeout
	check(absf(position - GameMusic.player.get_playback_position()) < 0.04, "暂停期间配乐播放位置冻结")
	GameUI.close_modal()
	await get_tree().create_timer(0.25).timeout
	check(GameMusic.player.get_playback_position() > position, "继续旅程后配乐恢复")
	SceneRouter.goto_map()
	await settle()
	check(GameMusic.current_track == "home" and GameMusic.player.get_playback_position() > position, "主页面到旅程总览同曲不断播")
	for id in ["lijiang", "dali", "puer", "xianggelila"]:
		SceneRouter.goto_station(id)
		await settle()
		check(GameMusic.current_track == id and GameMusic.player.stream.resource_path.ends_with(id + ".ogg") and GameMusic.player.playing, "实际城市使用对应曲目：" + id)
		var stream := GameMusic.player.stream as AudioStreamOggVorbis
		GameMusic.player.seek(stream.get_length() - 0.15)
		await get_tree().create_timer(0.5).timeout
		check(stream.loop and GameMusic.player.playing and GameMusic.player.get_playback_position() < 2.0, "实际跨曲尾继续循环：" + id)
	SceneRouter.goto_codex()
	await settle()
	check(GameMusic.current_track == "xianggelila", "城市进入行囊保留本城配乐")
	SceneRouter.goto_puzzle("xianggelila")
	await settle()
	check(GameMusic.current_track == "xianggelila", "小游戏延续对应城市配乐")
	SceneRouter.goto_dialogue("sample_lijiang", {"station": "lijiang"})
	await settle()
	check(GameMusic.current_track == "lijiang", "对话场景使用对应城市配乐")
	SceneRouter.goto_station("gucheng")
	await settle()
	check(GameMusic.current_track == "lijiang", "复用丽江地图的古城集场沿用丽江曲")
	SceneRouter.goto_path("res://scenes/OpeningScene.tscn", {}, "home")
	await settle()
	var opening := get_tree().current_scene
	check(GameMusic.current_track.is_empty() and not GameMusic.player.playing and opening._player.is_playing(), "开场影像仅播放自身音轨")
	opening.skip_opening()
	check(not GameMusic.player.playing, "跳过后的简介保持安静")
	opening._begin_transition()
	await get_tree().create_timer(4.5).timeout
	check(GameMusic.current_track == "home" and GameMusic.player.playing, "云幕揭开主页面时淡入主题曲")
	# 快速连续请求必须取消旧渐变，只保留最后一首。
	GameMusic.play("dali")
	await get_tree().create_timer(0.1).timeout
	GameMusic.play("puer")
	await get_tree().create_timer(1.8).timeout
	check(GameMusic.current_track == "puer" and GameMusic.player.stream.resource_path.ends_with("puer.ogg") and GameMusic.get_child_count() == 1, "快速切换只保留最后一首，无旧曲叠播")
	GameState.save_path = actual_path
	GameState.load_game()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://music-test.cfg"))
	print("MUSIC CHECKS: ", checks, " FAILURES: ", failures)
	if failures == 0:
		# 使用与原生窗口关闭相同的信号，验证播放中退出的解码清理。
		get_tree().root.close_requested.emit()
	else:
		GameMusic.stop()
		get_tree().quit(failures)

func _peak(capture: AudioEffectCapture) -> float:
	var peak := 0.0
	for sample in capture.get_buffer(capture.get_frames_available()):
		peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
	return peak
