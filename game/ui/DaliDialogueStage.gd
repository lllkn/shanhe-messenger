extends "res://ui/PortraitDialogueStage.gd"
## 大理独立身份、源台词ID和照片事件；使用最新共用排版与手机输入。
const ART := "res://assets/characters/dali/"
const PORTRAITS := {
	"dali_arrival": "", "dali_zhaobi": "", "dali_pagodas": "",
	"dali_vendor": ART + "vendor-v01.png",
	"dali_vendor_repeat": ART + "vendor-v01.png",
	"dali_vendor_done": ART + "vendor-v01.png",
	"dali_youngster": ART + "youngster-v01.png",
	"dali_youngster_repeat": ART + "youngster-v01.png",
	"dali_youngster_done": ART + "youngster-v01.png",
	"dali_granny": ART + "granny-v01.png",
	"dali_granny_repeat": ART + "granny-v01.png",
	"dali_granny_done": ART + "granny-v01.png",
	"dali_popo_visit": "res://assets/puzzles/dali/npc_popo.png",
	"dali_popo_farewell": "res://assets/puzzles/dali/npc_popo.png",
	"dali_popo_repeat": "res://assets/puzzles/dali/npc_popo.png",
}
var current_portrait := ""

func stage_config(id: String) -> Dictionary:
	var data := ContentDB.read_json("res://data/dialogues/%s.json" % id)
	var source: Dictionary = data.get("stage", {})
	var result := {"portrait": PORTRAITS.get(id, ""), "speaker_portraits": source.get("speaker_portraits", {})}
	current_portrait = result["portrait"]
	var photo: Dictionary = source.get("phone", {})
	if photo.is_empty(): return result
	var sources: Array = data["lines"].map(func(line: Dictionary): return line.get("source_line", ""))
	var show: Array = photo["show"]
	result.merge({"photo": photo["photo"], "photo_title": "古锦 · 大理纹样线索", "phone_lines": [sources.find(show.front()), sources.find(show.back())], "required_line": sources.find(photo["required"]), "require_zoom": photo.get("require_zoom", false), "confirm_text": photo["confirm_label"], "instruction": photo["instruction"], "continue_hint": photo["hint"]})
	return result

func show_line(index: int, speaker: String) -> void:
	var portraits: Dictionary = config.get("speaker_portraits", {})
	if portraits.has(speaker): current_portrait = portraits[speaker]
	super.show_line(index, speaker)
	# 女主与旁白发言时保留最近交谈NPC，收尾姑娘/婆婆发言才切换。
	if not current_portrait.is_empty(): npc.texture = load(current_portrait)
	if speaker == "报道文字": npc.modulate = Color(0.72, 0.76, 0.74)
