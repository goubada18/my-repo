extends SceneTree
## Verify nepal LMB hold: set_hold(true) -> update() fires repeatedly -> toggle alternates.
func _init():
	var ps: PackedScene = load("res://scenes/player.tscn")
	var inst = ps.instantiate()
	root.add_child(inst)
	for i in range(15):
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
	fp_vm.set("_alt_shoot_anim", "midslash2")
	fp_vm.set("_sfx_alt", AudioWavLoader.load_wav("res://audio/nepal_slash2.dat"))
	fp_vm.call("set_sfx_paths", "res://audio/nepal_slash1.dat", "", "", "", "")
	fp_vm.call("set_fire_interval", 0.05)   # 加速测试（实际 0.55s）
	# 模拟长按：首次 trigger + set_hold(true)，然后 update 连发
	fp_vm.call("interrupt_shoot")
	fp_vm.call("trigger_shoot")
	fp_vm.call("set_hold", true)
	var seq: Array = []
	for k in range(12):
		fp_vm.call("update", 0.05)
		var tg: bool = bool(fp_vm.get("_shoot_alt_toggle"))
		seq.append(tg)
	# 期望：长按期间 toggle 不断翻转（true/false 交替 >=3 次）
	var flips: int = 0
	for i in range(1, seq.size()):
		if seq[i] != seq[i-1]:
			flips += 1
	print("长按连发触发 toggle 序列: %s" % str(seq))
	print("翻转次数 = %d (期望 >=3，说明持续交替)" % flips)
	var ok: bool = flips >= 3
	print("=> %s" % ("ALL PASS (长按交替连发)" if ok else "FAIL"))
	quit(0)
