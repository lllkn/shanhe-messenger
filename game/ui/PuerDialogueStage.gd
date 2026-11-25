extends "res://ui/PortraitDialogueStage.gd"
## 普洱11个初次/再次/核心/收尾/旁白ID；不冒用丽江NPC。
const ART := "res://assets/characters/puer/"
const PORTRAITS := {
	"puer_arrival": "",
	"puer_interviews_end": "",
	"puer_hostess": ART + "hostess-v01.png",
	"puer_hostess_repeat": ART + "hostess-v01.png",
	"puer_farmer": ART + "farmer-v01.png",
	"puer_farmer_repeat": ART + "farmer-v01.png",
	"puer_novice": ART + "novice-v01.png",
	"puer_novice_repeat": ART + "novice-v01.png",
	"puer_yanxiang_visit": ART + "yanxiang-v01.png",
	"puer_yanxiang_farewell": ART + "yanxiang-v01.png",
	"puer_yanxiang_repeat": ART + "yanxiang-v01.png",
}
func stage_config(id: String) -> Dictionary:
	var data := {"portrait": PORTRAITS.get(id, "")}
	var spans := {"puer_arrival": [1,2], "puer_hostess": [0,8], "puer_farmer": [0,8], "puer_yanxiang_visit": [3,6], "puer_yanxiang_farewell": [0,2]}
	if id in spans:
		data.merge({"photo": ART + "brocade-photo-v01.png", "photo_title": "古锦 · 普洱文字线索", "phone_lines": spans[id], "zoom_text": "放大文字"})
	if id == "puer_yanxiang_visit":
		data.merge({"required_line": 4, "require_zoom": true, "confirm_text": "让岩香看照片", "instruction": "调亮到70%以上，放大文字后给岩香看。", "continue_hint": "请调亮并放大文字，再点击「让岩香看照片」"})
	if id == "puer_yanxiang_farewell":
		data["speaker_portraits"] = {"小沙弥": ART + "novice-v01.png"}
	return data
