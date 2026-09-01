extends SceneTree
## Verify: melee slash sfx delay = anim_len*0.45 - 0.15 (midslash1 0.74s -> 0.183s).
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
	# 注入近战配置（模拟尼泊尔：alt 动画存在 → 走延迟分支）
	fp_vm.set("_alt_shoot_anim", "midslash2")
	fp_vm.set("_sfx_alt", AudioWavLoader.load_wav("res://audio/nepal_slash2.dat"))
	fp_vm.call("set_sfx_paths", "res://audio/nepal_slash1.dat", "", "", "", "")
	# 触发（轻击）
	fp_vm.call("trigger_shoot")
	var t: float = float(fp_vm.get("_slash_sfx_timer"))
	var expect: float = 0.74 * 0.45 - 0.15
	print("slash sfx timer = %.3f (expect %.3f = 0.74*0.45-0.15)" % [t, expect])
	var ok: bool = absf(t - expect) < 0.02
	# 枪械（无 alt）：timer 应为 -1（立即播）
	fp_vm.set("_alt_shoot_anim", "")
	fp_vm.call("trigger_shoot")
	var t2: float = float(fp_vm.get("_slash_sfx_timer"))
	print("gun (no alt) timer = %.3f (expect -1, immediate)" % t2)
	ok = ok and t2 == -1.0
	print("=> %s" % ("ALL PASS" if ok else "FAIL"))
	quit(0)
