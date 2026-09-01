extends SceneTree
## 验证 v2：调用后【立即】读取（不等帧，避免 headless 运行时 _process 干扰）。
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
	# FP：调用后立即读
	pivot.set("editor_fp_preview", true)
	pivot.call("_editor_fp_preview_update")
	var pf: Vector3 = cam.global_position
	var fwd: Vector3 = -cam.global_transform.basis.z
	print("FP 立即: pos=%s 前向=%s %s" % [str(pf), str(fwd),
		"✅眼睛位朝前" if ((pf - Vector3(5, 1.62, 5)).length() < 0.05 and fwd.dot(Vector3(0, 0, 1)) > 0.99) else "❌"])
	# 3P：调用后立即读
	pivot.set("editor_fp_preview", false)
	pivot.call("_editor_fp_preview_update")
	pivot.call("_editor_3p_update")
	var p3: Vector3 = cam.global_position
	print("3P 立即: pos=%s %s" % [str(p3), "✅背后" if (p3 - Vector3(5, 2.85, 2.1)).length() < 0.05 else "❌"])
	quit(0)
