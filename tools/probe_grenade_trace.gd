extends SceneTree
## 逐帧追踪：swat 下标定场景 HandAnchor 的 scale 到底由什么决定。
func _init():
	var ps = load("res://scenes/grenade_calib.tscn")
	var node = ps.instantiate()
	root.add_child(node)
	for i in range(4):
		await process_frame
	node.character_id = "swat"
	for i in range(10):
		await process_frame
		var skel: Skeleton3D = node._skel
		var anchor: Node3D = node.get_node_or_null("HandAnchor")
		var sc: float = anchor.global_transform.basis.get_scale().x
		var sk: float = skel.global_transform.basis.get_scale().x
		var bp: float = skel.get_bone_global_pose(skel.find_bone("mixamorig_RightHand")).basis.get_scale().x
		print("帧%d: HandAnchor=%.8f  skel=%.8f  bone_global_pose=%.8f  (skel*bone=%.8f)" % [
			i, sc, sk, bp, sk * bp])
	# 手动模拟 _process 的一行逻辑
	var skel2: Skeleton3D = node._skel
	var anchor2: Node3D = node.get_node_or_null("HandAnchor")
	var idx: int = skel2.find_bone("mixamorig_RightHand")
	var before: Vector3 = anchor2.global_transform.basis.get_scale()
	anchor2.global_transform = skel2.global_transform * skel2.get_bone_global_pose(idx)
	var after: Vector3 = anchor2.global_transform.basis.get_scale()
	print("手动赋值: before=%s after=%s" % [str(before), str(after)])
	print("完成")
	quit(0)
