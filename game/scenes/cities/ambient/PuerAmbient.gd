extends Node3D
@export var enabled := true
@export_range(0.0,2.0,.05) var wind_strength := 1.0
@export_range(0.0,2.0,.05) var animation_speed := 1.0
var simulation_time := 0.0
var shader_materials: Array[ShaderMaterial] = []
var actors: Array[Dictionary] = []
var birds: Array[Dictionary] = []
var motes: MultiMeshInstance3D
var configured := false
var birds_root: Node3D
var wind_shader := preload("res://scenes/cities/ambient/微风.gdshader")
var mist_shader := preload("res://scenes/cities/ambient/流雾.gdshader")
var mist_root: Node3D
var mist: Array[Dictionary] = []
var _bound_map: Node3D
var _bound_visuals: Array[Node3D] = []

func bind_map(map: Node3D, visuals: Array[Node3D] = []) -> void:
	_bound_map = map
	_bound_visuals = visuals

func _ready() -> void:
	configure.call_deferred(_bound_map)

func configure(geometry: Node3D) -> void:
	if configured: return
	# Apply only to organic/cloth surfaces. Buildings, trunks, anchors and collisions stay rigid.
	for node in geometry.find_children("*","MeshInstance3D",true,false):
		var mesh_node := node as MeshInstance3D
		for surface in mesh_node.mesh.get_surface_count():
			var original := mesh_node.get_active_material(surface) as StandardMaterial3D
			if original == null: continue
			var material_name := original.resource_name
			var kind := -1
			var amp := .0
			if material_name in ["E_Puer_leaf","E_Puer_leaf_light"]:
				kind = 0
				amp = .20 if mesh_node.name.begins_with("B_09_") else .11
			elif material_name in ["E_Puer_tea","E_Puer_tea_light"]:
				kind = 1
				amp = .045
			elif mesh_node.name.begins_with("B_04_") and material_name in ["E_Puer_cloth","E_Puer_blue"]:
				kind = 2
				amp = .17
			if kind<0: continue
			var mat := ShaderMaterial.new()
			mat.shader = wind_shader
			mat.set_shader_parameter("base_color",original.albedo_color)
			mat.set_shader_parameter("surface_roughness",original.roughness)
			mat.set_shader_parameter("movement_kind",kind)
			mat.set_meta("base_amplitude",amp)
			mat.set_shader_parameter("amplitude",amp*wind_strength)
			mesh_node.set_surface_override_material(surface,mat)
			shader_materials.append(mat)
	# 正式剧情已替换旧NPC模型，只让现有视觉做待机，不移动热点和碰撞。
	for actor in _bound_visuals:
		actors.append({"node":actor,"transform":actor.transform,"phase":float(actors.size())*2.1})
	_build_mist()
	_build_birds()
	_build_motes()
	configured = true
	print("PUER_AMBIENT_READY wind_surfaces=",shader_materials.size()-mist.size()," actors=",actors.size()," birds=",birds.size()," motes=",motes.multimesh.instance_count," mist=",mist.size())
	_apply_frame()
func _process(delta: float) -> void:
	if not configured or not enabled: return
	simulation_time += delta*animation_speed
	_apply_frame()
func _apply_frame() -> void:
	for mat in shader_materials:
		mat.set_shader_parameter("wind_time",simulation_time)
		if mat.has_meta("base_amplitude"):
			mat.set_shader_parameter("amplitude",float(mat.get_meta("base_amplitude"))*wind_strength)
	for spec in actors:
		var actor: Node3D = spec["node"]
		var base: Transform3D = spec["transform"]
		var phase: float = spec["phase"]
		actor.transform = base
		# Breath and a slow glance, around the authored feet pivot.
		actor.position.y += sin(simulation_time*1.55+phase)*.009
		actor.rotation.y += sin(simulation_time*.47+phase)*.035
		actor.rotation.z += sin(simulation_time*.72+phase)*.008
	# 沿用既有访谈解锁条件控制雾的可见性，不引入演示场景的锁门碰撞。
	var city := get_parent()
	if mist_root != null and city.has_method("clue_count"):
		mist_root.visible = city.clue_count()<city.story["interviews"].size() and not GameState.is_completed(city.station_id)
	for spec in mist:
		var node: Node3D = spec["node"]
		var base: Vector3 = spec["position"]
		var phase: float = spec["phase"]
		node.position = base+Vector3(sin(simulation_time*.35+phase)*.22,sin(simulation_time*.43+phase)*.11,0)
	for i in birds.size():
		var spec: Dictionary = birds[i]
		var bird: Node3D = spec["node"]
		var a := simulation_time*.18 + float(i)*.22
		bird.position = Vector3(-13+cos(a)*11,7.5+sin(a*1.7+float(i))*.5+float(i)*.28,-13+sin(a)*6)
		var direction := Vector3(-sin(a)*11,0,cos(a)*6)
		bird.look_at(bird.position+direction,Vector3.UP)
		var flap := sin(simulation_time*6.5+float(i)*.8)*.5
		var left: Node3D = spec["left"]
		var right: Node3D = spec["right"]
		left.rotation.z = flap
		right.rotation.z = -flap
	if motes != null:
		for i in motes.multimesh.instance_count:
			var phase := float(i)*2.399963
			var a := phase+simulation_time*.13
			var centre := Vector3(-6,0,-1) if i<12 else Vector3(22,0,9)
			var radius := 1.1+float(i%6)*.38
			var pos := centre+Vector3(cos(a)*radius,1.05+fmod(float(i)*.19+simulation_time*.09,2.3),sin(a*.8+phase)*radius)
			var basis := Basis.from_euler(Vector3(a,phase+simulation_time*.8,sin(a)*.7)).scaled(Vector3(.095,.095,.095))
			motes.multimesh.set_instance_transform(i,Transform3D(basis,pos))
func _build_mist() -> void:
	mist_root = Node3D.new()
	mist_root.name = "LockedTempleMist"
	mist_root.position = Vector3(16,0,-6)
	add_child(mist_root)
	for i in 3:
		var fog := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 1.65
		sphere.height = 3.3
		fog.mesh = sphere
		fog.position = Vector3((i-1)*1.35,1.5,0)
		fog.scale = Vector3(1,1.1,.55)
		var mat := ShaderMaterial.new()
		mat.shader = mist_shader
		mat.set_shader_parameter("phase",float(i)*2.0)
		fog.material_override = mat
		fog.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mist_root.add_child(fog)
		shader_materials.append(mat)
		mist.append({"node":fog,"position":fog.position,"phase":float(i)*2.0})
func _flat_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = .85
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat
func _wing_mesh(side: float) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO,Vector3(side*.65,.02,.16),Vector3(side*.43,0,-.17)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP,Vector3.UP,Vector3.UP])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh
func _build_birds() -> void:
	birds_root = Node3D.new()
	birds_root.name = "TeaHillBirds"
	add_child(birds_root)
	var mat := _flat_material(Color(.14,.19,.13))
	for i in range(3):
		var bird := Node3D.new()
		bird.name = "Bird_%d" % i
		birds_root.add_child(bird)
		var left := MeshInstance3D.new()
		left.mesh = _wing_mesh(-1)
		left.material_override = mat
		bird.add_child(left)
		var right := MeshInstance3D.new()
		right.mesh = _wing_mesh(1)
		right.material_override = mat
		bird.add_child(right)
		var body := MeshInstance3D.new()
		var body_mesh := SphereMesh.new()
		body_mesh.radius = .065
		body_mesh.height = .13
		body.mesh = body_mesh
		body.scale = Vector3(1,1,2.8)
		body.material_override = mat
		bird.add_child(body)
		birds.append({"node":bird,"left":left,"right":right})
func _build_motes() -> void:
	motes = MultiMeshInstance3D.new()
	motes.name = "DriftingLeafMotes"
	var mesh := _wing_mesh(1)
	mesh.surface_set_material(0,_flat_material(Color(.67,.62,.28)))
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = 24
	motes.multimesh = multi
	motes.custom_aabb = AABB(Vector3(-11,0,-6),Vector3(39,5,20))
	motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(motes)
