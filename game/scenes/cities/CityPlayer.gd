extends CharacterBody3D
var heading := 0.0
var enabled := true
var jump_needs_release := false
func _physics_process(delta: float) -> void:
	if not Input.is_physical_key_pressed(KEY_SPACE):
		jump_needs_release = false
	elif not enabled:
		jump_needs_release = true
	var axis := Vector2.ZERO
	if enabled and not SceneRouter.is_switching():
		axis = Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	var direction := Basis(Vector3.UP, heading) * Vector3(axis.x, 0, axis.y).normalized()
	var speed := 6.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 3.5
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if is_on_floor():
		velocity.y = 0
		if enabled and not jump_needs_release and not SceneRouter.is_switching() and Input.is_physical_key_pressed(KEY_SPACE):
			velocity.y = 4.4
	else:
		velocity.y -= 18.0 * delta
	# 小台阶：先检查抬高后的水平路径与落脚面，再抬脚。
	if is_on_floor() and direction.length_squared() > 0.0:
		var motion := direction * maxf(speed * delta, 0.4)
		if test_move(global_transform, motion):
			var raised := global_transform
			raised.origin.y += 0.46
			if not test_move(raised, motion):
				var ray := PhysicsRayQueryParameters3D.create(raised.origin + motion, global_position + motion + Vector3(0, -0.1, 0), 1)
				var hit := get_world_3d().direct_space_state.intersect_ray(ray)
				if not hit.is_empty() and hit.normal.y > 0.75 and hit.position.y > global_position.y + 0.025:
					global_position.y = hit.position.y + 0.025
	move_and_slide()
