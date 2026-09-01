extends SceneTree
## 检查标定场景里 Grenade 节点：世界 AABB / 材质 / 网格是否正常。
## 判断"能看到节点看不到模型"是变换问题还是材质渲染问题。

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var ps: PackedScene = load("res://scenes/grenade_calib.tscn")
	if ps == null:
		print("FAIL: 无法加载标定场景")
		quit(1)
		return
	var scene = ps.instantiate()
	get_root().add_child(scene)
	await process_frame
	await process_frame
	var g = scene.get_node_or_null("HandAnchor/Grenade")
	if g == null:
		print("FAIL: 场景树无 HandAnchor/Grenade")
		quit(1)
		return
	print("Grenade 节点存在: name=%s class=%s" % [g.name, g.get_class()])
	print("Grenade local transform: origin=%s scale=%s rot=%s" % [
		g.transform.origin, g.transform.basis.get_scale(), g.transform.basis.get_rotation_quaternion()])
	print("Grenade global transform: origin=%s scale=%s" % [
		g.global_transform.origin, g.global_transform.basis.get_scale()])
	# 世界 AABB（节点变换 × 网格本地 AABB）
	var aabb := AABB()
	var mesh_count := 0
	var mat_names := []
	for mi in g.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		mesh_count += 1
		aabb = aabb.merge(m.get_aabb())
		if m.mesh != null:
			print("  Mesh[%s] 面数(索引数)=%d 可见=%s 本地AABB=%s" % [
				m.name, m.mesh.get_faces().size(), m.visible, m.get_aabb()])
		if m.material_override != null:
			mat_names.append("override:" + str(m.material_override.resource_name))
		if m.get_active_material(0) != null:
			var mat = m.get_active_material(0)
			mat_names.append("active:" + mat.resource_name + " class=" + mat.get_class())
			if mat.get_class() == "StandardMaterial3D":
				var sm := mat as StandardMaterial3D
				print("    albedo=%s  texture=%s  flags=%s" % [
					sm.albedo_color, sm.albedo_texture != null, sm.flags_unshaded])
	var gtf: Transform3D = g.global_transform
	var waabb := AABB(gtf * aabb.position, aabb.size * gtf.basis.get_scale())
	print("网格数=%d 合并本地AABB=%s size=%s" % [mesh_count, aabb, aabb.size])
	print("世界AABB center=%s size=%s" % [waabb.get_center(), waabb.size])
	print("材质: %s" % str(mat_names))
	if aabb.size.length() < 0.001:
		print(">>> 网格尺寸≈0：模型数据异常")
	if waabb.size.length() < 0.001 or waabb.size.length() > 100.0:
		print(">>> 世界AABB异常（极小或极大）→ 变换问题")
	quit(0)
