extends SceneTree
## 复测 v3：先绑脚本再进树（@onready 正常），对照运行时 vs 编辑器复刻。
func _make_pivot(owner_node: Node3D) -> Node3D:
	var pivot := Node3D.new()
	pivot.set_script(load("res://scripts/camera_controller.gd"))   # 先绑脚本
	var spring := SpringArm3D.new()
	spring.name = "SpringArm3D"
	spring.transform = Transform3D(Basis(Vector3(0, 1, 0), PI), Vector3.ZERO)
	pivot.add_child(spring)
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	spring.add_child(cam)
	owner_node.add_child(pivot)   # 进树触发 _ready → @onready 绑定
	return pivot

func _init():
	var owner_node := Node3D.new()
	owner_node.position = Vector3(5, 0, 5)
	root.add_child(owner_node)
	var pivotA := _make_pivot(owner_node)
	var pivotB := _make_pivot(owner_node)
	pivotA.set_process(false)
	pivotB.set_process(false)
	for i in range(3):
		await process_frame
	for p in [pivotA, pivotB]:
		p.set("camera_distance", 2.9)
		p.set("camera_height", 2.85)
		p.set("look_height", 2.766)
	# 运行时：_ready + SpringArm 推 + look_at
	pivotA.call("_ready")
	var springA: SpringArm3D = pivotA.get("spring_arm")
	var camA: Camera3D = pivotA.get("camera")
	springA.spring_length = 2.9
	camA.position = Vector3(0, 0, -2.9)
	camA.look_at(owner_node.global_position + Vector3(0, 2.766, 0), Vector3.UP)
	# 编辑器复刻
	pivotB.call("_editor_3p_update")
	await process_frame
	var camB: Camera3D = pivotB.get("camera")
	print("运行时: pos=%s 编辑器: pos=%s" % [str(camA.global_position), str(camB.global_position)])
	var d_pos: float = camA.global_position.distance_to(camB.global_position)
	var d_rot: float = rad_to_deg(camA.global_transform.basis.get_rotation_quaternion().angle_to(camB.global_transform.basis.get_rotation_quaternion()))
	print("位置差=%.4f 朝向差=%.2f° → %s" % [d_pos, d_rot,
		"✅ 与运行时一致" if (d_pos < 0.02 and d_rot < 0.5) else "❌ 仍不一致"])
	quit(0)
