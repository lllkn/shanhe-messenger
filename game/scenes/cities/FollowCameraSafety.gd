extends RefCounted
## 普洱镜头：优先保持用户轨道，避让时同时保证近裁剪空间与人物视线。
var current_length := 0.0
var resolved_pitch := 0.7
var resolved_yaw := 0.0
var sphere := SphereShape3D.new()
var sweep := PhysicsShapeQueryParameters3D.new()

func _init() -> void:
	sphere.radius = 0.28
	sweep.shape = sphere
	sweep.collision_mask = 4

func _limit(space: PhysicsDirectSpaceState3D, feet: Vector3, focus: Vector3, direction: Vector3, right: Vector3, length: float) -> float:
	sweep.transform = Transform3D(Basis.IDENTITY, focus)
	sweep.motion = direction * length
	var fractions := space.cast_motion(sweep)
	if not fractions.is_empty(): length *= fractions[0]
	# 只检测镜头中心会漏掉挡住身体/脚下的矮墙；侧边采样保留人物宽度。
	var targets: Array[Vector3] = [feet+Vector3(0,0.25,0),focus,feet+Vector3(0,1.5,0),focus+right*0.23,focus-right*0.23]
	for iteration in 6:
		var limit := length
		for target in targets:
			var end := focus + direction * length
			var ray := PhysicsRayQueryParameters3D.create(target, end, 4)
			var hit := space.intersect_ray(ray)
			if not hit.is_empty():
				var ratio := target.distance_to(hit.position) / maxf(target.distance_to(end), 0.001)
				limit = minf(limit, maxf(0.0, length*ratio-0.3))
		if is_equal_approx(limit, length): break
		length = limit
	return length

func update(camera: Camera3D, player: CharacterBody3D, yaw: float, pitch: float, distance: float, delta: float, reset: bool) -> void:
	var feet := player.global_position
	var focus := feet + Vector3(0,0.8,0)
	var orbit := Basis(Vector3.UP,yaw)
	var direction := orbit * Vector3(0,sin(pitch),cos(pitch))
	var space := player.get_world_3d().direct_space_state
	var safe_length := _limit(space,feet,focus,direction,orbit.x,distance)
	# 贴近矮屋檐时优先从檐下看人物，避免退化为贴脸镜头。
	var target_pitch := pitch
	if safe_length < 3.5:
		for candidate_pitch in [0.55,0.38,0.25,0.12]:
			if candidate_pitch >= pitch: continue
			var candidate_direction: Vector3 = orbit * Vector3(0,sin(candidate_pitch),cos(candidate_pitch))
			var candidate_length := _limit(space,feet,focus,candidate_direction,orbit.x,distance)
			if candidate_length > safe_length:
				target_pitch = candidate_pitch
				safe_length = candidate_length
			if safe_length >= 3.5: break
	resolved_yaw = yaw
	# 巷口贴墙仍无距离时向最近的开阔方向绕开；先试小角度。
	if safe_length < 2.5:
		for turn in [15.0,-15.0,30.0,-30.0,45.0,-45.0,60.0,-60.0,90.0,-90.0,135.0,-135.0,180.0]:
			var candidate_orbit := Basis(Vector3.UP,yaw+deg_to_rad(turn))
			var candidate_direction: Vector3 = candidate_orbit * Vector3(0,sin(target_pitch),cos(target_pitch))
			var candidate_length := _limit(space,feet,focus,candidate_direction,candidate_orbit.x,distance)
			if candidate_length > safe_length:
				resolved_yaw = yaw+deg_to_rad(turn)
				safe_length = candidate_length
			if safe_length >= 2.5: break
	orbit = Basis(Vector3.UP,resolved_yaw)
	if reset or target_pitch < resolved_pitch:
		resolved_pitch = target_pitch
	else:
		resolved_pitch = lerpf(resolved_pitch,target_pitch,1.0-exp(-4.0*maxf(delta,0.001)))
	direction = orbit * Vector3(0,sin(resolved_pitch),cos(resolved_pitch))
	safe_length = _limit(space,feet,focus,direction,orbit.x,distance)
	# 只平滑距离，每帧沿当前轨道重新做碰撞限制；世界坐标插值会在转弯时穿墙。
	if reset or safe_length <= current_length:
		current_length = safe_length
	else:
		current_length = lerpf(current_length,safe_length,1.0-exp(-6.0*maxf(delta,0.001)))
	current_length = _limit(space,feet,focus,direction,orbit.x,current_length)
	camera.global_position = focus + direction*current_length
	# 即使玩家贴墙，保留稳定朝向。
	camera.look_at(camera.global_position-direction,Vector3.UP)
