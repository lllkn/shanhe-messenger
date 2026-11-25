extends "res://ui/PortraitDialogueStage.gd"
## 终章对话使用二维卡通立绘；地图与拍照镜头继续由原3D场景呈现。
const ART := "res://assets/characters/gucheng/"
const PORTRAITS := {"gucheng_arrival": "", "gucheng_mulaoye_visit": ART + "mulaoye-portrait-v01.png", "gucheng_mulaoye_repeat": ART + "mulaoye-portrait-v01.png"}
var xiaomu: TextureRect

func stage_config(id: String) -> Dictionary:
	return {"portrait": PORTRAITS.get(id, "")}

func prepare(id: String) -> void:
	super.prepare(id)
	if id == "gucheng_arrival":
		protagonist.hide()
		return
	protagonist.texture = load(ART + "protagonist-portrait-v01.png")
	protagonist.position = Vector2(905, 106)
	protagonist.size = Vector2(330, 336)
	protagonist.flip_h = true
	protagonist.show()
	xiaomu = _image(ART + "xiaomu-portrait-v01.png", Vector2(432, 118), Vector2(330, 324))
	xiaomu.flip_h = true
	xiaomu.hide()

func show_line(index: int, speaker: String) -> void:
	if _dialogue_id == "gucheng_arrival": return
	npc.modulate = Color.WHITE if speaker == "木老爷" else Color(0.74, 0.76, 0.74)
	protagonist.modulate = Color.WHITE if speaker == "主角" else Color(0.74, 0.76, 0.74)
	xiaomu.visible = _dialogue_id == "gucheng_mulaoye_repeat" or index >= 9
	xiaomu.modulate = Color.WHITE if speaker == "小木" else Color(0.74, 0.76, 0.74)
