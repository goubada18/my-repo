extends SceneTree
## Verify shared sfx system: 3P (FPActionRetarget) has NO own sfx data/players;
## all channels play through FPViewmodelPlayer's shared slots/players (same instance).
## Plus: V-key view switch goes to idle (no draw anim/sfx).
func _init():
	var ps: PackedScene = load("res://scenes/player.tscn")
	var inst = ps.instantiate()
	root.add_child(inst)
	for i in range(20):
		await process_frame
	var fp_vm: Node = null
	var fp_action: Node = null
	for n in inst.get_children():
		var scr: String = str(n.get_script().resource_path) if n.get_script() != null else ""
		if "fp_viewmodel_player.gd" in scr:
			fp_vm = n
		if "fp_action_retarget.gd" in scr:
			fp_action = n
	if fp_vm == null or fp_action == null:
		printerr("FAIL: fp_vm=%s fp_action=%s" % [str(fp_vm), str(fp_action)])
		quit(1)
		return
	# 注入 M82 音效到共享层（模拟 _apply_weapon_to_subsystems 对 FP 侧注入）
	fp_vm.call("set_sfx_paths", "res://audio/m82a1_shoot.dat",
		"res://audio/AK47-HQL_KNIFE-ATTACK.dat", "res://audio/m82a1_reload.dat",
		"res://audio/m82a1_draw.dat", "res://audio/m82a1_bolt.dat")
	var ok := true
	# 1. 共享引用注入
	print("[1] _shared_sfx == _fp_vm ? %s" % str(fp_action.get("_shared_sfx") == fp_vm))
	ok = ok and fp_action.get("_shared_sfx") == fp_vm
	# 2. 3P 无自有音效槽/播放器
	var own: bool = fp_action.get("_sfx_shoot") != null or fp_action.get("_sfx_player") != null \
		or fp_action.get("_sfx_reload") != null or fp_action.get("_sfx_bolt") != null
	print("[2] 3P 无自有音效槽/播放器 ? %s" % str(not own))
	ok = ok and not own
	var sfx: AudioStreamPlayer = fp_vm.get("_sfx")
	var shoot_p: AudioStreamPlayer = fp_vm.get("_sfx_shoot_p")
	# 3. draw → 共享 _sfx.stream == 共享 draw 槽（同一实例）
	fp_action.call("trigger_draw")
	var ok3: bool = sfx.stream == fp_vm.get("_sfx_draw")
	print("[3] 3P draw → 共享 _sfx.stream==draw ? %s" % str(ok3))
	ok = ok and ok3
	# 4. shoot → 共享射击播放器
	fp_action.call("trigger_shoot")
	var ok4: bool = shoot_p.stream == fp_vm.get("_sfx_shoot")
	print("[4] 3P shoot → 共享 _sfx_shoot_p.stream==shoot ? %s" % str(ok4))
	ok = ok and ok4
	# 5. reload → 共享槽 + pitch（2.350s 换弹声 / 2.305s 动画 ≈ 1.020）
	fp_action.call("trigger_reload", 2.305)
	var nat: float = (fp_vm.get("_sfx_reload") as AudioStreamWAV).get_length()
	var expect_pitch: float = nat / 2.305
	var ok5: bool = sfx.stream == fp_vm.get("_sfx_reload") and absf(sfx.pitch_scale - expect_pitch) < 0.02
	print("[5] 3P reload → 共享槽 pitch=%.3f(应%.3f) ? %s" % [sfx.pitch_scale, expect_pitch, str(ok5)])
	ok = ok and ok5
	# 6. bolt 计时到点 → 共享槽
	fp_action.set("_bolt_timer", 0.001)
	fp_action.call("update", 0.002, Basis.IDENTITY)
	var ok6: bool = sfx.stream == fp_vm.get("_sfx_bolt")
	print("[6] 3P bolt → 共享 _sfx.stream==bolt ? %s" % str(ok6))
	ok = ok and ok6
	# 7. V 键切 FP：动画回待机（非 draw）
	var ap: AnimationPlayer = fp_vm.get("_ap")
	inst.call("_toggle_view_mode")
	for i in range(3):
		await process_frame
	var cur: String = String(ap.current_animation)
	var ok7: bool = cur.contains("idle") and not cur.contains("draw")
	print("[7] 切 FP 后动画=%s（应 idle 非 draw）? %s" % [cur, str(ok7)])
	ok = ok and ok7
	print("=> %s" % ("ALL PASS (共用音效 + 切视角直接待机)" if ok else "FAIL"))
	quit(0)
