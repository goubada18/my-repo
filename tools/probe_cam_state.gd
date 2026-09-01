extends SceneTree
## 验证简化后的编辑器机位（第十三轮修复 v2）：
## 1. FP 每帧摆位：改 fp_eye_height/fp_offset 数值即时可见（所见即所得）
## 2. 无写回污染：反复切换模式/拖相机，参数永不被改
## 3. 3P/FP/自由 来回切换全部正确
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
	var fails: int = 0
	# ---- 1. 3P ----
	pivot.set("editor_view_mode", 0)
	pivot.call("_editor_view_update")
	var ok: bool = (cam.global_position - Vector3(5, 2.85, 2.1)).length() < 0.05
	print("[1] 3P: pos=%s %s" % [str(cam.global_position), "✅" if ok else "❌"])
	if not ok: fails += 1
	# ---- 2. FP 摆位 ----
	pivot.set("editor_view_mode", 1)
	pivot.call("_editor_view_update")
	ok = (cam.global_position - Vector3(5, 1.62, 5)).length() < 0.05
	print("[2] FP: pos=%s %s" % [str(cam.global_position), "✅" if ok else "❌"])
	if not ok: fails += 1
	# ---- 3. 改 fp_eye_height → 即时可见 ----
	pivot.set("fp_eye_height", 1.80)
	pivot.set("fp_offset", Vector3(0.2, 0, -0.3))
	pivot.call("_editor_view_update")
	ok = (cam.global_position - Vector3(5.2, 1.80, 4.7)).length() < 0.05
	print("[3] 改数值即时可见: pos=%s %s" % [str(cam.global_position), "✅" if ok else "❌"])
	if not ok: fails += 1
	# ---- 4. FP 下强行拖相机（模拟旧拖拽）→ 参数不被污染 ----
	cam.global_position = Vector3(9, 9, 9)
	pivot.call("_editor_view_update")   # 每帧摆位：拉回眼睛位
	var eh: float = float(pivot.get("fp_eye_height"))
	var off: Vector3 = pivot.get("fp_offset")
	var ok4a: bool = absf(eh - 1.80) < 0.01 and off.distance_to(Vector3(0.2, 0, -0.3)) < 0.01
	var ok4b: bool = (cam.global_position - Vector3(5.2, 1.80, 4.7)).length() < 0.05
	ok = ok4a and ok4b
	print("[4] 拖不走+参数不污染: eye=%.2f offset=%s %s" % [eh, str(off), "✅" if ok else "❌"])
	if not ok: fails += 1
	# ---- 5. 自由观察拖相机 ----
	pivot.set("editor_view_mode", 2)
	pivot.call("_editor_view_update")
	cam.global_position = Vector3(9, 9, 9)
	pivot.call("_editor_view_update")   # 自由模式不动相机
	ok = (cam.global_position - Vector3(9, 9, 9)).length() < 0.001
	print("[5] 自由观察不驱动: pos=%s %s" % [str(cam.global_position), "✅" if ok else "❌"])
	if not ok: fails += 1
	# ---- 6. 自由→FP 重新摆位 ----
	pivot.set("editor_view_mode", 1)
	pivot.call("_editor_view_update")
	ok = (cam.global_position - Vector3(5.2, 1.80, 4.7)).length() < 0.05
	print("[6] 自由→FP 摆位: pos=%s %s" % [str(cam.global_position), "✅" if ok else "❌"])
	if not ok: fails += 1
	# ---- 7. 自由→3P ----
	pivot.set("editor_view_mode", 2)
	pivot.call("_editor_view_update")
	cam.global_position = Vector3(9, 9, 9)
	pivot.set("editor_view_mode", 0)
	pivot.call("_editor_view_update")
	ok = (cam.global_position - Vector3(5, 2.85, 2.1)).length() < 0.05
	print("[7] 自由→3P: pos=%s %s" % [str(cam.global_position), "✅" if ok else "❌"])
	if not ok: fails += 1
	# ---- 8. 参数全程未被污染（保持 1.80 / (0.2,0,-0.3)）----
	ok = absf(float(pivot.get("fp_eye_height")) - 1.80) < 0.01 and (pivot.get("fp_offset") as Vector3).distance_to(Vector3(0.2, 0, -0.3)) < 0.01
	print("[8] 参数全程未污染 %s" % ("✅" if ok else "❌"))
	if not ok: fails += 1
	print("=== 失败 %d → %s ===" % [fails, "全部通过 ✅" if fails == 0 else "存在失败 ❌"])
	quit(0 if fails == 0 else 1)
