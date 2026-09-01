extends SceneTree
## 手雷标定求解器：根据【目标世界长轴】与【掌心偏移】反算 Grenade 的 local_scale / local_pos。
##
## 背景：grenade_world.glb 的 MeshInstance3D 节点自带 0.0254 缩放（Blender 导出时
## Armature=0.0254 残留），旧标定值漏算这一层 → 手雷世界尺寸仅 2.9mm，3D 视图中不可见。
## 本探针不写文件，只打印应填入 grenade_calib_<角色>.tres 的数值。
## 目标世界长轴（米）。0.10 = 真实手雷尺寸；0.3225 = 与用户调好的 swat 视觉一致
## （swat local_scale 80 → 11.5032 × 0.0254 × 80 × 0.013795 ≈ 0.3225m）
const TARGET_LEN := 0.3225
const PALM_LOCAL_M := Vector3(0.0, -0.05, 0.07)  ## 掌心偏移（骨骼局部系，米）
const ROT := Quaternion(0.7071, 0.0, 0.0, 0.7071)  ## 绕 X +90°

func _init():
	for cid in ["feihu", "swat"]:
		await _solve(cid)
	quit(0)

func _solve(cid: String) -> void:
	print("================ 角色 %s ================" % cid)
	var ps = load("res://scenes/grenade_calib.tscn")
	var node = ps.instantiate()
	root.add_child(node)
	node.character_id = cid
	node._rebuild_character()
	for i in range(6):
		await process_frame
	var anchor: Node3D = node.get_node_or_null("HandAnchor")
	var grenade: Node3D = node.get_node_or_null("HandAnchor/Grenade")
	var skel: Skeleton3D = node._skel
	if anchor == null or grenade == null or skel == null:
		printerr("PROBE_FAIL: 节点缺失 cid=%s" % cid)
		return
	var a_basis: Basis = anchor.global_transform.basis
	var a_scale: float = a_basis.get_scale().x
	var bone_w: Vector3 = anchor.global_transform.origin
	print("HandAnchor 世界scale = %.8f   骨骼世界位 = %s" % [a_scale, str(bone_w)])

	# --- 第 1 轮：以 scale=1、pos=0 起测，量出"单位 scale"下的世界长轴 ---
	grenade.quaternion = ROT
	grenade.scale = Vector3.ONE
	grenade.position = Vector3.ZERO
	await process_frame
	await process_frame
	var m1: Dictionary = _measure(grenade)
	var len1: float = m1["longest"]
	if len1 <= 0.0:
		printerr("PROBE_FAIL: 量不到网格")
		return
	var s_need: float = TARGET_LEN / len1
	print("scale=1 时世界长轴 = %.6f m  →  目标 %.2f m 需 local_scale = %.2f" % [
		len1, TARGET_LEN, s_need])

	# --- 第 2 轮：套用求得的 scale，量几何中心，反解 position ---
	grenade.scale = Vector3.ONE * s_need
	grenade.position = Vector3.ZERO
	await process_frame
	await process_frame
	var m2: Dictionary = _measure(grenade)
	var center_w: Vector3 = m2["center"]
	print("scale=%.2f 时：世界长轴 = %.4f m   几何中心世界位 = %s" % [
		s_need, m2["longest"], str(center_w)])

	# 目标：几何中心 = 骨骼位 + 骨骼局部系的掌心偏移
	var palm_w: Vector3 = Basis(a_basis.get_rotation_quaternion()) * PALM_LOCAL_M
	var target_w: Vector3 = bone_w + palm_w
	var delta_w: Vector3 = target_w - center_w
	var p_need: Vector3 = a_basis.inverse() * delta_w
	print("掌心偏移(世界) = %s   目标中心 = %s" % [str(palm_w), str(target_w)])
	print(">>> local_scale = %.4f" % s_need)
	print(">>> local_pos   = (%.4f, %.4f, %.4f)" % [p_need.x, p_need.y, p_need.z])

	# --- 第 3 轮：套用完整解，复核 ---
	grenade.scale = Vector3.ONE * s_need
	grenade.position = p_need
	await process_frame
	await process_frame
	var m3: Dictionary = _measure(grenade)
	print("复核：世界长轴 = %.4f m   中心 = %s   距骨骼 = %.4f m" % [
		m3["longest"], str(m3["center"]), m3["center"].distance_to(bone_w)])
	node.queue_free()
	await process_frame

## 测量手雷所有 MeshInstance3D 的世界 AABB 与几何中心。
func _measure(grenade: Node3D) -> Dictionary:
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
		var sc: float = gt.basis.get_scale().x
		# 长轴（不是对角线）：手雷最长一边，按它对齐真实尺寸 10cm
		longest = max(longest, max(box.size.x, max(box.size.y, box.size.z)) * sc)
		for c in _corners(box):
			var wc: Vector3 = gt * c
			if first:
				mn = wc
				mx = wc
				first = false
			else:
				mn = mn.min(wc)
				mx = mx.max(wc)
	return {"min": mn, "max": mx, "center": (mn + mx) * 0.5,
		"longest": longest}

func _corners(b: AABB) -> Array:
	return [
		b.position,
		b.position + Vector3(b.size.x, 0, 0),
		b.position + Vector3(0, b.size.y, 0),
		b.position + Vector3(0, 0, b.size.z),
		b.position + Vector3(b.size.x, b.size.y, 0),
		b.position + Vector3(b.size.x, 0, b.size.z),
		b.position + Vector3(0, b.size.y, b.size.z),
		b.position + b.size,
	]
