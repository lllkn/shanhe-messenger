extends Node3D

# 大理地图的运行时动态层。
#
# 与丽江那版同一套思路：GLB 保持静态、可复现，动的东西全部在 Godot 侧按节点名
# 接管后再动画；只在运行时校正遮住水面的湖底，原GLB不重导。
#
#   Godot --path . -- --dynamics            正常开启动态细节
#   Godot --path . -- --no-dynamics         全部关掉，用来对比/排查
#   Godot --path . -- --dynamics-shot       截图后退出（验收用）
#
# 本节点由城市共用外壳绑定map_root，暂停和销毁随当前城市。

const MAP_NODE := "DaliMap"

# 可动部件的节点名（导出前按材质合批过，所以只能按"材质网格名"定位，
# 不能按单个零件名——晾晒布整批合进了 B_09_E_TieDye_* 这几块里）。
# Blender 导出时特意排除在合批之外，所以它保留了自己的名字（前缀匹配）。
const LAKE_MESH := "Erhai_water_surface"
const STREAM_MESHES := ["B_02_M_Canal_Turquoise", "B_04_M_Canal_Turquoise"]
const CLOTH_MESHES := ["B_09_E_TieDye_Indigo", "B_09_E_TieDye_IndigoFaded",
	"B_09_E_TieDye_White", "B_04_E_TieDye_White"]
const BOAT_PREFIX := "Boat_"

# 洱海水面高度（Godot Y）。水面是一整块平板，动画直接在这块上做。
const WATER_Y := -0.52

# 细分网格的目标格边长（米）。2 米左右足够看出起伏，更密只是白烧三角形。
const WAVE_CELL_SIZE := 2.0

var configured := false
var _enabled := true
var _elapsed := 0.0
# 宿主可以显式指定地图节点，避免依赖"自己恰好是地图的子节点"这种隐式约定。
var _bound_map: Node = null
# 命令行参数提到成员上：构建被 call_deferred 到下一帧，局部变量那时已经没了。
var _args: PackedStringArray = PackedStringArray()


func bind_map(map: Node) -> void:
	_bound_map = map

# --- 水面 ---
var _water_material: ShaderMaterial
var _stream_material: ShaderMaterial
var _lake: MeshInstance3D

# --- 船 ---
# 每条船是一个部件数组；动画直接改各部件相对原始位置的偏移，
# 不建枢轴、不做 reparent——在 _ready 阶段 reparent 会踩到"节点尚未完全进树"的
# 报错（实测 add_child/get_global_transform 都会失败），而且那样还得迁就父子变换。
var _boats: Array[Array] = []
var _boat_home: Array[Array] = []
var _boat_phase: Array[float] = []
var _boat_centers: Array[Vector3] = []

# --- 晾晒布 ---
var _cloth: Array[MeshInstance3D] = []
var _cloth_home: Array[Vector3] = []

# --- 鸟 ---
var _birds: Array[Node3D] = []
var _bird_radius: Array[float] = []
var _bird_phase: Array[float] = []

# --- 水禽 ---
var _fowl: Array[Node3D] = []


func _ready() -> void:
	_args = OS.get_cmdline_user_args()
	for arg in _args:
		if arg == "--no-dynamics":
			_enabled = false
	if not _enabled:
		print("DALI_DYNAMICS_DISABLED")
		return

	# 关键：整层构建必须延到下一帧。
	# 动态层是在宿主场景的 _ready 里被 add_child 的，此时地图节点正处在
	# "busy setting up children" 状态，直接往它上面 add_child / reparent 会被拒绝
	# （报 "Parent node is busy setting up children"），于是水面材质、船、布全部落空。
	_build.call_deferred()


func _build() -> void:
	if not _enabled:
		return

	# 地图节点要么由宿主显式给（bind_map），要么从父节点上找。
	#
	# 注意不要用 get_tree().current_scene 兜底：在 _ready 阶段它可能还是 null，
	# 而 null 上调用 find_child 会直接抛错、把后面所有动态初始化全跳过
	# （现象是"节点建了但一个都没动"，我第一次就是栽在这里）。
	var map: Node = _bound_map
	if map == null and get_parent() != null:
		map = get_parent().get_node_or_null(MAP_NODE)
	if map == null:
		push_error("动态层找不到地图节点 %s：请用 bind_map() 显式传入" % MAP_NODE)
		return

	var water := _setup_water(map)
	_restore_lake_bed(map)
	var boats := _setup_boats(map)
	var cloth := _setup_cloth(map)
	_setup_birds()
	_setup_fowl()

	configured = true
	print("DALI_DYNAMICS_READY water=", water, " boats=", boats,
		" cloth=", cloth, " birds=", _birds.size(), " fowl=", _fowl.size())

	if "--dynamics-shot" in _args:
		_capture_and_quit()


# ------------------------------------------------------------------ 水面 ---
func _setup_water(map: Node) -> int:
	# 两位移方案分开：
	#   洱海  —— 换成"细分过的"平面再交给顶点位移 shader，起伏是真的几何起伏。
	#            原来那块水面只有 1 个四边形，两个三角形做位移等于没有，必须先细分。
	#   水渠  —— 只有 1.6 米宽的薄面，细分和位移都没意义，保留原网格只换材质。
	# 洱海用**位移 shader**，但网格是 Blender 侧就细分好的（Erhai_water_surface，
	# 2 米格边长，导出时特意排除在合批之外，所以名字还在）。
	#
	# 之前试过在 Godot 运行时自建细分网格，渲染不出来（隔离渲染全黑，
	# 换 PlaneMesh 也一样，无报错无警告），原因没查清；改成在 Blender 侧细分后，
	# 这里只需换材质，不再动网格。
	var wave_shader := Shader.new()
	wave_shader.code = WATER_WAVE_SHADER
	_water_material = ShaderMaterial.new()
	_water_material.shader = wave_shader

	# 水渠只有 1.6 米宽，细分与位移都没意义，用平水面 shader 只做偏蓝的流动色
	var flat_shader := Shader.new()
	flat_shader.code = WATER_FLAT_SHADER
	_stream_material = ShaderMaterial.new()
	_stream_material.shader = flat_shader

	var count := 0
	var lake_found := 0
	for node in map.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		var name := str(mesh_node.name)
		if name.begins_with(LAKE_MESH):
			mesh_node.material_override = _water_material
			_lake = mesh_node
			lake_found += 1
			count += 1
		elif name in STREAM_MESHES:
			mesh_node.material_override = _stream_material
			count += 1
	if lake_found == 0:
		push_error("找不到细分后的洱海水面 %s（检查 Blender 侧是否被合批吃掉了）" % LAKE_MESH)
	return count


func _restore_lake_bed(map: Node) -> void:
	# 现有GLB湖底中央Y=0.2，高于水面Y=-0.85；只校正水域内背景地形。
	if _lake == null: return
	var bounds := _world_bounds(_lake)
	var water_y := bounds.position.y
	for node in map.find_children("B_00_M_Earth_Olive", "MeshInstance3D",true,false):
		var terrain := node as MeshInstance3D
		var original := terrain.mesh
		var restored := ArrayMesh.new()
		var world := terrain.global_transform
		var inverse := world.affine_inverse()
		for surface in original.get_surface_count():
			var arrays := original.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for index in vertices.size():
				var point := world*vertices[index]
				var inset := minf(minf(point.x-bounds.position.x,bounds.end.x-point.x),minf(point.z-bounds.position.z,bounds.end.z-point.z))
				var weight := smoothstep(4.0,8.0,inset)
				if weight <= 0.0: continue
				point.y = lerpf(point.y,minf(point.y,water_y-0.3),weight)
				vertices[index] = inverse*point
			arrays[Mesh.ARRAY_VERTEX] = vertices
			restored.add_surface_from_arrays(original.surface_get_primitive_type(surface),arrays)
			restored.surface_set_material(surface,original.surface_get_material(surface))
		terrain.mesh = restored

func _world_bounds(mesh_node: MeshInstance3D) -> AABB:
	var xform := mesh_node.global_transform
	var local := mesh_node.get_aabb()
	var result := AABB()
	for i in 8:
		var w: Vector3 = xform * local.get_endpoint(i)
		if i == 0:
			result = AABB(w, Vector3.ZERO)
		else:
			result = result.expand(w)
	return result


func _build_wave_plane(width: float, depth: float, cell: float) -> ArrayMesh:
	# 细分出一张 (cols+1) x (rows+1) 的网格。cell 是目标格边长，
	# 取 2 米左右就够看出起伏，再密只是白烧三角形。
	var cols := maxi(8, int(round(width / cell)))
	var rows := maxi(8, int(round(depth / cell)))
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	verts.resize((cols + 1) * (rows + 1))
	normals.resize((cols + 1) * (rows + 1))
	uvs.resize((cols + 1) * (rows + 1))
	for r in rows + 1:
		for c in cols + 1:
			var i := r * (cols + 1) + c
			var u := float(c) / float(cols)
			var v := float(r) / float(rows)
			verts[i] = Vector3((u - 0.5) * width, 0.0, (v - 0.5) * depth)
			normals[i] = Vector3.UP
			uvs[i] = Vector2(u * width * 0.25, v * depth * 0.25)
	for r in rows:
		for c in cols:
			var a := r * (cols + 1) + c
			var b := a + 1
			var d := a + cols + 1
			var e := d + 1
			indices.append_array([a, d, b, b, d, e])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var plane := ArrayMesh.new()
	plane.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return plane


# -------------------------------------------------------------------- 船 ---
func _setup_boats(map: Node) -> int:
	# 30 个船部件是分开的节点（导出时特意排除在合批之外），按前缀归组到三条船上，
	# 每条船套一个 Node3D 枢轴，就能整体浮动。
	var groups := {}
	for node in map.find_children(BOAT_PREFIX + "*", "MeshInstance3D", true, false):
		var name := str(node.name)
		# 部件名有两种形状：Boat_Caicun_00_hull 和 Boat_Caicun_00_bow_-1。
		# 船的标识 = "Boat_" 后的两段（Boat_Caicun_00），必须按段数切；
		# 从后面找下划线会把 bow_-1 切成另一个枢轴，一只船散成好几块。
		var segments := name.split("_")
		var pivot_name := "_".join(segments.slice(0, 3)) if segments.size() >= 3 else name
		if not groups.has(pivot_name):
			groups[pivot_name] = []
		groups[pivot_name].append(node)

	var names := groups.keys()
	names.sort()
	for i in names.size():
		var members: Array = groups[names[i]]
		var homes: Array = []
		for member in members:
			homes.append((member as Node3D).transform)
		_boats.append(members)
		_boat_home.append(homes)
		_boat_phase.append(float(i) * 1.9)
		_boat_centers.append(_group_center(members))
	return _boats.size()


func _group_center(members: Array) -> Vector3:
	var center := Vector3.ZERO
	for member in members:
		center += (member as Node3D).position
	return center / float(members.size())


# --------------------------------------------------------------- 晾晒布 ---
func _setup_cloth(map: Node) -> int:
	# 晾晒布在导出时整批合进了几块大网格，没法按零件摆动。这里把网格里的
	# 每一块布拆成独立 MeshInstance3D，各自挂在木架顶端做小幅摆动。
	for node in map.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if str(mesh_node.name) not in CLOTH_MESHES:
			continue
		var pieces := _split_into_islands(mesh_node)
		for i in pieces.size():
			var piece: ArrayMesh = pieces[i]
			if piece.get_surface_count() == 0:
				continue
			# 合批后的顶点仍在整张地图坐标里，先把转轴移到这块布的挂点。
			var bounds := piece.get_aabb()
			var pivot := bounds.get_center()
			pivot.y = bounds.end.y
			var arrays := piece.surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for vertex in vertices.size(): vertices[vertex] -= pivot
			arrays[Mesh.ARRAY_VERTEX] = vertices
			var pivoted := ArrayMesh.new()
			pivoted.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
			var item := MeshInstance3D.new()
			item.name = "%s_cloth_%02d" % [mesh_node.name, i]
			item.mesh = pivoted
			item.material_override = mesh_node.material_override
			if item.material_override == null and mesh_node.mesh.get_surface_count() > 0:
				item.material_override = mesh_node.mesh.surface_get_material(0)
			item.transform = mesh_node.transform.translated_local(pivot)
			map.add_child(item)
			# 拆分出的布不参与碰撞与阴影，纯粹是视觉
			item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_cloth.append(item)
			_cloth_home.append(item.position)
		# 原来的整块布藏起来，避免和新拆出来的重叠
		mesh_node.visible = false
	return _cloth.size()


func _split_into_islands(mesh_node: MeshInstance3D) -> Array:
	# 用并查集把网格按"顶点相连"切成一个个岛屿：一块布的所有面共享顶点，
	# 不同布之间没有共享顶点，所以连通分量就是单块布。
	var arrays := mesh_node.mesh.surface_get_arrays(0)
	if arrays.is_empty():
		return []
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var normals = arrays[Mesh.ARRAY_NORMAL]
	var uvs = arrays[Mesh.ARRAY_TEX_UV]
	var tri_count := indices.size() / 3 if indices.size() > 0 else verts.size() / 3
	if tri_count == 0:
		return []

	var parent := PackedInt32Array()
	parent.resize(verts.size())
	for i in verts.size():
		parent[i] = i

	# 同一位置但索引不同的顶点也要并到一起（合批时可能没做焊接）
	var by_position := {}
	for i in verts.size():
		var key := "%.4f_%.4f_%.4f" % [verts[i].x, verts[i].y, verts[i].z]
		if by_position.has(key):
			_union(parent, by_position[key], i)
		else:
			by_position[key] = i

	for t in tri_count:
		var ia := indices[t * 3] if indices.size() > 0 else t * 3
		var ib := indices[t * 3 + 1] if indices.size() > 0 else t * 3 + 1
		var ic := indices[t * 3 + 2] if indices.size() > 0 else t * 3 + 2
		_union(parent, ia, ib)
		_union(parent, ia, ic)

	# 按根分组，把三角形收集到各自的岛屿
	var islands := {}
	for t in tri_count:
		var ia := indices[t * 3] if indices.size() > 0 else t * 3
		var root := _find(parent, ia)
		if not islands.has(root):
			islands[root] = PackedInt32Array()
		var bucket: PackedInt32Array = islands[root]
		if indices.size() > 0:
			bucket.append(indices[t * 3])
			bucket.append(indices[t * 3 + 1])
			bucket.append(indices[t * 3 + 2])
		else:
			bucket.append(t * 3)
			bucket.append(t * 3 + 1)
			bucket.append(t * 3 + 2)
		islands[root] = bucket

	var result := []
	for root in islands.keys():
		var tris: PackedInt32Array = islands[root]
		if tris.size() < 3:
			continue
		# 只收这块岛屿用到的顶点，重建索引
		var remap := {}
		var new_verts := PackedVector3Array()
		var new_normals := PackedVector3Array()
		var new_uvs := PackedVector2Array()
		var new_tris := PackedInt32Array()
		for idx in tris:
			if not remap.has(idx):
				remap[idx] = new_verts.size()
				new_verts.append(verts[idx])
				if normals != null and normals.size() > idx:
					new_normals.append(normals[idx])
				if uvs != null and uvs.size() > idx:
					new_uvs.append(uvs[idx])
			new_tris.append(remap[idx])
		var island_arrays := []
		island_arrays.resize(Mesh.ARRAY_MAX)
		island_arrays[Mesh.ARRAY_VERTEX] = new_verts
		if new_normals.size() == new_verts.size():
			island_arrays[Mesh.ARRAY_NORMAL] = new_normals
		if new_uvs.size() == new_verts.size():
			island_arrays[Mesh.ARRAY_TEX_UV] = new_uvs
		island_arrays[Mesh.ARRAY_INDEX] = new_tris
		var piece := ArrayMesh.new()
		piece.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, island_arrays)
		result.append(piece)
	return result


func _find(parent: PackedInt32Array, i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i


func _union(parent: PackedInt32Array, a: int, b: int) -> void:
	var ra := _find(parent, a)
	var rb := _find(parent, b)
	if ra != rb:
		parent[rb] = ra


# ------------------------------------------------------------------- 鸟 ---
func _setup_birds() -> void:
	# 洱海上空盘旋的水鸟。纯程序化生成，不占资源。
	for i in 4:
		var bird := _make_bird("LakeBird_%02d" % i)
		add_child(bird)
		_birds.append(bird)
		_bird_radius.append(9.0 + 3.5 * float(i))
		_bird_phase.append(float(i) * 1.4)


func _make_bird(name: String) -> Node3D:
	var root := Node3D.new()
	root.name = name
	var body := _material(Color(0.86, 0.86, 0.84))
	var wing_mat := _material(Color(0.72, 0.73, 0.72))
	_box(root, "Body", Vector3(0, 0, 0), Vector3(0.16, 0.10, 0.44), body)
	for sign in [-1, 1]:
		var wing := Node3D.new()
		wing.name = "Wing_%d" % sign
		root.add_child(wing)
		_box(wing, "Blade", Vector3(sign * 0.34, 0, 0), Vector3(0.62, 0.03, 0.20), wing_mat)
	return root


# --------------------------------------------------------------- 水禽 ---
func _setup_fowl() -> void:
	# 城内水渠里两只水禽，沿渠来回游。
	var routes := [
		[Vector3(-10.0, -0.05, -16.2), Vector3(-7.6, -0.05, -16.4)],
		[Vector3(9.2, -0.05, -18.4), Vector3(11.6, -0.05, -18.2)],
	]
	for i in routes.size():
		var fowl := _make_fowl("StreamFowl_%02d" % i)
		add_child(fowl)
		fowl.set_meta("route", routes[i])
		fowl.position = routes[i][0]
		_fowl.append(fowl)


func _make_fowl(name: String) -> Node3D:
	var root := Node3D.new()
	root.name = name
	var pale := _material(Color(0.78, 0.72, 0.55))
	var chestnut := _material(Color(0.39, 0.25, 0.16))
	_ellipsoid(root, "Body", Vector3(0, 0.09, 0), Vector3(0.20, 0.14, 0.30), pale)
	_ellipsoid(root, "Head", Vector3(0, 0.23, -0.22), Vector3(0.13, 0.13, 0.13), pale)
	_ellipsoid(root, "WingL", Vector3(-0.16, 0.12, 0.03), Vector3(0.055, 0.075, 0.18), chestnut)
	_ellipsoid(root, "WingR", Vector3(0.16, 0.12, 0.03), Vector3(0.055, 0.075, 0.18), chestnut)
	_box(root, "Bill", Vector3(0, 0.20, -0.37), Vector3(0.15, 0.045, 0.12),
		_material(Color(0.79, 0.42, 0.16)))
	return root


# -------------------------------------------------------------- 每帧驱动 ---
func _process(delta: float) -> void:
	if not _enabled or not configured:
		return
	_elapsed += delta

	# 水：把时间交给 shader，这里只保证材质存在
	if _water_material != null:
		_water_material.set_shader_parameter("flow_time", _elapsed)
	if _stream_material != null:
		_stream_material.set_shader_parameter("flow_time", _elapsed)

	# 船：上下浮动 + 轻微横摇 + 顺着水面缓慢漂移
	for i in _boats.size():
		var phase := _elapsed * 0.42 + _boat_phase[i]
		var offset := Vector3(
			0.06 * sin(phase * 0.7),
			0.045 * sin(phase),
			0.03 * cos(phase * 0.5))
		var tilt := Vector3(
			0.035 * sin(phase * 1.3),
			0.020 * sin(phase * 0.6),
			0.045 * sin(phase * 0.9))
		var members: Array = _boats[i]
		var homes: Array = _boat_home[i]
		var center := _boat_centers[i]
		var turn := Basis.from_euler(tilt)
		for k in members.size():
			var part := members[k] as Node3D
			var home: Transform3D = homes[k]
			part.transform = home
			part.position = center+turn*(home.origin-center)+offset
			part.basis = turn*home.basis

	# 晾晒布：以挂点为中心小幅摆动，幅度沿布面高度递增（下摆更飘）
	for i in _cloth.size():
		var phase := _elapsed * 1.15 + float(i) * 0.7
		var item := _cloth[i]
		item.rotation = Vector3(
			0.055 * sin(phase),
			0.020 * sin(phase * 0.6),
			0.040 * sin(phase * 1.4))

	# 鸟：绕洱海盘旋，翅膀上下扇
	for i in _birds.size():
		var phase := _elapsed * 0.22 + _bird_phase[i]
		var radius := _bird_radius[i]
		var center := Vector3(34.0, 9.0 + 1.6 * float(i), -2.0)
		_birds[i].position = center + Vector3(
			radius * cos(phase), 0.6 * sin(phase * 2.1), radius * sin(phase))
		_birds[i].rotation = Vector3(0.0, -phase + PI * 0.5, 0.0)
		for child in _birds[i].get_children():
			if child is Node3D and str(child.name).begins_with("Wing_"):
				(child as Node3D).rotation.z = 0.55 * sin(_elapsed * 6.5 + i)

	# 水禽：沿渠来回，带一点浮沉
	for i in _fowl.size():
		var route: Array = _fowl[i].get_meta("route")
		var phase := _elapsed * 0.30 + float(i) * 2.1
		var f := 0.5 + 0.5 * sin(phase)
		var start: Vector3 = route[0]
		var finish: Vector3 = route[1]
		_fowl[i].position = start.lerp(finish, f) + Vector3(0, 0.015 * sin(_elapsed * 2.4 + i), 0)
		var direction := (finish - start) * cos(phase)
		if direction.length_squared() > 0.003:
			_fowl[i].rotation.y = lerp_angle(_fowl[i].rotation.y,
				atan2(-direction.x, -direction.z), minf(1.0, delta * 2.3))


# ------------------------------------------------------------------ 工具 ---
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


func _capture_and_quit() -> void:
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png("res://动态细节预览.png")
	print("DYNAMICS_SHOT_OK" if error == OK else "DYNAMICS_SHOT_FAILED", " ", error)
	get_tree().quit(0 if error == OK else 1)


# 洱海水面：真起伏。
# 顶点沿 3 组不同方向/波长的正弦波叠加位移（限制在 ±0.06 米，否则会插进岸边的陆地），
# 法线用波形偏导数解析求出——必须重算法线，否则起伏不会改变光照，看起来仍是平的一片。
# 颜色按波长方向做了偏蓝处理：深水是蓝，波峰偏青。
const WATER_WAVE_SHADER := """
shader_type spatial;
render_mode diffuse_burley, cull_disabled;

uniform float flow_time = 0.0;
uniform float wave_speed = 0.85;
uniform float wave_amp = 0.060;
uniform vec3 deep_color : source_color = vec3(0.020, 0.105, 0.290);
uniform vec3 shallow_color : source_color = vec3(0.075, 0.300, 0.520);
uniform vec3 crest_color : source_color = vec3(0.420, 0.660, 0.820);

varying vec3 world_pos;

void waves(vec2 p, float t, out float height, out vec2 grad) {
	// 三组波：方向、波长、速度都不同，叠起来才不像规则的搓板
	// 波长要中等：太短会糊成均匀噪声，太长会变成明显的斜条纹（试过 0.34 起步，
	// 出来是规则的斜带），这里取 0.9/1.6/2.6 三档，接近真实细浪的尺度。
	vec2 d1 = vec2(0.86, 0.51);
	float k1 = 0.90; float a1 = 0.55;
	vec2 d2 = vec2(-0.35, 0.94);
	float k2 = 1.60; float a2 = 0.30;
	vec2 d3 = vec2(0.62, -0.78);
	float k3 = 2.60; float a3 = 0.15;
	float p1 = dot(p, d1) * k1 - t * 1.10;
	float p2 = dot(p, d2) * k2 - t * 1.55;
	float p3 = dot(p, d3) * k3 - t * 2.30;
	height = a1 * sin(p1) + a2 * sin(p2) + a3 * sin(p3);
	grad = a1 * k1 * cos(p1) * d1
		+ a2 * k2 * cos(p2) * d2
		+ a3 * k3 * cos(p3) * d3;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h;
	vec2 g;
	waves(world_pos.xz, flow_time * wave_speed, h, g);
	VERTEX.y += h * wave_amp;
	// 解析法线：n = normalize(vec3(-dh/dx, 1, -dh/dz))
	NORMAL = normalize(vec3(-g.x * wave_amp, 1.0, -g.y * wave_amp));
}

void fragment() {
	float h;
	vec2 g;
	waves(world_pos.xz, flow_time * wave_speed, h, g);
	float crest = clamp(h * 0.5 + 0.5, 0.0, 1.0);
	float slope = clamp(length(g) * 0.55, 0.0, 1.0);
	// 深水 -> 浅水 -> 波峰，三段混色，整体偏蓝
	vec3 water = mix(deep_color, shallow_color, crest * 0.85 + 0.10);
	water = mix(water, crest_color, pow(crest, 3.0) * 0.45 * slope);
	ALBEDO = water;
	EMISSION = vec3(0.010, 0.024, 0.050) + vec3(0.020, 0.040, 0.060) * crest;
	ROUGHNESS = 0.34 - slope * 0.16;
	SPECULAR = 0.42;
	METALLIC = 0.0;
	// 波峰处稍亮，配合真实起伏更容易看出水面在动
	AO = 1.0;
}
"""

# 城内水渠：只有 1.6 米宽，细分与位移都没意义，保留薄面，只做偏蓝的流动色。
# 频率比洱海高，因为观察距离近。
const WATER_FLAT_SHADER := """
shader_type spatial;
render_mode diffuse_burley, cull_disabled;

uniform float flow_time = 0.0;
uniform float wave_speed = 1.35;
uniform vec3 deep_color : source_color = vec3(0.030, 0.150, 0.330);
uniform vec3 shallow_color : source_color = vec3(0.110, 0.370, 0.560);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float drift = flow_time * wave_speed;
	float a = sin(p.x * 1.15 + p.y * 0.85 - drift * 1.7);
	float b = sin(p.x * 0.62 - p.y * 1.35 - drift * 1.15);
	float ripple = 0.5 + 0.5 * (a * 0.55 + b * 0.45);
	ALBEDO = mix(deep_color, shallow_color, 0.18 + ripple * 0.72);
	EMISSION = vec3(0.008, 0.020, 0.040);
	ROUGHNESS = 0.36;
	SPECULAR = 0.40;
}
"""
