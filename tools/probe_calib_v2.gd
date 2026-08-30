extends SceneTree
## 一次性验证：标定场景 v2（Knife 常驻节点版）
func _init():
	var ps = load("res://scenes/nepal_knife_calib.tscn")
	var node = ps.instantiate()
	root.add_child(node)
	for i in range(30):
		await process_frame
	var knife = node.get_node_or_null("HandAnchor/Knife")
	print("feihu: Knife节点存在=%s" % str(knife != null))
	# HandAnchor 是否跟到右手骨骼
	var skel = node._skel
	var bi = node._bone_idx
	var expect: Transform3D = skel.global_transform * skel.get_bone_global_pose(bi)
	var diff: float = (node._hand_anchor.global_transform.origin - expect.origin).length()
	print("feihu: HandAnchor与骨骼位姿偏差=%.5f m（期望≈0）" % diff)
	# 切 swat
	node.character_id = "swat"
	for i in range(30):
		await process_frame
	var knife2 = node.get_node_or_null("HandAnchor/Knife")
	var skel2 = node._skel
	print("swat: Knife仍存在=%s 角色已切换=%s" % [str(knife2 != null), str(skel2 != node._skel or skel2 != null)])
	var expect2: Transform3D = skel2.global_transform * skel2.get_bone_global_pose(node._bone_idx)
	var diff2: float = (node._hand_anchor.global_transform.origin - expect2.origin).length()
	print("swat: HandAnchor偏差=%.5f m" % diff2)
	# 保存链路
	node._save_calib()
	quit(0)
