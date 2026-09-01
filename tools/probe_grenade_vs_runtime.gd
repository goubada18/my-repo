extends SceneTree
## 关键对比：标定场景的【HandAnchor 挂载】vs 游戏运行时的【BoneAttachment3D 挂载】，
## 用【同一个角色、同一份标定值】分别挂，量手雷世界 AABB 是否一致。
## 若不一致 → 找到"标定好了进游戏不一样"的真凶（挂载语义差异）。
func _init():
	for cid in ["feihu", "swat"]:
		await _check(cid)
	print("对比完成")
	quit(0)

func _check(cid: String) -> void:
	var ps = load("res://scenes/grenade_calib.tscn")
	var node = ps.instantiate()
	root.add_child(node)
	node.character_id = cid
	node._rebuild_character()
	for i in range(8):
		await process_frame

	var skel: Skeleton3D = node._skel
	var grenade: Node3D = node.get_node_or_null("HandAnchor/Grenade")
	if skel == null or grenade == null:
		printerr("PROBE_FAIL: 节点缺失 cid=%s" % cid)
		return
	var bone_idx: int = skel.find_bone("mixamorig_RightHand")

	# --- 方式1：标定场景（HandAnchor 子节点）---
	var ab1: Dictionary = _aabb(grenade)
	print("[%s] 方式1 HandAnchor : 长轴=%.4f m  中心=%s" % [
		cid, ab1["longest"], str(ab1["center"])])

	# --- 方式2：模拟运行时 BoneAttachment3D ---
	var ba := BoneAttachment3D.new()
	ba.name = "TestBA"
	ba.bone_name = "mixamorig_RightHand"
	skel.add_child(ba)
	var calib = load("res://resources/characters/grenade_calib_%s.tres" % cid)
	var sub: Node3D = load("res://resources/models/grenade/grenade_world.glb").instantiate()
	sub.transform = Transform3D(Basis(calib.local_rot).scaled(calib.local_scale), calib.local_pos)
	ba.add_child(sub)
	for i in range(8):
		await process_frame
	var ab2: Dictionary = _aabb(sub)
	print("[%s] 方式2 BoneAttach : 长轴=%.4f m  中心=%s" % [
		cid, ab2["longest"], str(ab2["center"])])

	var d_long: float = absf(ab1["longest"] - ab2["longest"])
	var d_center: float = ab1["center"].distance_to(ab2["center"])
	# 动画播放中两种挂载的更新时机差一帧 → 中心允许 1cm 误差（<0.5%）
	var ok: bool = d_long < 0.002 and d_center < 0.01
	print("    → 长轴差=%.5f m  中心差=%.5f m   %s" % [
		d_long, d_center,
		"✅ 一致（标定场景=游戏运行时）" if ok else "❌ 不一致（这就是进游戏不一样的原因）"])
	ba.queue_free()
	node.queue_free()
	await process_frame

func _aabb(grenade: Node3D) -> Dictionary:
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
	return {"center": (mn + mx) * 0.5, "longest": longest}
