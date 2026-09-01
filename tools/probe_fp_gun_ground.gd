extends SceneTree
## Measure: FP gun lowest point vs ground at pitch 0/25/75 deg, standing/crouching.
var _gun_meshes: Array = []

func _mesh_lowest_y() -> float:
	var low: float = INF
	for m in _gun_meshes:
		var mi := m as MeshInstance3D
		var la := mi.get_aabb()
		var gt: Transform3D = mi.global_transform
		for xi in [0, 1]:
			for yi in [0, 1]:
				for zi in [0, 1]:
					var wp := gt * (la.position + Vector3(la.size.x * xi, la.size.y * yi, la.size.z * zi))
					low = minf(low, wp.y)
	return low

func _check(tag: String) -> void:
	var low: float = _mesh_lowest_y()
	if low > 0.01:
		print("%s: gun_lowest_y=%.3f -> OK (above ground)" % [tag, low])
	else:
		print("%s: gun_lowest_y=%.3f -> CLIP %.3f m into ground" % [tag, low, absf(low)])

func _init():
	var ps: PackedScene = load("res://scenes/player.tscn")
	var inst = ps.instantiate()
	root.add_child(inst)
	for i in range(15):
		await process_frame
	var pivot: Node3D = inst.get_node_or_null("CameraPivot")
	if pivot == null:
		printerr("FAIL: no CameraPivot")
		quit(1)
		return
	var cam: Camera3D = pivot.get("camera")
	pivot.call("set_first_person", true, 70.0)
	for i in range(6):
		await process_frame
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		var p := n.get_parent()
		var pscr: String = str(p.get_script().resource_path) if p != null and p.get_script() != null else ""
		if "fp_viewmodel_player.gd" in pscr or (p != null and p.get("vm_scene_path") != null):
			_gun_meshes.append(n)
	if _gun_meshes.is_empty():
		# 模型直接挂到主相机下（setup: p_camera.add_child(_model)，节点名 FPViewModel）
		for n in cam.find_children("*", "MeshInstance3D", true, false):
			_gun_meshes.append(n)
		print("via camera: meshes=%d" % _gun_meshes.size())
	print("gun meshes: %d" % _gun_meshes.size())
	if _gun_meshes.is_empty():
		printerr("FAIL: no gun mesh found")
		quit(1)
		return
	pivot.set("pitch", 0.0)
	await process_frame
	_check("[stand pitch0]")
	pivot.set("pitch", deg_to_rad(25.0))
	await process_frame
	_check("[stand pitch25]")
	pivot.set("pitch", deg_to_rad(75.0))
	await process_frame
	_check("[stand pitch75 min]")
	pivot.set("pitch", 0.0)
	pivot.call("set_crouch", true, 0.3)
	for i in range(30):
		await process_frame
	_check("[crouch pitch0]")
	pivot.set("pitch", deg_to_rad(75.0))
	await process_frame
	_check("[crouch pitch75 min]")
	print("")
	print("cam: fp_eye_height=%.2f stand, fp_eye_height_crouch=%.2f crouch, max_pitch=75deg" % [
		float(pivot.get("fp_eye_height")), float(pivot.get("fp_eye_height_crouch"))])
	quit(0)
