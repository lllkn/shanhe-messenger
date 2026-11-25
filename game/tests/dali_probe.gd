extends Node
func _ready() -> void:
	get_tree().current_scene=null
	GameState.save_path="user://dali-probe.cfg"
	GameState.reset_game();GameState.unlocked.assign(["lijiang","xianggelila","dali"])
	SceneRouter.goto_station("dali")
	await get_tree().process_frame
	while SceneRouter.is_switching():await get_tree().process_frame
	var city:=get_tree().current_scene
	while not city.walk_guide.ready:await get_tree().physics_frame
	await get_tree().create_timer(0.3).timeout
	while city.dialogue!=null:city.dialogue._continue()
	await get_tree().process_frame
	var data:=[]
	var cd: Resource=load("res://assets/cities/dali/collision.res")
	for i in cd.shapes.size():
		if not str(cd.names[i]).begins_with("B_07_"):continue
		var shape: Shape3D=cd.shapes[i]
		if shape is ConvexPolygonShape3D:
			var box:=AABB(shape.points[0],Vector3.ZERO)
			for p in shape.points:box=box.expand(p)
			print("WALL_COMPONENT ",cd.names[i]," points=",shape.points.size()," box=",box)

	for item in city.hotspots:print("HOTSPOT ",item["id"]," pos=",item["position"]," nearest=",city.walk_guide.nearest_open(item["position"])," route=",city.walk_guide.path(city.player.position,item["position"]).size())
	for bridge in city.story["bridges"]:
		if not bridge.get("water",false) and bridge["id"]!="WaterGateWest":continue
		var center: Vector3=city.bridge_center(bridge)
		var axis: Array=bridge["across"]
		var across:=Vector3(axis[0],0,axis[2])
		for i in range(-12,13):
			var pos:=center+across*i*0.3
			var ray:=PhysicsRayQueryParameters3D.create(pos+Vector3(0,0.48,0),pos-Vector3(0,1,0),1)
			var hit: Dictionary=city.get_world_3d().direct_space_state.intersect_ray(ray)
			var query:=PhysicsShapeQueryParameters3D.new()
			var capsule:=CapsuleShape3D.new();capsule.radius=0.34;capsule.height=1.65
			query.shape=capsule;query.collision_mask=1
			query.transform=Transform3D(Basis.IDENTITY,hit.get("position",pos)+Vector3(0,0.86,0))
			var names:=[]
			for block in city.get_world_3d().direct_space_state.intersect_shape(query):
				var labels: Array=block.collider.get_meta("shape_names",[])
				var index: int=block.get("shape",-1)
				names.append(labels[index] if index>=0 and index<labels.size() else block.collider.name)
			print("BRIDGE_AXIS ",bridge["id"]," t=",i*0.3," floor=",hit.get("position",Vector3.ZERO)," normal=",hit.get("normal",Vector3.ZERO)," blocks=",names)
	var file:=FileAccess.open("res://../drafts/dali-upgrade-20261010/probe.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(data,"  "))
	var grid: AStarGrid2D=city.walk_guide.grid
	var img:=Image.create(grid.region.size.x,grid.region.size.y,false,Image.FORMAT_RGB8)
	for x in grid.region.size.x:
		for z in grid.region.size.y:img.set_pixel(x,z,Color.WHITE if not grid.is_point_solid(Vector2i(x,z)) else Color.BLACK)
	img.resize(img.get_width()*8,img.get_height()*8,Image.INTERPOLATE_NEAREST)
	img.save_png("res://../drafts/dali-upgrade-20261010/grid.png")
	if DisplayServer.get_name()!="headless":
		city.player.enabled=false
		city.distance=48;city.pitch=1.3;city.yaw=0
		city.player.position=Vector3(0,1,3)
		city.camera.position=Vector3(0,45,25)
		city.camera.look_at(Vector3(0,0,3))
		await get_tree().create_timer(1).timeout
		RenderingServer.force_draw()
		get_viewport().get_texture().get_image().save_png("res://../drafts/dali-upgrade-20261010/probe.png")
	get_tree().quit()
