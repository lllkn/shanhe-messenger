extends "res://ui/PortraitDialogueStage.gd"
## 丽江身份与照片事件；排版及输入使用共用舞台。
const ART := "res://assets/characters/lijiang/"
const PORTRAITS := {
	"lijiang_silver": ART + "silver-v01.png",
	"lijiang_silver_repeat": ART + "silver-v01.png",
	"lijiang_student": ART + "student-v01.png",
	"lijiang_student_repeat": ART + "student-v01.png",
	"lijiang_inn": ART + "inn-v01.png",
	"lijiang_inn_repeat": ART + "inn-v01.png",
	"lijiang_dongba_visit": "res://assets/puzzles/lijiang/npc_dongba.png",
	"lijiang_dongba_farewell": "res://assets/puzzles/lijiang/npc_dongba.png",
	"lijiang_dongba_repeat": "res://assets/puzzles/lijiang/npc_dongba.png",
}

func stage_config(id: String) -> Dictionary:
	var data := {"portrait": PORTRAITS.get(id, "")}
	if id == "lijiang_dongba_visit":
		data.merge({"photo": ART + "brocade-photo-v03.png", "phone_lines": [6,14], "required_line": 8, "allow_adjustment": true, "require_zoom": true, "confirm_text": "让阿东巴看照片", "instruction": "调亮到70%以上并放大纹样，再递给阿东巴。", "continue_hint": "请先调亮并放大纹样，再点击「让阿东巴看照片」"})
	return data
