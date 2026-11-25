extends "res://ui/PortraitDialogueStage.gd"
## 香格里拉人物身份与copy_id照片事件，复用最新共用组件。
const PORTRAITS := {
  "xianggelila_cloth": "res://assets/characters/xianggelila/cloth-v01.png",
  "xianggelila_cloth_repeat": "res://assets/characters/xianggelila/cloth-v01.png",
  "xianggelila_visitor": "res://assets/characters/xianggelila/visitor-v01.png",
  "xianggelila_visitor_repeat": "res://assets/characters/xianggelila/visitor-v01.png",
  "xianggelila_son": "res://assets/characters/xianggelila/son-v01.png",
  "xianggelila_son_repeat": "res://assets/characters/xianggelila/son-v01.png",
  "xianggelila_danzeng_visit": "res://assets/puzzles/xianggelila/npc_danzeng.png",
  "xianggelila_danzeng_farewell": "res://assets/puzzles/xianggelila/npc_danzeng.png",
  "xianggelila_danzeng_repeat": "res://assets/puzzles/xianggelila/npc_danzeng.png",
  "xianggelila_danzeng_locked": "res://assets/puzzles/xianggelila/npc_danzeng.png",
  "xianggelila_retry": "res://assets/puzzles/xianggelila/npc_danzeng.png",
  "xianggelila_arrival": ""
}
var current_portrait := ""
var line_portraits: Dictionary = {}
var copy_ids: Array = []

func stage_config(id: String) -> Dictionary:
	var source: Dictionary = ContentDB.read_json("res://data/xianggelila_dialogue_stage.json")[id]
	var data := ContentDB.read_json("res://data/dialogues/"+id+".json")
	copy_ids = data["lines"].map(func(line: Dictionary): return line.get("copy_id", ""))
	line_portraits = source.get("line_portraits", {})
	var result := {"portrait": source["portrait"], "speaker_portraits": source.get("speaker_portraits", {})}
	current_portrait = source["portrait"]
	var photo: Dictionary = source.get("phone", {})
	if photo.is_empty(): return result
	var show: Array = photo["show"]
	result.merge({"photo": photo["photo"], "photo_title": "古锦 · 五色线索", "phone_lines": [copy_ids.find(show.front()),copy_ids.find(show.back())], "required_line": copy_ids.find(photo.get("required", "__none__")), "require_zoom": photo.get("require_zoom", false), "confirm_text": photo.get("confirm_label", "展示照片"), "instruction": photo.get("instruction", ""), "continue_hint": photo.get("hint", "")})
	return result

func show_line(index: int, speaker: String) -> void:
	var portraits: Dictionary = config.get("speaker_portraits", {})
	if portraits.has(speaker): current_portrait = portraits[speaker]
	if line_portraits.has(copy_ids[index]): current_portrait = line_portraits[copy_ids[index]]
	super.show_line(index, speaker)
	if not current_portrait.is_empty(): npc.texture = load(current_portrait)
