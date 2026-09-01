extends SceneTree
## Verify nepal LMB hold alternates midslash1/midslash2 (toggle) + alt sfx chosen.
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
	# 注入近战配置（模拟尼泊尔）
	fp_vm.set("_alt_shoot_anim", "midslash2")
	fp_vm.set("_sfx_alt", AudioWavLoader.load_wav("res://audio/nepal_slash2.dat"))
	fp_vm.call("set_sfx_paths", "res://audio/nepal_slash1.dat", "", "", "", "")
	# 模拟触发：记录 toggle 与音效流选择
	var seq: Array = []
	for k in range(4):
		fp_vm.call("trigger_shoot")
		var tg: bool = bool(fp_vm.get("_shoot_alt_toggle"))
		var stream: AudioStream = fp_vm.get("_sfx_shoot_p").stream
		var is_alt: bool = stream == fp_vm.get("_sfx_alt")
		var anim: String = String(fp_vm.get("_ap").current_animation)
		seq.append("t%d: toggle=%s alt_sfx=%s anim=%s" % [k, str(tg), str(is_alt), anim])
	for s in seq:
		print("  " + s)
	# 期望：toggle 交替 true/false；t0 轻击(shoot sfx)、t1 交替(alt sfx)……
	var ok: bool = true
	ok = ok and seq[0].contains("toggle=true") and seq[0].contains("alt_sfx=false")
	ok = ok and seq[1].contains("toggle=false") and seq[1].contains("alt_sfx=true")
	ok = ok and seq[2].contains("toggle=true") and seq[2].contains("alt_sfx=false")
	ok = ok and seq[3].contains("toggle=false") and seq[3].contains("alt_sfx=true")
	print("=> %s" % ("ALL PASS (交替循环)" if ok else "FAIL"))
	quit(0)
