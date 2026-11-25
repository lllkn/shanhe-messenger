extends "res://tests/test_dali_chain.gd"
func _ready() -> void:
	get_tree().current_scene=null
	original_save=GameState.save_path;GameState.save_path="user://dali-water.cfg"
	GameState.reset_game();GameState.unlocked.assign(["lijiang","xianggelila","dali"])
	SceneRouter.goto_station("dali");var city:=await city_ready();await finish_talk(city)
	for bridge in city.story["bridges"]:
		if not bridge.get("water",false):continue
		var center: Vector3=city.bridge_center(bridge)
		var axis: Array=bridge["across"];var bridge_axis:=Vector3(axis[0],0,axis[2])
		for i in city.story["canal"].size()-1:
			var aa: Array=city.story["canal"][i];var bb: Array=city.story["canal"][i+1]
			var a:=Vector3(aa[0],0,aa[1]);var b:=Vector3(bb[0],0,bb[1]);var dir: Vector3=(b-a).normalized()
			for j in 11:
				var p: Vector3=a.lerp(b,j/10.0)
				if p.distance_to(Vector3(center.x,0,center.z))>6:continue
				var delta:=p-center
				if absf(delta.dot(bridge_axis))<2.8 and absf(delta.dot(bridge_axis.cross(Vector3.UP)))<1.45:continue
				var side:=dir.cross(Vector3.UP)
				var ray:=PhysicsRayQueryParameters3D.create(p+side*2+Vector3(0,0.85,0),p-side*2+Vector3(0,0.85,0),1)
				var hit: Dictionary=city.get_world_3d().direct_space_state.intersect_ray(ray)
				if hit.is_empty():print("UNGUARDED_OUTSIDE_BRIDGE ",bridge["id"]," ",p)
	_restore_save();get_tree().quit()
