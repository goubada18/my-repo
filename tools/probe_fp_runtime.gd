extends SceneTree
## 验证：游戏本体 player.tscn 的 FP 相机运行时位置 = 用户调好的参数。
## 加载 player.tscn → CameraPivot → set_first_person(true) → 读相机世界位置。
func _init():
	var ps: PackedScene = load("res://scenes/player.tscn")
	if ps == null:
		printerr("FAIL: player.tscn 无法加载")
		quit(1)
		return
	var inst = ps.instantiate()
	root.add_child(inst)
	for i in range(10):
		await process_frame
	var pivot: Node3D = inst.get_node_or_null("CameraPivot")
	if pivot == null:
		printerr("FAIL: 无 CameraPivot")
		quit(1)
		return
	# 1. 参数确认（读的就是场景里保存的）
	var eh: float = float(pivot.get("fp_eye_height"))
	var off: Vector3 = pivot.get("fp_offset")
	print("参数: fp_eye_height=%.3f fp_offset=%s" % [eh, str(off)])
	# 2. 切 FP（运行时 V 键同款）；关垂直平滑做精确验证（_y_lag=0，相机 y 应精确=角色y+眼睛高）
	pivot.set("vertical_smoothing", 0.0)
	pivot.call("set_first_person", true, 70.0)
	for i in range(40):
		await process_frame
	var cam: Camera3D = pivot.get("camera")
	var base: Vector3 = inst.global_position
	var pivot_local_y: float = pivot.position.y
	print("pivot.local.y = %.3f（应=fp_eye_height 2.700）" % pivot_local_y)
	var expect: Vector3 = Vector3(base.x + off.x, base.y + eh + off.y, base.z + off.z)
	var actual: Vector3 = cam.global_position
	var err: float = actual.distance_to(expect)
	print("角色位置=%s" % str(base))
	print("FP 相机实际=%s  期望=%s  误差=%.4f m" % [str(actual), str(expect), err])
	print("=> %s" % ("✅ 游戏 FP 位置已生效（参数驱动）" if err < 0.02 and absf(pivot_local_y - 2.7) < 0.01 else "❌ 未生效"))
	# 3. FP 相机应朝角色前方 +Z（运行时 fixed 朝向）
	var fwd: Vector3 = -cam.global_transform.basis.z
	var ok_dir: bool = fwd.dot(Vector3(0, 0, 1)) > 0.99
	print("相机朝向=%s %s" % [str(fwd), "✅ 朝角色前方(+Z)" if ok_dir else "❌"])
	quit(0)
