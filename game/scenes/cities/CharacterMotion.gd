extends Node3D
## 分件模型的轻量步行动作；不改变角色碰撞体与城市移动规则。
var phase := 0.0
var left_leg: Node3D
var right_leg: Node3D
var left_arm: Node3D
var right_arm: Node3D

func _ready() -> void:
	left_leg = find_child("*Leg_L*", true, false) as Node3D
	right_leg = find_child("*Leg_R*", true, false) as Node3D
	left_arm = find_child("*Arm_L*", true, false) as Node3D
	right_arm = find_child("*Arm_R*", true, false) as Node3D

func _process(delta: float) -> void:
	var parent := get_parent() as CharacterBody3D
	if parent == null: return
	var speed := Vector2(parent.velocity.x, parent.velocity.z).length()
	phase += delta * (10.0 if speed > 4 else 7.0)
	var sway := sin(phase) * minf(speed / 3.5, 1.0) * 0.30
	if left_leg != null: left_leg.rotation.x = sway
	if right_leg != null: right_leg.rotation.x = -sway
	if left_arm != null: left_arm.rotation.x = -sway * 0.5
	if right_arm != null: right_arm.rotation.x = sway * 0.5
	if speed > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(parent.velocity.x, parent.velocity.z), minf(delta*14, 1.0))
