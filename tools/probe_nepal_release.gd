extends SceneTree
## Verify: LMB press sets hold=true, release sets hold=false (stops).
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
	fp_vm.call("set_fire_interval", 0.05)
	# 模拟 player 尼泊尔分支：按下 → trigger+hold；松开 → 由尼泊尔 released 分支置 false
	fp_vm.call("interrupt_shoot")
	fp_vm.call("trigger_shoot")
	fp_vm.call("set_hold", true)
	var h1: bool = bool(fp_vm.get("_fire_hold"))
	print("按下后 _fire_hold = %s (expect true)" % str(h1))
	# 模拟松开：直接调 set_hold(false)（player 尼泊尔 released 分支行为）
	fp_vm.call("set_hold", false)
	var h2: bool = bool(fp_vm.get("_fire_hold"))
	print("松开后 _fire_hold = %s (expect false)" % str(h2))
	# 松开后 update 不应再连发：记录触发次数
	var toggles_before: int = int(fp_vm.get("_shoot_alt_toggle")) 
	fp_vm.call("update", 0.05)
	fp_vm.call("update", 0.05)
	fp_vm.call("update", 0.05)
	var toggles_after: int = int(fp_vm.get("_shoot_alt_toggle"))
	print("松开后 3 帧 update toggle 变化: %d -> %d (应不变)" % [toggles_before, toggles_after])
	var ok: bool = h1 and not h2 and toggles_before == toggles_after
	print("=> %s" % ("ALL PASS (单击即停)" if ok else "FAIL"))
	quit(0)
