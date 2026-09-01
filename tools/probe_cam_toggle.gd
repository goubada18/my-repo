extends SceneTree
## 验证一键切换按钮：FP ↔ 3P 来回切换，且切换不写回 fp_eye_height。
func _init():
	var owner_node := Node3D.new()
	owner_node.position = Vector3(5, 0, 5)
	root.add_child(owner_node)
	var pivot := Node3D.new()
	pivot.set_script(load("res://scripts/camera_controller.gd"))
	var spring := SpringArm3D.new()
	spring.name = "SpringArm3D"
	spring.transform = Transform3D(Basis(Vector3(0, 1, 0), PI), Vector3.ZERO)
	pivot.add_child(spring)
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	spring.add_child(cam)
	owner_node.add_child(pivot)
	pivot.set_process(false)
	for i in range(3):
		await process_frame
	for k in ["camera_distance", "camera_height", "look_height"]:
		pivot.set(k, {"camera_distance": 2.9, "camera_height": 2.85, "look_height": 2.766}[k])
	pivot.set("fp_eye_height", 1.62)
	pivot.set("fp_offset", Vector3.ZERO)
	# 初始 3P
	pivot.call("_editor_3p_update")
	# 点按钮 → FP
	pivot.call("_toggle_editor_view")
	var pf: Vector3 = cam.global_position
	print("按钮1次(→FP): pos=%s %s" % [str(pf), "✅" if (pf - Vector3(5, 1.62, 5)).length() < 0.05 else "❌"])
	print("  fp_eye_height 未写回 = %.2f %s" % [float(pivot.get("fp_eye_height")), "✅" if absf(float(pivot.get("fp_eye_height")) - 1.62) < 0.01 else "❌"])
	# 再点按钮 → 3P
	pivot.call("_toggle_editor_view")
	var p3: Vector3 = cam.global_position
	print("按钮2次(→3P): pos=%s %s" % [str(p3), "✅" if (p3 - Vector3(5, 2.85, 2.1)).length() < 0.05 else "❌"])
	quit(0)
