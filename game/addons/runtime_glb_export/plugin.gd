@tool
extends EditorPlugin
## 地图和人物通过 GLTFDocument 运行时读取；常规导出只保留导入后的场景。

class RawGltfExport extends EditorExportPlugin:
	func _get_name() -> String:
		return "ShanheRuntimeGLB"

	func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
		if path.get_extension().to_lower() == "glb":
			add_file(path, FileAccess.get_file_as_bytes(path), false)

var exporter := RawGltfExport.new()

func _enter_tree() -> void:
	add_export_plugin(exporter)

func _exit_tree() -> void:
	remove_export_plugin(exporter)
