extends SceneTree
## 一次性诊断：量 grenade_world.glb 的【原始 local 尺寸】与内部节点结构，
## 从而算出在 feihu(0.00026) / swat(0.0138) 骨架下正确的 local_scale。
const GLB := "res://resources/models/grenade/grenade_world.glb"

func _init():
	var packed: PackedScene = load(GLB) as PackedScene
	if packed == null:
		printerr("PROBE_FAIL: 无法加载 " + GLB)
		quit(1)
		return
	var inst: Node = packed.instantiate()
	root.add_child(inst)
	_dump(inst, 0)
	# 累积世界 AABB（此时父=root，scale=1 → 即模型原始尺寸）
	var mn := Vector3.ZERO
	var mx := Vector3.ZERO
	var first := true
	var n := 0
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var mesh := mi as MeshInstance3D
		if mesh.mesh == null:
			continue
		n += 1
		var box: AABB = mesh.get_aabb()
		print("  mesh[%s] local_aabb pos=%s size=%s  节点scale=%s" % [
			mesh.name, str(box.position), str(box.size),
			str(mesh.global_transform.basis.get_scale())])
		for c in _corners(box):
			var wc: Vector3 = mesh.global_transform * c
			if first:
				mn = wc
				mx = wc
				first = false
			else:
				mn = mn.min(wc)
				mx = mx.max(wc)
	print("网格数=%d" % n)
	print("GLB 原始世界AABB: min=%s max=%s" % [str(mn), str(mx)])
	var size: Vector3 = mx - mn
	print("GLB 原始尺寸 = %s   最大轴=%.4f 单位" % [str(size), max(size.x, max(size.y, size.z))])
	# 反推标定 scale
	var raw: float = max(size.x, max(size.y, size.z))
	for pair in [["feihu", 0.00026], ["swat", 0.0138]]:
		var target: float = 0.1  # 目标世界尺寸 10cm（手雷长约 10cm）
		var s: float = target / (raw * pair[1])
		print("→ %s (骨架scale≈%s): 要 %.2fm 需 local_scale ≈ %.1f" % [pair[0], str(pair[1]), target, s])
	quit(0)

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

func _dump(n: Node, depth: int) -> void:
	var ind: String = "  ".repeat(depth)
	var extra: String = ""
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		extra = " mesh=%s visible=%s skin=%s" % [str(mi.mesh != null), str(mi.visible), str(mi.skin != null)]
	elif n is Node3D:
		var n3 := n as Node3D
		extra = " xform_scale=%s visible=%s" % [str(n3.transform.basis.get_scale()), str(n3.visible)]
	print("%s- %s (%s)%s" % [ind, n.name, n.get_class(), extra])
	for c in n.get_children():
		_dump(c, depth + 1)
