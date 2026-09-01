extends SceneTree
## 手雷 3P 模型绑定标定探针：
## 1) grenade_world.glb 导入后真实 AABB（算缩放用）
## 2) gaobao 待机合成后右手骨骼全局位置（算挂载 transform 用）

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	# ---- 1) 模型 AABB ----
	var ps2: PackedScene = load("res://resources/models/grenade/grenade_world.glb")
	var mod: Node3D = ps2.instantiate()
	get_root().add_child(mod)
	await process_frame
	var aabb := AABB()
	var have := false
	for mi in mod.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		aabb = aabb.merge(m.get_aabb())
		have = true
		print("  MeshInstance: %s  local_aabb=%s" % [m.name, m.get_aabb()])
	var gf: Transform3D = mod.global_transform
	print("MODEL: 节点=%s 全局变换 origin=%s scale=%s" % [mod.name, gf.origin, gf.basis.get_scale()])
	if have:
		print("MODEL: 合并AABB(本地)=%s size=%s" % [aabb, aabb.size])
		var waabb := AABB(gf * aabb.position, aabb.size * gf.basis.get_scale())
		print("MODEL: 全局AABB(估算) center=%s size=%s" % [waabb.get_center(), waabb.size])
	mod.queue_free()
	# ---- 2) 角色右手骨骼 ----
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
	await process_frame
	await process_frame
	var skel: Skeleton3D = player._weapon_skel
	for bn in ["mixamorig_RightHand", "mixamorig_RightForeArm", "mixamorig_RightArm"]:
		var idx := skel.find_bone(bn)
		if idx >= 0:
			var gp: Transform3D = skel.get_bone_global_pose(idx)
			print("BONE %s: global_pose origin=%s  rot=%s  scale=%s" % [
				bn, gp.origin, gp.basis.get_rotation_quaternion(), gp.basis.get_scale()])
	print("SKEL: global_transform origin=%s" % skel.global_transform.origin)
	quit(0)
