extends "res://tests/test_dali_chain.gd"
func _ready() -> void:
	get_tree().current_scene=null
	original_save=GameState.save_path
	GameState.save_path="user://dali-geometry.cfg"
	GameState.reset_game();GameState.unlocked.assign(["lijiang","xianggelila","dali"])
	SceneRouter.goto_station("dali")
	var city:=await city_ready()
	await physics(10);await finish_talk(city)
	for bridge in city.story["bridges"]:
		var middle: Vector3=city.bridge_center(bridge)
		var axis: Array=bridge["across"]
		var across:=Vector3(axis[0],0,axis[2])
		await walk(city,middle-across*3.4,"入口 "+bridge["id"])
		await walk(city,middle,"桥心 "+bridge["id"])
		print("BRIDGE_PLAYER ",city.player.position)
		await walk(city,middle+across*3.4,"出口 "+bridge["id"])
	check(city.hotspots.size()==4,"地图仅保留三位访谈人物和扎染婆婆")
	check(hotspot(city,"pagodas").is_empty() and hotspot(city,"zhaobi").is_empty(),"两处风物入口已移除")
	for id in ["vendor","youngster","granny"]:
		var item:=hotspot(city,id)
		await walk(city,item["position"],id)
		check(city.near_hotspot().get("id","")==id,"访谈到位 "+id)
		key(KEY_E,true);await physics(3);key(KEY_E,false);await get_tree().process_frame
		check(city.dialogue!=null and city.dialogue.dialogue_id==item["dialogue"],"真实E触发 "+id)
		await finish_talk(city)
	_restore_save();print("GEOMETRY failures=",failures);get_tree().quit(failures)
