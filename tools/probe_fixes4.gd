extends SceneTree
## 验证探针：本轮四项修复的行为验证
## ④ Q 键 last-weapon toggle（开局→第二把/往返切换，必须在任何切枪前先测）
## ① 首枪预览就绪（set_anim_map 清空后重新预建） ② 手枪射击动画压缩到 fire_rate
## ③ 狙击 3P 包络=fire_rate
func _init():
	var ps = load("res://scenes/main_multichar.tscn")
	var m = ps.instantiate()
	root.add_child(m)
	for i in range(30):
		await process_frame
	var p = root.find_child("Player", true, false)
	var fails: Array = []

	# ④ Q 键 toggle（最先测：开局状态 prev 为空）
	var slot_list: Array = p._weapon_system.get_slot_weapons(p.WEAPON_SLOT_IDS)
	var second_id: String = (slot_list[1] as WeaponDef).id if slot_list.size() >= 2 else ""
	p._switch_prev_weapon()
	var w1: String = p._weapon_system.get_current_weapon().id
	p._select_weapon_by_id("m82a1")
	for i in range(5):
		await process_frame
	p._switch_prev_weapon()
	var w2: String = p._weapon_system.get_current_weapon().id
	p._switch_prev_weapon()
	var w3: String = p._weapon_system.get_current_weapon().id
	print("④ Q 链: 开局Q→%s（期望第二把=%s） 选m82后Q→%s（期望 v_deagle=选狙击前持有） 再Q→%s（期望 m82a1）" % [w1, second_id, w2, w3])
	if w1 != second_id or w2 != "v_deagle" or w3 != "m82a1": fails.append("④")

	# ① AK47 启动+往返切枪后 shoot2_preview 应存在（set_anim_map 重建后预建）
	p._select_weapon_by_id("ak47")
	for i in range(10):
		await process_frame
	var vm = p.get("_fp_vm")
	var ok1: bool = vm._ap.has_animation("shoot2_preview")
	print("① 首枪预览就绪(ak47 shoot2_preview 存在): ", ok1)
	if not ok1: fails.append("①")

	# ② 手枪：切 v_deagle → trigger_shoot → 动画速度保持 1.0（中断式，不加速），
	#    锁在 fire_rate(0.22s) 内为真；等待解锁后动画必须【仍在播放】（未到 0.692s 结束）
	#    = 锁提前于动画结束释放，玩家此时点击即硬中断上一发动画。
	p._select_weapon_by_id("v_deagle")
	for i in range(10):
		await process_frame
	vm = p.get("_fp_vm")
	vm.trigger_shoot()
	var spd: float = vm._ap.speed_scale
	var locked_now: bool = vm.is_shoot_locked()
	var guard := 0
	while vm.is_shoot_locked() and guard < 600:
		await process_frame
		guard += 1
	var pos_at_release: float = vm._ap.current_animation_position
	var shooting_at_release: bool = vm.is_shoot()
	print("② 手枪 speed=%.2f（期望1.0 不加速） 刚击发锁=%s（期望true） 解锁时进度=%.2fs（应≥0.22） 解锁时动画仍播=%s（期望true） 等待帧=%d" % [
		spd, str(locked_now), pos_at_release, str(shooting_at_release), guard])
	if absf(spd - 1.0) > 0.01 or not locked_now or not shooting_at_release \
			or pos_at_release < 0.21 or pos_at_release > 0.691: fails.append("②")

	# ③ 狙击：3P 包络时长应=fire_rate(1.2)
	p._select_weapon_by_id("m82a1")
	for i in range(10):
		await process_frame
	var act = p.get("_fp_action")
	var dur: float = act._shoot_duration()
	print("③ 狙击 3P 包络时长=%.2f（期望 1.2，旧值 0.52）" % dur)
	if absf(dur - 1.2) > 0.01: fails.append("③")

	if fails.is_empty():
		print("PROBE_OK>>> 四项修复全部通过")
		quit(0)
	else:
		print("PROBE_FAIL>>> 未通过: ", str(fails))
		quit(1)
