extends Node
## 当前流水线玩法回归：误选恢复、轨道稳定、悬停减速、超时与完整通关。
var _failures := 0

func _check(cond: bool, name: String) -> void:
	if cond:
		print("  PASS  ", name)
	else:
		_failures += 1
		printerr("  FAIL  ", name)

func _ready() -> void:
	var scene = load("res://scenes/puzzles/PuzzleGlyph.tscn").instantiate()
	get_tree().root.add_child.call_deferred(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	# 测试使用内存 GameState，不写玩家的真实存档。
	scene._gs = PuzzleBase.MockGameState.new()
	scene.add_child(scene._gs)
	_check(scene.station_id == "lijiang", "正确载入丽江配置")
	_check(scene._pair_of_glyph.size() == 6, "六组字画")
	scene._on_intro_start()
	_check(scene._busy, "发牌期间锁定输入")
	await get_tree().create_timer(0.65).timeout
	_check(not scene._busy, "发牌落定后可选")
	_check(scene._glyph_card.position.is_equal_approx(Vector2(430, 208)), "字牌落在左侧新位置")

	var correct: String = scene._pair_of_glyph[scene._current_glyph]
	var wrong_sids: Array = []
	for sid in scene._belt_cards:
		if sid != correct:
			wrong_sids.append(sid)
	for i in 3:
		scene._on_pick(wrong_sids[i])
	_check(scene._score == -15, "三次错选扣分")
	_check(scene._wrong_streak == 0, "第三次错选给金边提示")
	_check(scene._belt_cards[wrong_sids[0]].disabled, "当前题错选卡变灰禁用")
	scene._on_pick(wrong_sids[0])
	_check(scene._score == -15, "重复点击灰卡不会再次扣分")

	# 悬停减速后离开会恢复，避免速度跳变。
	scene._hovered_sketch = correct
	await get_tree().create_timer(0.55).timeout
	_check(scene._belt_velocity < scene._belt_speed * 0.3, "悬停平滑减速")
	scene._hovered_sketch = ""
	await get_tree().create_timer(0.55).timeout
	_check(is_equal_approx(scene._belt_velocity, scene._belt_speed), "离开恢复流速")

	scene._on_pick(correct)
	_check(scene._belt_cards.size() == 6, "收牌不会改变流水线周长")
	_check(scene._matched_sketches.size() == 1, "正确卡记为已配对")
	await get_tree().create_timer(1.5).timeout
	_check(not scene._belt_cards[wrong_sids[0]].disabled, "下一题恢复之前的错选卡")
	_check(scene._belt_cards[correct].disabled, "已配对的卡保持禁用")

	# 结算动画中超时：旧动画不能继续发牌污染新一轮。
	scene._on_pick(scene._pair_of_glyph[scene._current_glyph])
	scene._countdown = 0.02
	await get_tree().create_timer(2.3).timeout
	_check(scene._score == 0 and scene._matched_sketches.is_empty(), "超时完整重置分数与配对")
	_check(scene._deal_queue.size() == 5, "超时后的旧收牌回调不重复发牌")
	_check(not scene._busy, "重开发牌结束后可操作")

	# 全配对 → 第二关 → 结算。
	for i in 6:
		var sid: String = scene._pair_of_glyph[scene._current_glyph]
		scene._on_pick(sid)
		await get_tree().create_timer(1.5).timeout
	_check(scene._l1_result_layer != null, "第一关结束展示独立结算")
	scene._continue_to_level2()
	_check(scene._level == 1, "结算入场结束前不会误切第二关")
	await get_tree().create_timer(1.0).timeout
	_check(scene._l1_result_score.text == "60", "结算滚动得分正确")
	_check(not scene._timing and not scene._belt_moving, "结算冻结计时与流水线")
	_check(not scene._finished and scene._gs.fragments.is_empty(), "阶段结算不发最终碎片")
	scene._continue_to_level2()
	scene._continue_to_level2()
	await get_tree().create_timer(0.70).timeout
	scene._continue_to_level2() # 过渡层释放之后再次触发也应安全。
	_check(scene._l1_result_layer == null and not scene._transitioning, "重复继续不重入且过渡层正常清理")
	_check(is_equal_approx(scene._l2_root.modulate.a, 1.0) and is_zero_approx(scene._l2_root.position.y), "第二关淡入后归位")
	_check(scene._score == 60, "六张全部正确得60分")
	_check(scene._level == 2 and scene._l2_root.visible, "顺利进入第二关")
	_check(scene._matched_minis.size() == 12, "六对收牌完成")
	var pids: Array = scene._page_correct_order.keys()
	# 真正走吸附逻辑，核对占用槽交换和丢回桌面。
	var first_page: TextureRect = scene._pages[pids[0]]
	var second_page: TextureRect = scene._pages[pids[1]]
	first_page.position = scene._slots[0]["rect"].position
	scene._drop_page(first_page)
	second_page.position = scene._slots[1]["rect"].position
	scene._drop_page(second_page)
	first_page.position = scene._slots[1]["rect"].position
	scene._drop_page(first_page)
	_check(scene._slots[0]["page_id"] == pids[1] and scene._slots[1]["page_id"] == pids[0], "拖入占用槽位可交换残页")
	first_page.position = Vector2(20, 120)
	scene._drop_page(first_page)
	_check(scene._slots[1]["page_id"] == "" and scene._submit_btn.disabled, "放回桌面清除原槽位并禁用拼合")
	await get_tree().create_timer(0.35).timeout
	_check(first_page.position.is_equal_approx(first_page.get_meta("home")), "桌面外松手动画返回原位")
	for pid in pids:
		var wrong_slot: int = int(scene._page_correct_order[pid]) % 4
		scene._slots[wrong_slot]["page_id"] = pid
	scene._refresh_submit()
	scene._on_submit()
	_check(scene._fail_count == 1 and not scene._finished, "第二关错误排序不结算")
	for pid in pids:
		var idx: int = scene._page_correct_order[pid] - 1
		scene._slots[idx]["page_id"] = pid
	scene._refresh_submit()
	scene._on_submit()
	_check(scene._finished, "第二关正确排序结算")
	await get_tree().create_timer(2.3).timeout
	var gs: Node = scene._gs
	_check(gs.has_fragment("frag_dongba_tea") and gs.is_puzzle_solved("lijiang"), "正常发放碎片与记录通关")
	print("== failures: ", _failures, " ==")
	get_tree().quit(_failures)
