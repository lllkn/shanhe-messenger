extends Node
## 在实际城市中核验动态层，不用原独立预览代替接入测试。
var failures := 0
var checks := 0
var output := OS.get_environment("DYNAMICS_TEST_OUTPUT")

func check(ok: bool, message: String) -> void:
	checks += 1
	print("PASS: " if ok else "FAIL: ",message)
	if not ok: failures += 1

func ready_city(id: String) -> Node3D:
	SceneRouter.goto_station(id)
	await get_tree().process_frame
	while SceneRouter.is_switching(): await get_tree().process_frame
	var city := get_tree().current_scene
	for frame in 6: await get_tree().process_frame
	return city

func capture(city: Node3D, id: String) -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless": return
	city.set_process(false)
	city.player.enabled = false
	city.mouse_look = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	match id:
		"lijiang":
			city.camera.position = Vector3(-12,8.8,17.5)
			city.camera.look_at(Vector3(-20,1,12))
		"dali":
			city.camera.position = Vector3(28,9,16)
			city.camera.look_at(Vector3(33,0,0))
		"puer":
			city.camera.position = Vector3(-7,9,17)
			city.camera.look_at(Vector3(-6,1,0))
		"xianggelila":
			city.camera.position = Vector3(8,9,17)
			city.camera.look_at(city.anchor_position("POI_PrayerFlagArray"))
	for shot in 2:
		await get_tree().create_timer(0.7).timeout
		for frame in 3: await get_tree().process_frame
		RenderingServer.force_draw()
		var image := get_viewport().get_texture().get_image()
		image.save_png(output.path_join(id+"-%d.png" % shot))
		if id == "dali":
			var water_pixels := 0
			for y in range(120,600):
				for x in range(350,980):
					var color := image.get_pixel(x,y)
					if color.b > color.r*1.3 and color.b > 0.12 and color.g > color.r: water_pixels += 1
			check(water_pixels>4000,"大理实际渲染画面显示蓝色水面："+str(water_pixels))
	city.set_process(true)
	city.player.enabled = true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().current_scene = null
	var actual: String = GameState.save_path
	GameState.save_path = "user://city-dynamics-test.cfg"
	GameState.reset_game()
	GameState.unlocked.assign(["lijiang","xianggelila","dali","puer","gucheng"])
	for id in ["lijiang","xianggelila","dali","puer"]:
		GameState.set_flag("flow/"+id+"/arrival")
	for id in ["lijiang","dali","puer","xianggelila","gucheng"]:
		var city := await ready_city(id)
		var spawn: Vector3 = city.anchor_position(city.spec["spawn_anchor"])
		var goal: Vector3 = city.anchor_position(city.spec["goal_anchor"])
		var body: StaticBody3D = city.get_node("MapCollision")
		var collision_count := body.get_child_count()
		var layer: Node3D = city.ambient_details
		var probe: Node3D
		var material: ShaderMaterial
		var animation: AnimationPlayer
		if id == "xianggelila":
			animation = city.map_root.find_child("AnimationPlayer",true,false)
			check(animation != null and animation.is_playing(),"香格里拉原GLB动画正在播放")
			var clip := animation.get_animation(animation.current_animation)
			check(clip.loop_mode == Animation.LOOP_LINEAR and clip.get_track_count()>200,"香格里拉319轨环境动画已循环")
			# 从周期末尾跨到下一周期，验证不是仅设置了循环标志。
			animation.seek(clip.length-0.1,true)
			await get_tree().create_timer(0.3).timeout
			check(animation.is_playing() and animation.current_animation_position<1.0,"香格里拉跨越周期末尾继续播放")
			probe = city.map_root.find_child("Dyn_FlagLine_Array_0_00",true,false)
		elif id in ["lijiang","gucheng"]:
			check(layer != null and layer.configured,"丽江动态层启动："+id)
			check(layer._wheel.get_child_count()>=18 and layer._ducks.size()==2 and layer._cat!=null,"丽江水车、两只鸭、猫导入："+id)
			probe = layer._wheel
			material = layer._water_material
		elif id == "dali":
			check(layer != null and layer.configured,"大理动态层启动")
			check(layer._boats.size()==3 and layer._cloth.size()>=8 and layer._birds.size()==4 and layer._fowl.size()==2,"大理三条船、飘布、水鸟、水禽导入")
			probe = layer._boats[0][0]
			material = layer._water_material
			var lake: MeshInstance3D = city.map_root.find_child("Erhai_water_surface",true,false)
			check(lake.material_override is ShaderMaterial and lake.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()>500,"大理细分洱海水面及水波材质已接入")
		elif id == "puer":
			check(layer != null and layer.configured,"普洱动态层启动")
			check(layer.shader_materials.size()>=8 and layer.birds.size()==3 and layer.motes.multimesh.instance_count==24,"普洱风动、三只鸟、24片漂叶导入")
			check(layer.actors.size()==4,"普洱现有四位NPC视觉待机已绑定")
			check(layer.mist.size()==3 and layer.mist_root.visible,"普洱原流雾效果已接入")
			probe = layer.birds[0]["node"]
			material = layer.shader_materials[0]
		var before := probe.transform
		await get_tree().create_timer(0.4).timeout
		check(not probe.transform.is_equal_approx(before),id+" 实际帧中动态部件变换发生变化")
		if material != null:
			var time_key := "wind_time" if id == "puer" else "flow_time"
			var time: float = material.get_shader_parameter(time_key)
			await get_tree().create_timer(0.1).timeout
			check(float(material.get_shader_parameter(time_key))>time,id+" 水流/风动着色器时间推进")
		before = probe.transform
		var held: float = animation.current_animation_position if animation != null else (layer.simulation_time if id=="puer" else layer._elapsed)
		get_tree().paused = true
		await get_tree().create_timer(0.15,true).timeout
		check(probe.transform.is_equal_approx(before),id+" 暂停冻结动态部件")
		var now: float = animation.current_animation_position if animation != null else (layer.simulation_time if id=="puer" else layer._elapsed)
		check(is_equal_approx(held,now),id+" 暂停冻结动画/水面/风动时间")
		get_tree().paused = false
		await get_tree().create_timer(0.1).timeout
		check(not probe.transform.is_equal_approx(before),id+" 恢复继续动态")
		check(city.anchor_position(city.spec["spawn_anchor"]).is_equal_approx(spawn) and city.anchor_position(city.spec["goal_anchor"]).is_equal_approx(goal),id+" 出生与剧情锚点未移动")
		check(body.get_child_count()==collision_count,id+" 动态未更改地图碰撞节点")
		if id == "puer":
			for item in city.story["interviews"]: GameState.set_flag("clue/puer/"+str(item["id"]))
			await get_tree().process_frame
			await get_tree().process_frame
			check(not layer.mist_root.visible,"普洱访谈完成后散雾，不新增锁门规则")
			for item in city.story["interviews"]: GameState.set_flag("clue/puer/"+str(item["id"]),false)
		if id != "gucheng": await capture(city,id)
		SceneRouter.goto_codex()
		await get_tree().process_frame
		while SceneRouter.is_switching(): await get_tree().process_frame
		get_tree().current_scene._back()
		await get_tree().process_frame
		while SceneRouter.is_switching(): await get_tree().process_frame
		city = get_tree().current_scene
		for frame in 6: await get_tree().process_frame
		check((city.ambient_details != null and city.ambient_details.configured) if id!="xianggelila" else city.map_root.find_child("AnimationPlayer",true,false).is_playing(),id+" 行囊返回后动态重新接入")
	GameState.save_path = actual
	GameState.load_game()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://city-dynamics-test.cfg"))
	print("CITY_DYNAMICS_TEST checks=",checks," failures=",failures)
	get_tree().quit(failures)
