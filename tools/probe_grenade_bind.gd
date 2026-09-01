extends SceneTree
## 验证手雷 3P 模型绑定：切 gaobao → 等挂载 → 检查模型挂在右手骨骼下、位置/尺寸合理、skip_follow。

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var ps := load("res://scenes/main_multichar.tscn") as PackedScene
	var scene = ps.instantiate()
	get_root().add_child(scene)
	await process_frame
	await process_frame
	var player = scene.get_node_or_null("Player")
	if player == null:
		for c in scene.get_children():
			if c is CharacterBody3D:
				player = c
				break
	await process_frame
	player._switch_to_weapon(player._weapon_system.select_by_id("gaobao"))
	# 等挂载异步完成（2帧 + 缓冲）
	for i in range(10):
		await process_frame
	var skel: Skeleton3D = player._weapon_skel
	var ok := true
	if player._grenade_model == null or not is_instance_valid(player._grenade_model):
		print("FAIL: _grenade_model 未挂载")
		ok = false
	else:
		var g: Node3D = player._grenade_model
		var parent := g.get_parent()
		print("挂载: parent=%s (%s)  child=%s" % [parent.name if parent else "null",
			parent.get_class() if parent else "?", g.name])
		# 手雷全局位置 vs 右手骨骼
		var rhi := skel.find_bone("mixamorig_RightHand")
		var rh_g: Vector3 = skel.get_bone_global_pose(rhi).origin
		var g_g: Vector3 = g.global_position
		print("右手骨骼全局: (%6.2f, %6.2f, %6.2f)" % [rh_g.x, rh_g.y, rh_g.z])
		print("手雷全局:     (%6.2f, %6.2f, %6.2f)" % [g_g.x, g_g.y, g_g.z])
		var dist: float = rh_g.distance_to(g_g)
		print("手雷↔右手距离: %.3f m (合理 <0.3)" % dist)
		if dist > 0.3:
			print("WARN: 距离偏大，标定位置可能不对")
		# 尺寸：世界 AABB（本地 AABB × sub.transform，含 L 缩放）
		var aabb := AABB()
		for mi in g.find_children("*", "MeshInstance3D", true, false):
			aabb = aabb.merge((mi as MeshInstance3D).get_aabb())
		var gtf: Transform3D = g.global_transform
		var waabb := AABB(gtf * aabb.position, aabb.size * gtf.basis.get_scale())
		print("手雷本地AABB size=%s  →  世界AABB size=%s (期望长轴≈0.10-0.14)" % [
			Vector3(aabb.size.x, aabb.size.y, aabb.size.z),
			Vector3(waabb.size.x, waabb.size.y, waabb.size.z)])
	# skip_follow
	print("skip_follow=%s (期望 true)" % str(player._weapon_rig.skip_follow if player._weapon_rig else "-"))
	# 换回 AK 验证释放
	player._switch_to_weapon(player._weapon_system.select_by_id("ak47"))
	await process_frame
	await process_frame
	if player._grenade_attach != null and is_instance_valid(player._grenade_attach):
		print("FAIL: 切回 AK 后 grenade_attach 未释放")
		ok = false
	else:
		print("切回 AK: grenade_attach 已释放 OK")
	print("RESULT: %s" % ("PASS" if ok else "FAIL"))
	quit(0)
