class_name ClueBook
extends RefCounted
## 从原有访谈与存档标记读取线索，所有入口共享，不另存第二份收集进度。
const CITIES := {"lijiang": "丽江", "xianggelila": "香格里拉", "dali": "大理", "puer": "普洱"}
const CATEGORIES := {"lijiang": "东巴文字", "xianggelila": "手工染色", "dali": "扎染纹样", "puer": "贝叶文字"}
const COLORS := {"lijiang": Color("748c7c"), "xianggelila": Color("b56d56"), "dali": Color("668bab"), "puer": Color("a38a4b")}
const NOTES := {
	"lijiang/silver": ["纹样可能是文字", "银饰大姐觉得古锦上的纹样可能是文字。带着照片继续打听它的来历。"],
	"lijiang/student": ["认识东巴字的人", "小学生认出这是东巴字，但认识这些字的人越来越少。"],
	"lijiang/inn": ["阿东巴的坚持", "客栈老板提到阿东巴坚持不外传，家中的孩子也已经离开。"],
	"dali/vendor": ["眼熟的老花样", "摊主觉得照片上的花样眼熟，建议向扎染店年轻人打听。"],
	"dali/youngster": ["被水泡坏的纹样板", "老纹样板被水泡坏了，姑娘的奶奶仍记得那些花样，现在还在周城扎染坊做活。"],
	"dali/granny": ["带上照片和纸笔", "邻居建议带着照片和纸笔去拜访，边看婆婆画，边向她核对。"],
	"puer/hostess": ["读贝叶的人", "古锦上的字与奘房贝叶册上的字相似。岩香认得，也会抄，这几天正在整理旧册。"],
	"puer/farmer": ["口传的同路规矩", "茶农记得老人说过，结伴出门要互相分吃喝、等待落在后面的人。这些口述还需核对，不能直接当作古锦文字的意思。"],
	"puer/novice": ["把字和念读一起留下", "小沙弥建议先征求岩香同意，再拍摄贝叶；把文字、念读的人和讲解一起记下，才能看懂留下的内容。"],
}

static func entries(station_id := "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for city_id in CITIES:
		if not station_id.is_empty() and station_id != city_id: continue
		var story := ContentDB.read_json("res://data/%s_city.json" % city_id)
		var index := 0
		for interview in story.get("interviews", []):
			index += 1
			var key: String = city_id + "/" + interview["id"]
			var note: Array = NOTES.get(key, [interview.get("clue_title", interview.get("clue", "走访笔记")), interview.get("clue_text", interview.get("clue", ""))])
			result.append({"key": key, "station": city_id, "city": CITIES[city_id], "category": CATEGORIES[city_id], "color": COLORS[city_id], "id": interview["id"], "number": index, "title": note[0], "text": note[1], "unrevealed_name": interview["name"], "name": interview.get("revealed_name", interview["name"]), "place": interview["place"], "portrait": "res://assets/characters/%s/%s-v01.png" % [city_id, interview["id"]]})
	return result

static func entry(station_id: String, clue_id: String) -> Dictionary:
	for item in entries(station_id):
		if item["id"] == clue_id: return item
	return {}

static func collected(item: Dictionary) -> bool:
	return not item.is_empty() and GameState.has_flag("clue/" + item["key"])

static func count(station_id := "") -> int:
	var total := 0
	for item in entries(station_id):
		if collected(item): total += 1
	return total
