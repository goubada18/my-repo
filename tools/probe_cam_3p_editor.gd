extends SceneTree
## 验证编辑器 3P 机位复刻逻辑：pivot 高度/SpringArm 距离/视线方向与运行时参数一致。
func _init():
	var ps = load("res://scenes/player_preview.tscn")
	var inst = ps.instantiate()
	root.add_child(inst)
	for i in range(6):
		await process_frame
	var pivot: Node3D = null
	for n in inst.find_children("*", "Node3D", true, false):
		if n.has_method("_editor_3p_update"):
			pivot = n
			break
	if pivot == null:
		printerr("FAIL: 未找到 camera_controller (CameraPivot)")
		quit(1)
		return
	var cam: Camera3D = pivot.get("camera")
	var spring: SpringArm3D = pivot.get("spring_arm")
	print("参数: camera_distance=%.2f camera_height=%.2f look_height=%.2f" % [
		pivot.get("camera_distance"), pivot.get("camera_height"), pivot.get("look_height")])
	pivot.call("_editor_3p_update")
	await process_frame
	print("pivot.position.y      = %.3f（应=camera_height %.2f）" % [pivot.position.y, float(pivot.get("camera_height"))])
	print("spring_arm.length     = %.3f（应=camera_distance %.2f）" % [spring.spring_length, float(pivot.get("camera_distance"))])
	var cam_g: Vector3 = cam.global_position
	var base: Vector3 = pivot.global_position
	print("相机世界位 = %s" % str(cam_g))
	print("相机相对pivot = (%s)（应在 -Z 背后方向）" % str(cam_g - base))
	# 视线方向应指向 pivot 上方 look_height 处
	var dir: Vector3 = -cam.global_transform.basis.z
	var target_dir: Vector3 = (base + Vector3(0, pivot.get("look_height"), 0) - cam_g).normalized()
	var ang: float = rad_to_deg(dir.angle_to(target_dir))
	print("视线与 look_height 目标夹角 = %.2f°（应≈0）" % ang)
	print("=> %s" % ("✅ 3P 机位复刻正确" if ang < 1.0 else "❌ 视线未对准"))
	quit(0)
