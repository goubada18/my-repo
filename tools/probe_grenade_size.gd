extends SceneTree
## 一次性诊断：grenade_calib 场景中手雷模型的实际世界尺寸与位置。
func _init():
	var ps = load("res://scenes/grenade_calib.tscn")
	var node = ps.instantiate()
	root.add_child(node)
	for i in range(30):
		await process_frame
	var anchor = node.get_node_or_null("HandAnchor")
	var grenade = node.get_node_or_null("HandAnchor/Grenade")
	print("skel=%s bone_idx=%d" % [str(node._skel != null), node._bone_idx])
	if anchor == null or grenade == null:
		printerr("PROBE_FAIL: 节点缺失")
		quit(1)
		return
	var a_scale: Vector3 = anchor.global_transform.basis.get_scale()
	print("HandAnchor 世界scale = %s" % str(a_scale))
	# 计算手雷所有 MeshInstance3D 的世界 AABB
	var aabb_min: Vector3
	var aabb_max: Vector3
	var first := true
	var count := 0
	for mi in grenade.find_children("*", "MeshInstance3D", true, false):
		var mesh := mi as MeshInstance3D
		if mesh.mesh == null:
			continue
		count += 1
		var wtl: Transform3D = grenade.global_transform * mesh.get_global_transform().inverse() * mesh.global_transform
		var box: AABB = mesh.get_aabb()
		var corners := [
			box.position,
			box.position + Vector3(box.size.x, 0, 0),
			box.position + Vector3(0, box.size.y, 0),
			box.position + Vector3(0, 0, box.size.z),
			box.position + Vector3(box.size.x, box.size.y, 0),
			box.position + Vector3(box.size.x, 0, box.size.z),
			box.position + Vector3(0, box.size.y, box.size.z),
			box.position + box.size,
		]
		for c in corners:
			var wc: Vector3 = mesh.global_transform * c
			if first:
				aabb_min = wc
				aabb_max = wc
				first = false
			else:
				aabb_min = aabb_min.min(wc)
				aabb_max = aabb_max.max(wc)
	print("网格数=%d 世界AABB: min=%s max=%s" % [count, str(aabb_min), str(aabb_max)])
	var size: Vector3 = aabb_max - aabb_min
	print("手雷世界尺寸 = %s 米（期望≈0.1m；若≈1e-6 则确认微观级过小）" % str(size))
	# 右手骨骼世界位置（对照手雷位置是否在手边）
	var skel: Skeleton3D = node._skel
	var bone_w: Vector3 = (skel.global_transform * skel.get_bone_global_pose(node._bone_idx)).origin
	print("右手骨骼世界位=%s 手雷中心=%s 距离=%.4fm" % [str(bone_w), str((aabb_min + aabb_max) / 2.0), (aabb_min + aabb_max / 2.0).distance_to(bone_w)])
	quit(0)
