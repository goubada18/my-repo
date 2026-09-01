extends SceneTree
## 对照：同一节点结构下，"运行时 SpringArm 推 + look_at" vs "编辑器 _editor_3p_update"，
## 相机最终 global_transform 是否一致。
func _init():
	# ---- 通用结构：Owner(Player) → Pivot(camera_controller) → SpringArm(R_y180) → Camera ----
	var owner_node := Node3D.new()
	owner_node.name = "Player"
	owner_node.position = Vector3(5, 0, 5)
	root.add_child(owner_node)

	# ===== A. 运行时模拟 =====
	var pivotA := Node3D.new()
	pivotA.name = "CameraPivot"
	owner_node.add_child(pivotA)
	pivotA.set_script(load("res://scripts/camera_controller.gd"))
	var springA := SpringArm3D.new()
	springA.name = "SpringArm3D"
	springA.transform = Transform3D(Basis(Vector3(0, 1, 0), PI), Vector3.ZERO)
	pivotA.add_child(springA)
	var camA := Camera3D.new()
	camA.name = "Camera3D"
	springA.add_child(camA)
	for i in range(3):
		await process_frame   # @onready 绑定
	# 运行时：_ready 设 spring_length；SpringArm 推相机；look_at 角色
	pivotA.set("camera_distance", 2.9)
	pivotA.set("camera_height", 2.85)
	pivotA.set("look_height", 2.766)
	pivotA.call("_ready")
	springA.spring_length = 2.9
	camA.position = Vector3(0, 0, -2.9)   # 模拟 SpringArm 推（局部）
	camA.look_at(owner_node.global_position + Vector3(0, 2.766, 0), Vector3.UP)
	await process_frame
	var rt_pos: Vector3 = camA.global_position
	var rt_rot: Basis = camA.global_transform.basis

	# ===== B. 编辑器复刻 =====
	var pivotB := Node3D.new()
	pivotB.name = "CameraPivot"
	owner_node.add_child(pivotB)
	pivotB.set_script(load("res://scripts/camera_controller.gd"))
	var springB := SpringArm3D.new()
	springB.name = "SpringArm3D"
	springB.transform = Transform3D(Basis(Vector3(0, 1, 0), PI), Vector3.ZERO)
	pivotB.add_child(springB)
	var camB := Camera3D.new()
	camB.name = "Camera3D"
	springB.add_child(camB)
	for i in range(3):
		await process_frame
	pivotB.set("camera_distance", 2.9)
	pivotB.set("camera_height", 2.85)
	pivotB.set("look_height", 2.766)
	pivotB.call("_editor_3p_update")
	await process_frame
	var ed_pos: Vector3 = camB.global_position
	var ed_rot: Basis = camB.global_transform.basis

	print("运行时: pos=%s  前向=%s" % [str(rt_pos), str(-rt_rot.z)])
	print("编辑器: pos=%s  前向=%s" % [str(ed_pos), str(-ed_rot.z)])
	var d_pos: float = rt_pos.distance_to(ed_pos)
	var d_rot: float = rad_to_deg(rt_rot.get_rotation_quaternion().angle_to(ed_rot.get_rotation_quaternion()))
	print("位置差=%.4f  朝向差=%.2f°  → %s" % [d_pos, d_rot,
		"✅ 一致" if (d_pos < 0.02 and d_rot < 0.5) else "❌ 不一致（真凶）"])
	quit(0)
