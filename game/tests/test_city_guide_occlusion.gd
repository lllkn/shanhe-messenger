extends Node3D
## 用实际像素验证遮挡修正；必须使用窗口渲染，不能用headless代替。
var failures := 0
var checks := 0
var arrow: MeshInstance3D
var cover: MeshInstance3D
var camera: Camera3D
var output := OS.get_environment("CITY_OCCLUSION_OUTPUT")

func check(ok: bool, message: String) -> void:
	checks += 1
	print("PASS: " if ok else "FAIL: ", message)
	if not ok: failures += 1

func box(dimensions: Vector3, position_at: Vector3, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	instance.mesh = mesh
	instance.position = position_at
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	instance.material_override = mat
	add_child(instance)
	return instance

func capture(name: String, fixed: bool) -> int:
	var base := arrow.material_override as StandardMaterial3D
	var repair: Material = base.next_pass
	if not fixed: base.next_pass = null
	for i in 5: await get_tree().process_frame
	RenderingServer.force_draw()
	var img := get_viewport().get_texture().get_image()
	var count := 0
	for y in img.get_height():
		for x in img.get_width():
			var color := img.get_pixel(x, y)
			if color.r > 0.6 and color.g > 0.4 and color.b < 0.4 and color.r > color.b*1.8:
				count += 1
	if not output.is_empty():
		check(img.save_png(output.path_join(name + ("-fixed" if fixed else "-before") + ".png")) == OK, "保存截图 " + name)
	base.next_pass = repair
	print("OCCLUSION_PIXELS ", name, " fixed=", fixed, " gold=", count)
	return count

func case_run(name: String, should_show: bool) -> void:
	var before := await capture(name, false)
	var after := await capture(name, true)
	if should_show:
		check(before < 10 and after > 100, name + "：遮挡复现，修复后箭头可见")
	else:
		check(before < 10 and after < 10, name + "：仍遮挡箭头，没有透视显示")

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("该测试需要实际渲染窗口")
		get_tree().quit(1)
		return
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.035, 0.05, 0.05)
	add_child(environment)
	camera = Camera3D.new()
	camera.position = Vector3(0, 6, 7)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.5
	camera.current = true
	add_child(camera)
	camera.look_at(Vector3.ZERO)
	box(Vector3(10, 0.1, 10), Vector3(0, -0.05, 0), Color(0.17, 0.22, 0.22))
	arrow = CityRouteGuide.new().create_mesh()
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector3(0, 0.09, 0)
	var vertices := PackedVector3Array([Vector3(0,0.09,-0.5), Vector3(-0.38,0.09,0.2), Vector3(0,0.09,0.07), Vector3(0,0.09,-0.5), Vector3(0,0.09,0.07), Vector3(0.38,0.09,0.2)])
	mesh.surface_set_color(Color(0.14, 0.14, 0.14))
	for vertex in vertices:
		var offset := vertex - center
		mesh.surface_add_vertex(center + Vector3(offset.x*1.22, -0.006, offset.z*1.22))
	mesh.surface_set_color(Color.WHITE)
	for vertex in vertices: mesh.surface_add_vertex(vertex)
	mesh.surface_end()
	arrow.mesh = mesh
	add_child(arrow)
	var clear_before := await capture("clear", false)
	var clear_after := await capture("clear", true)
	check(clear_before > 100 and abs(clear_after-clear_before) < 15, "无遮盖路面颜色和箭头保持一致")
	cover = box(Vector3(2, 0.3, 2), Vector3(0, 0.15, 0), Color(0.4, 0.45, 0.45))
	await case_run("raised-paving", true)
	cover.rotation.x = deg_to_rad(12)
	cover.position.y = 0.3
	await case_run("sloped-paving", true)
	cover.rotation = Vector3.ZERO
	(cover.mesh as BoxMesh).size = Vector3(2, 2.0, 0.15)
	cover.position = Vector3(0, 1.0, 0.5)
	await case_run("wall", false)
	(cover.mesh as BoxMesh).size = Vector3(4, 0.1, 4)
	cover.position = Vector3(0, 1.0, 0)
	await case_run("high-cover", false)
	camera.position = Vector3(0, 0.6, 5)
	camera.look_at(Vector3.ZERO)
	(cover.mesh as BoxMesh).size = Vector3(2, 0.6, 0.03)
	cover.position = Vector3(0, 0.3, 0.4)
	await case_run("low-vertical-wall", false)
	print("CITY_GUIDE_OCCLUSION_TEST checks=", checks, " failures=", failures, " renderer=", RenderingServer.get_current_rendering_method())
	get_tree().quit(failures)
