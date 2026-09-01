extends SceneTree
## 验收探针：走完整加载路径（_ready → _apply_calib 读 tres），核对两角色手雷的
## 世界长轴 / 几何中心 / 距骨骼距离，确认 3D 视图中可见且贴合手掌。
func _init():
	for cid in ["feihu", "swat"]:
		await _check(cid)
	print("验收完成")
	quit(0)

func _check(cid: String) -> void:
	var ps = load("res://scenes/grenade_calib.tscn")
	var node = ps.instantiate()
	root.add_child(node)
	node.character_id = cid
	node._rebuild_character()
	for i in range(6):
		await process_frame
	var anchor: Node3D = node.get_node_or_null("HandAnchor")
	var grenade: Node3D = node.get_node_or_null("HandAnchor/Grenade")
	var bone_w: Vector3 = anchor.global_transform.origin
	var mn := Vector3.ZERO
	var mx := Vector3.ZERO
	var first := true
	var longest := 0.0
	for mi in grenade.find_children("*", "MeshInstance3D", true, false):
		var mesh := mi as MeshInstance3D
		if mesh.mesh == null:
			continue
		var box: AABB = mesh.get_aabb()
		var gt: Transform3D = mesh.global_transform
		longest = max(longest, max(box.size.x, max(box.size.y, box.size.z)) * gt.basis.get_scale().x)
		for c in [box.position, box.position + Vector3(box.size.x, 0, 0),
				box.position + Vector3(0, box.size.y, 0), box.position + Vector3(0, 0, box.size.z),
				box.position + Vector3(box.size.x, box.size.y, 0),
				box.position + Vector3(box.size.x, 0, box.size.z),
				box.position + Vector3(0, box.size.y, box.size.z), box.position + box.size]:
			var wc: Vector3 = gt * c
			if first:
				mn = wc
				mx = wc
				first = false
			else:
				mn = mn.min(wc)
				mx = mx.max(wc)
	var center: Vector3 = (mn + mx) * 0.5
	var size: Vector3 = mx - mn
	var ok: bool = longest > 0.05 and longest < 0.60
	print("[%s] 世界长轴=%.4f m  包围盒=%s  中心=%s  距右手骨骼=%.4f m  → %s" % [
		cid, longest, str(size), str(center), center.distance_to(bone_w),
		"✅ 可见" if ok else "❌ 尺寸异常"])
	# 参考：手掌尺度（RightHand骨骼原点→食指掌指关节 = 掌长），判断手雷是否被"握在手里"
	var skel: Skeleton3D = node._skel
	var palm_len: float = -1.0
	var finger: int = skel.find_bone("mixamorig_RightHandIndex1")
	if finger >= 0:
		var p0: Vector3 = (skel.global_transform * skel.get_bone_global_pose(node._bone_idx)).origin
		var p1: Vector3 = (skel.global_transform * skel.get_bone_global_pose(finger)).origin
		palm_len = p0.distance_to(p1)
	print("    参考：掌长=%.4f m，指尖≈%.4f m（手雷中心在 %.4f m 处）" % [
		palm_len, palm_len * 2.2, center.distance_to(bone_w)])
	node.queue_free()
	await process_frame
