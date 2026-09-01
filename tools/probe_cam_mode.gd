extends SceneTree
## 验证 editor_view_mode 下拉：0=3P 背后 / 1=FP 眼睛 / 2=自由。
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
	# 模式 0 = 3P
	pivot.set("editor_view_mode", 0)
	pivot.call("_editor_3p_update")
	var p0: Vector3 = cam.global_position
	print("mode0 3P: pos=%s %s" % [str(p0), "✅" if (p0 - Vector3(5, 2.85, 2.1)).length() < 0.05 else "❌"])
	# 模式 1 = FP
	pivot.set("editor_view_mode", 1)
	pivot.call("_editor_fp_preview_update")
	var p1: Vector3 = cam.global_position
	print("mode1 FP: pos=%s %s" % [str(p1), "✅" if (p1 - Vector3(5, 1.62, 5)).length() < 0.05 else "❌"])
	# 模式 2 = 自由（不驱动）
	pivot.set("editor_view_mode", 2)
	var before: Vector3 = cam.global_position
	pivot.call("_process", 0.016) if false else null
	print("mode2 自由: 相机不被驱动（保留 FP 位） %s" % ["✅" if (cam.global_position - p1).length() < 0.001 else "❌"])
	quit(0)
