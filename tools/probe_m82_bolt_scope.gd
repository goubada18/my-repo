extends SceneTree
func _init():
	# 1. M82 def 字段
	var def: Resource = load("res://resources/weapons/m82a1.tres")
	var scope: String = def.get("scope_sfx")
	var bolt: String = def.get("bolt_sfx")
	print("scope_sfx=%s  bolt_sfx=%s" % [scope, bolt])
	# 2. 音效可加载
	var sw: AudioStreamWAV = AudioWavLoader.load_wav(scope)
	var bw: AudioStreamWAV = AudioWavLoader.load_wav(bolt)
	print("scope load=%s (%.3fs)  bolt load=%s (%.3fs)" % [str(sw != null), sw.get_length() if sw else -1, str(bw != null), bw.get_length() if bw else -1])
	# 3. bolt 计时器逻辑（模拟）
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
		printerr("FAIL: no fp_vm")
		quit(1)
		return
	# 注入 bolt（模拟切枪注入路径）
	fp_vm.call("set_sfx_paths", "", "", "", "", "res://audio/m82a1_bolt.dat")
	# 触发射击（fire_blocked 默认 false）
	fp_vm.call("trigger_shoot")
	var t: float = float(fp_vm.get("_bolt_timer"))
	print("trigger_shoot 后 _bolt_timer = %.2f (应 1.3)" % t)
	var ok: bool = absf(t - 1.3) < 0.05 and sw != null and bw != null and scope != "" and bolt != ""
	print("=> %s" % ("ALL PASS" if ok else "FAIL"))
	quit(0)
