extends SceneTree
## [updated] 3P sfx now routed through shared system: draw plays via _fp_vm._sfx,
## bolt timer set on shoot and counted in update; bolt plays via shared _sfx.
func _init():
	var ps: PackedScene = load("res://scenes/player.tscn")
	var inst = ps.instantiate()
	root.add_child(inst)
	for i in range(15):
		await process_frame
	var fa: Node = null
	var fv: Node = null
	for n in inst.get_children():
		var scr: String = str(n.get_script().resource_path) if n.get_script() != null else ""
		if "fp_action_retarget.gd" in scr:
			fa = n
		if "fp_viewmodel_player.gd" in scr:
			fv = n
	if fa == null or fv == null:
		printerr("FAIL")
		quit(1)
		return
	# 注入共享音效（M82：draw/bolt）
	fv.call("set_sfx_paths", "res://audio/m82a1_shoot.dat", "",
		"res://audio/m82a1_reload.dat", "res://audio/m82a1_draw.dat", "res://audio/m82a1_bolt.dat")
	fa.call("set_shared_sfx", fv)
	var sfx: AudioStreamPlayer = fv.get("_sfx")
	var d: AudioStreamWAV = fv.get("_sfx_draw")
	var b: AudioStreamWAV = fv.get("_sfx_bolt")
	print("draw=%s  bolt=%s" % [str(d != null), str(b != null)])
	fa.call("trigger_draw")
	var ok1: bool = sfx.stream == d
	print("trigger_draw -> shared _sfx.stream==draw ? %s" % str(ok1))
	fa.call("trigger_shoot")
	var t: float = float(fa.get("_bolt_timer"))
	print("trigger_shoot 后 _bolt_timer=%.2f (expect 1.38)" % t)
	var ok: bool = d != null and b != null and ok1 and absf(t - 1.38) < 0.05
	print("=> %s" % ("ALL PASS (3P 共用音效)" if ok else "FAIL"))
	quit(0)
