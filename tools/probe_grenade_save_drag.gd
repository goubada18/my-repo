extends SceneTree
## 回归：模拟"用户在 3D 视口拖动 Grenade 节点 → 点保存"完整链路。
## 关键断言：保存必须写【节点当前值】（旧 bug：写的是字段旧值，拖动白拖）。
func _init():
	var ps = load("res://scenes/grenade_calib.tscn")
	var node = ps.instantiate()
	root.add_child(node)
	for i in range(6):
		await process_frame
	var grenade: Node3D = node.get_node_or_null("HandAnchor/Grenade")
	var path := "res://resources/characters/grenade_calib_feihu.tres"

	# 1) 模拟拖动：把节点挪到一个测试位置（与字段旧值明显不同）
	grenade.position = Vector3(1234.0, 5678.0, -9012.0)
	grenade.scale = Vector3.ONE * 7777.0
	print("字段旧值: grenade_pos=%s grenade_scale=%.1f" % [str(node.grenade_pos), node.grenade_scale])
	print("节点新值: pos=%s scale=%s" % [str(grenade.position), str(grenade.scale)])

	# 2) 模拟用户点「保存当前手雷位 → 标定资源」
	node._save_calib()

	# 3) 重新读 tres，断言 = 节点值（不是字段旧值）
	var r = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
	var ok_pos: bool = r.local_pos.is_equal_approx(grenade.position)
	var ok_scale: bool = absf(r.local_scale.x - 7777.0) < 0.1
	print("tres 保存值: pos=%s scale=%s" % [str(r.local_pos), str(r.local_scale)])
	print("断言: pos=%s scale=%s  → %s" % [
		"✅=节点" if ok_pos else "❌=旧字段", "✅=节点" if ok_scale else "❌=旧字段",
		"✅ 保存以节点为准（拖动生效）" if (ok_pos and ok_scale) else "❌ 仍写旧字段（拖动白拖）"])

	# 4) 恢复正确标定值（避免测试污染）
	grenade.position = Vector3(-1079.1437, 2308.8135, -796.2861)
	grenade.quaternion = Quaternion(0.7071, 0, 0, 0.7071)
	grenade.scale = Vector3.ONE * 4245.2682
	node._save_calib()
	var r2 = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
	print("已恢复: scale=%.2f pos=%s" % [r2.local_scale.x, str(r2.local_pos)])
	print("完成")
	quit(0)
