extends SceneTree
## 一次性诊断：逐层打印 grenade_calib 场景的 transform 链，定位尺寸塌缩发生在哪一层。
func _init():
	var ps = load("res://scenes/grenade_calib.tscn")
	var node = ps.instantiate()
	root.add_child(node)
	for i in range(30):
		await process_frame
	var anchor = node.get_node_or_null("HandAnchor")
	var grenade = node.get_node_or_null("HandAnchor/Grenade")
	print("=== 节点链 ===")
	print("root(GrenadeCalib)      scale=%s" % str(node.global_transform.basis.get_scale()))
	print("HandAnchor  global      scale=%s pos=%s" % [
		str(anchor.global_transform.basis.get_scale()), str(anchor.global_transform.origin)])
	print("HandAnchor  LOCAL       scale=%s pos=%s" % [
		str(anchor.transform.basis.get_scale()), str(anchor.transform.origin)])
	print("Grenade     LOCAL       scale=%s pos=%s" % [
		str(grenade.transform.basis.get_scale()), str(grenade.transform.origin)])
	print("Grenade     global      scale=%s pos=%s" % [
		str(grenade.global_transform.basis.get_scale()), str(grenade.global_transform.origin)])
	print("脚本字段 _grenade == 场景节点? %s" % str(node._grenade == grenade))
	print("_grenade.scale = %s" % str(node._grenade.scale))
	print("_grenade.visible = %s   HandAnchor.visible = %s" % [
		str(grenade.visible), str(anchor.visible)])
	print("=== 从 Grenade 往下整棵树 ===")
	_dump(grenade, 1)
	print("=== 网格 ===")
	for mi in grenade.find_children("*", "MeshInstance3D", true, false):
		var mesh := mi as MeshInstance3D
		print("  %s: global_scale=%s  local_aabb.size=%s  visible=%s" % [
			mesh.name, str(mesh.global_transform.basis.get_scale()),
			str(mesh.get_aabb().size), str(mesh.visible)])
		var box: AABB = mesh.get_aabb()
		var mn := Vector3.ZERO
		var mx := Vector3.ZERO
		var first := true
		for c in [box.position, box.position + Vector3(box.size.x, 0, 0),
				box.position + Vector3(0, box.size.y, 0), box.position + Vector3(0, 0, box.size.z),
				box.position + Vector3(box.size.x, box.size.y, 0),
				box.position + Vector3(box.size.x, 0, box.size.z),
				box.position + Vector3(0, box.size.y, box.size.z), box.position + box.size]:
			var wc: Vector3 = mesh.global_transform * c
			if first:
				mn = wc
				mx = wc
				first = false
			else:
				mn = mn.min(wc)
				mx = mx.max(wc)
		var sz: Vector3 = mx - mn
		print("  %s: 世界AABB size=%s  最长轴=%.4f m" % [mesh.name, str(sz), max(sz.x, max(sz.y, sz.z))])
	# 反推：若要把最长轴做到 0.10m，Grenade 的 local_scale 应该是多少
	var cur_longest: float = 0.0
	for mi in grenade.find_children("*", "MeshInstance3D", true, false):
		var mesh := mi as MeshInstance3D
		var b: AABB = mesh.get_aabb()
		cur_longest = max(cur_longest, b.size.length())
	if cur_longest > 0.0:
		var eff: float = grenade.global_transform.basis.get_scale().x
		var need: float = 0.10 / (cur_longest * (eff / grenade.transform.basis.get_scale().x) / grenade.transform.basis.get_scale().x)
		print("=== 反推 ===")
		print("当前 Grenade local_scale=%.4f → 世界最长轴=%.5f m" % [
			grenade.transform.basis.get_scale().x, cur_longest * eff])
		print("若目标 0.10m，local_scale 应为 %.2f（放大 %.1f 倍）" % [
			grenade.transform.basis.get_scale().x * (0.10 / (cur_longest * eff)),
			0.10 / (cur_longest * eff)])
	quit(0)

func _dump(n: Node, depth: int) -> void:
	var ind: String = "  ".repeat(depth)
	var extra: String = ""
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		extra = " mesh=%s skin=%s" % [str(mi.mesh != null), str(mi.skin != null)]
	if n is Node3D:
		var n3 := n as Node3D
		extra += " local_scale=%s global_scale=%s visible=%s" % [
			str(n3.transform.basis.get_scale()),
			str(n3.global_transform.basis.get_scale()), str(n3.visible)]
	print("%s- %s (%s)%s" % [ind, n.name, n.get_class(), extra])
	for c in n.get_children():
		_dump(c, depth + 1)
