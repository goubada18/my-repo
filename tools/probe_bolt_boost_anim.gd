extends SceneTree
## Verify full bolt-boost: draw anim speed_scale = divisor, draw sfx pitch = divisor,
## bolt timer scaled, speed restored after draw finishes.
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
		printerr("FAIL")
		quit(1)
		return
	var ok := true
	var DIV := 2.2
	# ① set_draw_boost + trigger_draw → 动画 speed_scale 与音效 pitch 同步
	fp_vm.call("set_draw_boost", DIV)
	fp_vm.call("trigger_draw")
	var ap: AnimationPlayer = fp_vm.get("_ap")
	var spd: float = ap.speed_scale
	var sfx: AudioStreamPlayer = fp_vm.get("_sfx")
	var pitch: float = sfx.pitch_scale
	print("[1] draw 加速: speed_scale=%.2f（应 2.20） draw 音效 pitch=%.2f（应 2.20）" % [spd, pitch])
	ok = ok and absf(spd - DIV) < 0.01 and absf(pitch - DIV) < 0.01
	# ② 普通切枪 set_draw_boost(1.0) → 原速
	fp_vm.call("set_draw_boost", 1.0)
	fp_vm.call("trigger_draw")
	var spd2: float = ap.speed_scale
	print("[2] 普通出枪: speed_scale=%.2f（应 1.00）" % spd2)
	ok = ok and absf(spd2 - 1.0) < 0.01
	# ③ scale_bolt_timer：拉栓声剩余计时缩短
	fp_vm.set("_bolt_timer", 1.38)
	fp_vm.call("scale_bolt_timer", DIV)
	var bt: float = float(fp_vm.get("_bolt_timer"))
	print("[3] 拉栓声计时 1.38 ÷%.1f = %.3f（应 0.627）" % [DIV, bt])
	ok = ok and absf(bt - 1.38 / DIV) < 0.01
	# ④ draw 播完回 idle → speed_scale 恢复 1.0
	fp_vm.call("set_draw_boost", DIV)
	fp_vm.call("trigger_draw")
	ap.seek(ap.current_animation_length - 0.05)
	await process_frame
	await process_frame
	var spd3: float = ap.speed_scale
	print("[4] draw 播完回 idle: speed_scale=%.2f（应 1.00 自动恢复）" % spd3)
	ok = ok and absf(spd3 - 1.0) < 0.01
	print("=> %s" % ("ALL PASS (拉栓整体加速)" if ok else "FAIL"))
	quit(0)
