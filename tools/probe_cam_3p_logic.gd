extends SceneTree
## 纯逻辑验证 v2：_editor_3p_update 相机世界位置与视线（含 SpringArm 180° 旋转）。
func _init():
	var owner_node := Node3D.new()
	owner_node.name = "Owner"
	owner_node.position = Vector3(10, 0, 20)
	root.add_child(owner_node)
	var pivot := Node3D.new()
	owner_node.add_child(pivot)
	pivot.set_script(load("res://scripts/camera_controller.gd"))
	var spring := SpringArm3D.new()
	spring.name = "SpringArm3D"
	spring.transform = Transform3D(Basis(Vector3(0, 1, 0), PI), Vector3.ZERO)  # 与 tscn 一致 180°
	pivot.add_child(spring)
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	spring.add_child(cam)
	for i in range(3):
		await process_frame
	pivot.set("camera_distance", 3.5)
	pivot.set("camera_height", 2.0)
	pivot.set("look_height", 1.8)
	# 等运行时 _process 干扰前立即验证：直接手动调用并立刻读（不 await）
	pivot.call("_editor_3p_update")
	var cam_w: Vector3 = cam.global_position
	var base: Vector3 = owner_node.global_position
	# 期望相机在 SpringArm 局部 -Z 3.5m → 父系 +Z（180°旋转）→ owner 前方 3.5m
	var expect_pos: Vector3 = base + Vector3(0, 2.0, 3.5)
	var pos_err: float = cam_w.distance_to(expect_pos)
	var dir: Vector3 = -cam.global_transform.basis.z
	var target: Vector3 = base + Vector3(0, 1.8, 0)
	var td: Vector3 = (target - cam_w).normalized()
	var ang: float = rad_to_deg(dir.angle_to(td))
	print("相机世界位 = %s 期望 %s 误差=%.4f %s" % [str(cam_w), str(expect_pos), pos_err, "✅" if pos_err < 0.05 else "❌"])
	print("视线对准 look_height 夹角 = %.2f° %s" % [ang, "✅" if ang < 0.5 else "❌"])
	quit(0)
