extends SceneTree
## 定位 swat 标定场景 HandAnchor scale 异常（0.00026 而非 0.0138）的来源：
## 量骨骼 rest / pose / bone_global_pose 的 scale，并对比 BoneAttachment3D 的 transform。
func _init():
	for cid in ["feihu", "swat"]:
		await _check(cid)
	print("完成")
	quit(0)

func _check(cid: String) -> void:
	var ps = load("res://scenes/grenade_calib.tscn")
	var node = ps.instantiate()
	root.add_child(node)
	for i in range(4):
		await process_frame
	node.character_id = cid
	for i in range(8):
		await process_frame
	var skel: Skeleton3D = node._skel
	var idx: int = skel.find_bone("mixamorig_RightHand")
	var rest_sc := skel.get_bone_rest(idx).basis.get_scale()
	var pose_sc := skel.get_bone_pose(idx).basis.get_scale()
	var gpose: Transform3D = skel.get_bone_global_pose(idx)
	var gpose_sc: Vector3 = gpose.basis.get_scale()
	print("[%s] skel.global=%f  bone[%d] rest_scale=%s pose_scale=%s global_pose_scale=%s" % [
		cid, skel.global_transform.basis.get_scale().x, idx,
		str(rest_sc), str(pose_sc), str(gpose_sc)])
	# 对比：BoneAttachment3D 的 transform（模拟运行时）
	var ba := BoneAttachment3D.new()
	ba.bone_name = "mixamorig_RightHand"
	skel.add_child(ba)
	await process_frame
	await process_frame
	print("    BoneAttachment3D.transform scale = %s" % str(ba.transform.basis.get_scale()))
	print("    BoneAttachment3D.global  scale = %s" % str(ba.global_transform.basis.get_scale()))
	ba.queue_free()
	node.queue_free()
	await process_frame
