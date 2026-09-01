extends SceneTree
## 诊断/回归：验证标定场景改造后的交互行为
##   A. 打开场景 → 标定值从 tres 正确回填
##   B. 改 Inspector 字段 grenade_scale → 节点同步、世界尺寸线性变化
##   C. 点「重建角色预览」→ 用户调过的值【不应】被覆盖
##   D. 切换 character_id → 应换用该角色标定值
##   E. 勾 freeze_anchor → 挂点应静止（拖拽基准稳定）
func _init():
	var ps = load("res://scenes/grenade_calib.tscn")
	var node = ps.instantiate()
	root.add_child(node)
	for i in range(6):
		await process_frame
	var grenade: Node3D = node.get_node_or_null("HandAnchor/Grenade")

	print("=== A. 打开场景（feihu）===")
	print("  grenade_scale=%.2f  节点scale=%.2f  世界长轴=%.4f m" % [
		node.grenade_scale, grenade.scale.x, _longest(grenade)])

	print("=== B. 改 Inspector 字段 grenade_scale = 3000 ===")
	node.grenade_scale = 3000.0
	await process_frame
	await process_frame
	print("  节点scale=%.2f  世界长轴=%.4f m  → %s" % [
		grenade.scale.x, _longest(grenade),
		"✅ 同步生效" if absf(grenade.scale.x - 3000.0) < 0.01 else "❌ 未同步"])

	print("=== C. 点「重建角色预览」（_rebuild_character）===")
	node._rebuild_character()
	await process_frame
	await process_frame
	print("  重建后 node.grenade_scale=%.2f  节点scale=%.2f  → %s" % [
		node.grenade_scale, grenade.scale.x,
		"✅ 保住用户的值" if absf(node.grenade_scale - 3000.0) < 0.01 else "❌ 被标定资源覆盖"])

	print("=== D. 切到 swat（应换用 swat 标定值 80）===")
	node.character_id = "swat"
	await process_frame
	await process_frame
	print("  grenade_scale=%.2f  世界长轴=%.4f m  → %s" % [
		node.grenade_scale, _longest(grenade),
		"✅ 已换标定" if absf(node.grenade_scale - 80.0) < 0.5 else "❌ 未切换"])
	print("  （feihu 4245.27 与 swat 80 数值差 53 倍，但世界长轴应当一致）")

	print("=== E. freeze_anchor 冻结挂点 ===")
	var anchor: Node3D = node.get_node_or_null("HandAnchor")
	var p0: Vector3 = anchor.global_transform.origin
	var q0: Quaternion = anchor.global_transform.basis.get_rotation_quaternion()
	for i in range(20):
		await process_frame
	var drift_unfrozen: float = p0.distance_to(anchor.global_transform.origin) + absf(q0.angle_to(anchor.global_transform.basis.get_rotation_quaternion()))
	node._toggle_freeze()   # 冻结（按钮等价）
	await process_frame
	await process_frame   # 等状态稳定后再取基准
	p0 = anchor.global_transform.origin
	q0 = anchor.global_transform.basis.get_rotation_quaternion()
	var trace := "  冻结后逐帧位移: "
	for i in range(20):
		await process_frame
		if i < 6:
			trace += "%.7f  " % p0.distance_to(anchor.global_transform.origin)
	print(trace)
	var drift_frozen: float = p0.distance_to(anchor.global_transform.origin) + absf(q0.angle_to(anchor.global_transform.basis.get_rotation_quaternion()))
	print("  未冻结 20 帧漂移=%.6f   冻结后 20 帧漂移=%.6f  → %s" % [
		drift_unfrozen, drift_frozen,
		"✅ 冻结生效" if drift_frozen < 1e-9 else "❌ 仍在动"])
	print("完成")
	quit(0)

func _longest(grenade: Node3D) -> float:
	var longest := 0.0
	for mi in grenade.find_children("*", "MeshInstance3D", true, false):
		var mesh := mi as MeshInstance3D
		if mesh.mesh == null:
			continue
		var box: AABB = mesh.get_aabb()
		var sc: float = mesh.global_transform.basis.get_scale().x
		longest = max(longest, max(box.size.x, max(box.size.y, box.size.z)) * sc)
	return longest
