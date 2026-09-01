extends SceneTree
## 决定性验证：手动把 HandAnchor 设为正确值(0.0138)后，等 3 帧，
## 若 _process 把它改回 0.00026 → _process 用的骨架是旧的/feihu 的。
## 若保持 0.0138 → _process 根本没更新 HandAnchor（freeze 或 _skel 为 null）。
func _init():
	var ps = load("res://scenes/grenade_calib.tscn")
	var node = ps.instantiate()
	root.add_child(node)
	for i in range(4):
		await process_frame
	node.character_id = "swat"
	for i in range(6):
		await process_frame
	var skel: Skeleton3D = node._skel
	var anchor: Node3D = node.get_node_or_null("HandAnchor")
	var idx: int = skel.find_bone("mixamorig_RightHand")
	print("当前: _skel scale=%.8f  _bone_idx=%d  freeze_anchor=%s" % [
		skel.global_transform.basis.get_scale().x, node._bone_idx, str(node.freeze_anchor)])
	anchor.global_transform = skel.global_transform * skel.get_bone_global_pose(idx)
	print("手动赋值后立即: HandAnchor scale=%.8f" % anchor.global_transform.basis.get_scale().x)
	for i in range(4):
		await process_frame
		print("  第%d帧后: HandAnchor scale=%.8f" % [i + 1, anchor.global_transform.basis.get_scale().x])
	print("完成")
	quit(0)
