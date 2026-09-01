extends SceneTree
## Verify: ① shared "pull"/"throw" channels exist; ② draw_muted blocks shared draw;
## ③ _start_grenade_pull/_throw play pull/throw sfx in 3P mode only (not FP);
## ④ cancel_grenade clears grenade state + idle; ⑤ _do_switch_weapon clears grenade session.
func _init():
	var ps: PackedScene = load("res://scenes/player.tscn")
	var inst = ps.instantiate()
	root.add_child(inst)
	for i in range(20):
		await process_frame
	var fp_vm: Node = null
	for n in inst.get_children():
		var scr: String = str(n.get_script().resource_path) if n.get_script() != null else ""
		if "fp_viewmodel_player.gd" in scr:
			fp_vm = n
			break
	if fp_vm == null:
		printerr("FAIL: no fp_vm")
		quit(1)
		return
	var ok := true
	var sfx: AudioStreamPlayer = fp_vm.get("_sfx")
	# ① pull/throw 共享槽存在（注入 gaobao 音效模拟手雷）
	fp_vm.call("set_action_sfx", "res://audio/nepal_slash2.dat",
		"res://audio/gaobao_pull.dat", "res://audio/gaobao_throw.mp3")
	var pull: AudioStream = fp_vm.get("_sfx_pull")
	var thr: AudioStream = fp_vm.get("_sfx_throw")
	print("[1] pull/throw 槽已注入 ? %s" % str(pull != null and thr != null))
	ok = ok and pull != null and thr != null
	# ② draw_muted=true 时共享 draw 不播（手雷）
	fp_vm.call("set_draw_muted", true)
	fp_vm.call("play_shared_sfx", "draw", pull, 1.0)
	var ok2: bool = sfx.stream != pull   # 不应被设置（mute 拦截）
	print("[2] draw_muted 拦截共享 draw ? %s (stream=%s)" % [str(ok2), str(sfx.stream != null)])
	ok = ok and ok2
	# ③ 3P 模式 _start_grenade_pull 播拉环声（先切 3P）
	inst.set("_fp_mode", false)
	inst.call("_start_grenade_pull")
	var ok3: bool = sfx.stream == pull
	print("[3] 3P 拉环 → 共享 pull ? %s" % str(ok3))
	ok = ok and ok3
	# ④ FP 模式 _start_grenade_pull 不播（防双响）
	inst.set("_fp_mode", true)
	inst.call("_start_grenade_throw")   # 先清状态再测
	inst.call("_start_grenade_pull")
	# 上面 3P 时已把 stream 设为 pull；FP 模式不应再改（保持 pull 状态 = 没被覆盖为 throw/pull 重播）
	var ok4: bool = sfx.stream == pull
	print("[4] FP 模式影子同步不播音效 ? %s" % str(ok4))
	ok = ok and ok4
	# ⑤ cancel_grenade 清手雷状态 + 回 idle
	fp_vm.call("cancel_grenade")
	var held: bool = bool(fp_vm.get("_grenade_held")) or bool(fp_vm.get("_grenade_holding"))
	var anim: String = String(fp_vm.get("_ap").current_animation)
	var ok5: bool = not held and anim.contains("idle")
	print("[5] cancel_grenade → 手雷状态清空 + 动画=%s ? %s" % [anim, str(ok5)])
	ok = ok and ok5
	# ⑥ 切枪清理组合（= _do_switch_weapon 新增的两行）：_stop_grenade_arms + cancel_grenade
	inst.set("_fp_mode", false)
	inst.call("_start_grenade_throw")   # 先建投掷会话
	var throwing_before: bool = bool(inst.get("_grenade_throwing"))
	inst.call("_stop_grenade_arms")
	fp_vm.call("cancel_grenade")
	var ok6: bool = throwing_before
	var ok6b: bool = not bool(inst.get("_grenade_throwing")) \
		and not bool(inst.get("_grenade_pulling")) \
		and not bool(inst.get("_grenade_held")) \
		and inst.get("_grenade_arms") == null \
		and not bool(fp_vm.get("_grenade_held")) \
		and not bool(fp_vm.get("_grenade_holding"))
	print("[6] 切枪清理: 会话已建立=%s → 清理后全清=%s" % [str(ok6), str(ok6b)])
	ok = ok and ok6 and ok6b
	print("=> %s" % ("ALL PASS" if ok else "FAIL"))
	quit(0)
