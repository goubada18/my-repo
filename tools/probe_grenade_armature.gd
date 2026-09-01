extends SceneTree
## 验证：标定场景加载的角色（character.tscn / character_preview.tscn）的 Armature 缩放
## 与游戏运行时角色是否一致。若不一致 → 标定数值在游戏里必然对不上。
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
	var anchor: Node3D = node.get_node_or_null("HandAnchor")
	var g: Node3D = node.get_node_or_null("HandAnchor/Grenade")
	print("[%s] 标定场景角色: %s" % [cid, node._char_inst.scene_file_path if node._char_inst != null else "null"])
	if skel != null:
		print("    skel.global scale   = %.8f" % skel.global_transform.basis.get_scale().x)
	print("    HandAnchor scale     = %.8f" % anchor.global_transform.basis.get_scale().x)
	print("    grenade_scale 字段   = %.4f  节点scale=%.4f" % [node.grenade_scale, g.scale.x])
	# 手雷世界长轴
	var longest := 0.0
	for mi in g.find_children("*", "MeshInstance3D", true, false):
		var mesh := mi as MeshInstance3D
		if mesh.mesh == null:
			continue
		var b: AABB = mesh.get_aabb()
		longest = max(longest, max(b.size.x, max(b.size.y, b.size.z)) * mesh.global_transform.basis.get_scale().x)
	print("    手雷世界长轴 = %.4f m" % longest)
	node.queue_free()
	await process_frame
