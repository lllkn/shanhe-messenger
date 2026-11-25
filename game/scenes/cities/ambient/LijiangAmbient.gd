extends Node3D

# Godot-side ambience stays separate from the editable Blender/GLB geometry.
# All coordinates below are Godot (Y-up) metres.
const WATER_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform float flow_time = 0.0;
varying vec3 world_pos;
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 p = world_pos.xz;
	float drift = flow_time * 0.55;
	float a = sin(p.x * 3.1 + p.y * 1.8 - drift * 2.1);
	float b = sin(p.x * 1.5 - p.y * 4.2 - drift * 1.4);
	float ripple = pow(max(0.0, a * 0.52 + b * 0.48), 5.0);
	float broad = 0.5 + 0.5 * sin(p.x * 0.85 + p.y * 0.45 - drift);
	ALBEDO = mix(vec3(0.20, 0.43, 0.47), vec3(0.37, 0.60, 0.62), 0.24 + broad * 0.30 + ripple * 0.13);
	EMISSION = vec3(0.014, 0.032, 0.036) + vec3(0.008, 0.014, 0.014) * ripple;
	ROUGHNESS = 0.54;
	SPECULAR = 0.29;
}
"""

const WHEEL_CENTER := Vector3(-20.8, 1.58, 12.3)
const WHEEL_SPEED_RAD_S := -0.34

var _wheel: Node3D
var _ducks: Array[Node3D] = []
var _duck_routes: Array[Array] = []
var _cat: Node3D
var _cat_tail: Node3D
var _elapsed := 0.0


var _bound_map: Node3D
var configured := false
var _water_material: ShaderMaterial

func bind_map(map: Node3D) -> void:
	_bound_map = map

func _ready() -> void:
	_build.call_deferred()

func _build() -> void:
	var map := _bound_map
	if map == null: return
	var wheel_count := _setup_wheel(map)
	var water_count := _setup_water(map)
	_setup_animals()
	configured = true
	print("LIJIANG_AMBIENCE_READY wheel_parts=",wheel_count," water_meshes=",water_count," ducks=",_ducks.size()," cats=",1)

func _process(delta: float) -> void:
	if not configured: return
	_elapsed += delta
	_water_material.set_shader_parameter("flow_time",_elapsed)
	if _wheel != null:
		_wheel.rotate_x(WHEEL_SPEED_RAD_S * delta)
	for i in range(_ducks.size()):
		var phase := _elapsed * (0.34 + i * 0.07) + i * 1.7
		var f := 0.5 + 0.5 * sin(phase)
		var start: Vector3 = _duck_routes[i][0]
		var finish: Vector3 = _duck_routes[i][1]
		_ducks[i].position = start.lerp(finish, f) + Vector3(0.0, 0.018 * sin(_elapsed * 2.6 + i), 0.0)
		var direction := (finish - start) * cos(phase)
		if direction.length_squared() > 0.003:
			_ducks[i].rotation.y = lerp_angle(_ducks[i].rotation.y,
				atan2(-direction.x, -direction.z), minf(1.0, delta * 2.3))
	if _cat != null:
		var phase := _elapsed * 0.41
		var f := 0.5 + 0.5 * sin(phase)
		var start := Vector3(1.45, 0.025, 2.8)
		var finish := Vector3(3.5, 0.025, 5.1)
		_cat.position = start.lerp(finish, f)
		var direction := (finish - start) * cos(phase)
		if direction.length_squared() > 0.003:
			_cat.rotation.y = lerp_angle(_cat.rotation.y,
				atan2(-direction.x, -direction.z), minf(1.0, delta * 2.0))
		_cat_tail.rotation.z = 0.25 * sin(_elapsed * 2.0)


func _setup_wheel(map: Node) -> int:
	_wheel = Node3D.new()
	_wheel.name = "AnimatedWaterwheelPivot"
	map.add_child(_wheel)
	_wheel.position = WHEEL_CENTER
	var count := 0
	for node in map.find_children("Waterwheel_*", "MeshInstance3D", true, false):
		if node.name.begins_with("Waterwheel_hub") \
		or node.name.begins_with("Waterwheel_open_timber_rim") \
		or node.name.begins_with("Waterwheel_paddle") \
		or node.name.begins_with("Waterwheel_spoke"):
			node.reparent(_wheel, true)
			count += 1
	if count < 18:
		push_warning("水车活动部件不足，检查 GLB 节点名：%d" % count)
	return count


func _setup_water(map: Node) -> int:
	var shader := Shader.new()
	shader.code = WATER_SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	_water_material = material
	var count := 0
	for node in map.find_children("*", "MeshInstance3D", true, false):
		if node.name.begins_with("Canal_water_to_map_edge") \
		or node.name.begins_with("Waterwheel_feeder_water") \
		or node.name.begins_with("Waterwheel_shallow_basin"):
			node.material_override = material
			count += 1
	if count < 3:
		push_warning("流动水面不足，检查 GLB 节点名：%d" % count)
	return count


func _setup_animals() -> void:
	var pale := _material(Color(0.78, 0.72, 0.55))
	var chestnut := _material(Color(0.39, 0.25, 0.16))
	_ducks.append(_make_duck("CanalDuck_A", pale, chestnut))
	_ducks.append(_make_duck("CanalDuck_B", chestnut, pale))
	_duck_routes.append([Vector3(-19.6, 0.105, -13.9), Vector3(-17.4, 0.105, -12.15)])
	_duck_routes.append([Vector3(-4.35, 0.105, -3.93), Vector3(-2.35, 0.105, -3.10)])
	_cat = _make_cat()


func _make_duck(name: String, body_mat: Material, wing_mat: Material) -> Node3D:
	var root := Node3D.new()
	root.name = name
	add_child(root)
	_ellipsoid(root, "Body", Vector3(0, 0.19, 0), Vector3(0.20, 0.14, 0.30), body_mat)
	_ellipsoid(root, "Head", Vector3(0, 0.33, -0.22), Vector3(0.13, 0.13, 0.13), body_mat)
	_ellipsoid(root, "LeftWing", Vector3(-0.16, 0.22, 0.03), Vector3(0.055, 0.075, 0.18), wing_mat)
	_ellipsoid(root, "RightWing", Vector3(0.16, 0.22, 0.03), Vector3(0.055, 0.075, 0.18), wing_mat)
	_box(root, "Bill", Vector3(0, 0.30, -0.37), Vector3(0.15, 0.045, 0.12),
		_material(Color(0.79, 0.42, 0.16)))
	var dark := _material(Color(0.035, 0.035, 0.028))
	_ellipsoid(root, "EyeL", Vector3(-0.105, 0.36, -0.30), Vector3(0.015, 0.019, 0.015), dark)
	_ellipsoid(root, "EyeR", Vector3(0.105, 0.36, -0.30), Vector3(0.015, 0.019, 0.015), dark)
	return root


func _make_cat() -> Node3D:
	var root := Node3D.new()
	root.name = "SquareStreetCat"
	add_child(root)
	var fur := _material(Color(0.54, 0.31, 0.17))
	var dark := _material(Color(0.10, 0.08, 0.06))
	_ellipsoid(root, "Body", Vector3(0, 0.24, 0.08), Vector3(0.18, 0.17, 0.32), fur)
	_ellipsoid(root, "Head", Vector3(0, 0.35, -0.26), Vector3(0.16, 0.15, 0.15), fur)
	for x in [-0.105, 0.105]:
		var ear := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.075
		cone.height = 0.16
		cone.radial_segments = 4
		ear.mesh = cone
		ear.material_override = fur
		ear.position = Vector3(x, 0.52, -0.27)
		root.add_child(ear)
		_ellipsoid(root, "Eye", Vector3(x * 0.8, 0.39, -0.395), Vector3(0.018, 0.024, 0.015), dark)
	for x in [-0.12, 0.12]:
		for z in [-0.14, 0.25]:
			_box(root, "Paw", Vector3(x, 0.09, z), Vector3(0.07, 0.16, 0.08), fur)
	_cat_tail = Node3D.new()
	_cat_tail.name = "SwayingTail"
	_cat_tail.position = Vector3(0, 0.32, 0.35)
	root.add_child(_cat_tail)
	_box(_cat_tail, "Tail", Vector3(0, 0.19, 0.055), Vector3(0.07, 0.39, 0.07), fur)
	return root


func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	return mat


func _ellipsoid(parent: Node3D, name: String, pos: Vector3, size: Vector3, mat: Material) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	var item := MeshInstance3D.new()
	item.name = name
	item.mesh = mesh
	item.material_override = mat
	item.position = pos
	item.scale = size
	parent.add_child(item)


func _box(parent: Node3D, name: String, pos: Vector3, size: Vector3, mat: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var item := MeshInstance3D.new()
	item.name = name
	item.mesh = mesh
	item.material_override = mat
	item.position = pos
	parent.add_child(item)
