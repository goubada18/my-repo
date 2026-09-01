extends SceneTree
## Verify: model position stays at calibrated _apply_pose pose during alt (midslash2) anim.
func _init():
	var ps: PackedScene = load("res://scenes/player.tscn")
	var inst = ps.instantiate()
	root.add_child(inst)
	for i in range(20):
		await process_frame
	var pivot: Node3D = inst.get_node_or_null("CameraPivot")
	var cam: Camera3D = pivot.get("camera") if pivot != null else null
	if cam == null:
		printerr("FAIL: no cam")
		quit(1)
		return
	# 切 FP + 切到尼泊尔（走武器系统或直接注入 nepal 配置）
	# 直接找 _fp_vm 并注入 nepal 配置，模拟尼泊尔视图模型
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
	fp_vm.set("_alt_shoot_anim", "midslash2")
	fp_vm.call("set_sfx_paths", "res://audio/nepal_slash1.dat", "", "", "", "")
	var model: Node3D = fp_vm.get("_model")
	if model == null:
		printerr("FAIL: no model")
		quit(1)
		return
	# 记录单击（midslash1）时模型位置
	fp_vm.call("trigger_shoot")
	var p1: Vector3 = model.position
	var r1: Vector3 = model.rotation
	await process_frame
	await process_frame
	# 触发交替（第二次 = midslash2）
	fp_vm.call("trigger_shoot")
	var p2: Vector3 = model.position
	var r2: Vector3 = model.rotation
	print("单击(midslash1): pos=%s rot=%s" % [str(p1), str(r1)])
	print("交替(midslash2): pos=%s rot=%s" % [str(p2), str(r2)])
	var d: float = p1.distance_to(p2)
	print("位置差=%.6f (应≈0，位置由 _apply_pose 全局固定)" % d)
	# 对比配置期望值
	var cfg: Resource = load("res://fp_viewmodel/fp_view_config_nepal.tres")
	print("配置 fp_gun_pos=%s  fp_cam_pos=%s" % [str(cfg.get("fp_gun_pos")), str(cfg.get("fp_cam_pos"))])
	print("=> %s" % ("位置一致（交替与单击共用同一调校摆位）" if d < 0.001 else "❌ 位置被带偏"))
	quit(0)
