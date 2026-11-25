extends Node
var failures := 0
var count := 0
func _ready() -> void:
 get_tree().current_scene = null
 var source: Dictionary = ContentDB.read_json("res://data/xianggelila_city.json")["copy"]
 var dir := DirAccess.open("res://data/dialogues")
 for file in dir.get_files():
  if not file.begins_with("xianggelila_") or not file.ends_with(".json"): continue
  var id := file.trim_suffix(".json")
  var dialogue = load("res://scenes/DialogueScene.tscn").instantiate()
  dialogue.configure_inline(id)
  add_child(dialogue)
  for index in dialogue.lines.size():
   dialogue.line_idx = index
   dialogue._goto_line(index)
   dialogue._continue()
   await get_tree().process_frame
   await get_tree().process_frame
   var line: Dictionary = dialogue.lines[index]
   count += 1
   var rect: Rect2 = dialogue._text_label.get_global_rect()
   var slot: Rect2 = dialogue._body_slot.get_global_rect()
   var screen := Rect2(Vector2.ZERO,get_viewport().get_visible_rect().size)
   if line["text"] != source[line["copy_id"]] or not screen.encloses(rect) or not slot.encloses(rect) or dialogue._text_label.get_content_height() > dialogue._text_label.size.y+1:
    failures += 1
    printerr("FAIL: ", id," ",index," rect=",rect," slot=",slot," content=",dialogue._text_label.get_content_height())
  dialogue.queue_free()
  await get_tree().process_frame
 print("XIANGGELILA_TEXT_TEST lines=",count," failures=",failures)
 get_tree().quit(failures)
