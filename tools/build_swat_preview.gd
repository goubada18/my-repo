extends SceneTree
## 保守预览 v3：用【原始 Rifle Aiming Idle.fbx】的完整导入结果生成独立预览场景。
## 关键区别（吸取教训）：
##   1. 不拆 Armature、不重定位、不旋转顶点、不重绑 Skin —— 保留 FBX 导入的全部自洽结构；
##   2. 只对根节点做整体缩放，使渲染高度 = 飞虎队渲染高度（≈2.74m），自动对比得出；
##   3. 自带 FBX 导入的 AnimationPlayer（待机动画），打开就能看到新 SWAT 正确站立+待机。
## 输出：scenes/swat_preview.tscn（独立场景，不影响任何现有场景）。
## 用法：godot --headless --path <proj> --script tools/build_swat_preview.gd

const TARGET_SCENE := "res://scenes/swat_preview.tscn"
const NEW_FBX := "res://新角色/Rifle Aiming Idle.fbx"
const FEIHU_SCENE := "res://scenes/character.tscn"

var _buf: PackedStringArray = PackedStringArray()

func _log(s: String) -> void:
	_buf.append(s)

func _flush() -> void:
	var f := FileAccess.open("res://probe_build_swat.txt", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_buf) + "\n")
		f.close()
	for s in _buf:
		print(s)

## 正确蒙皮渲染公式（BIND_AS_IS，经验证与 Godot 实际一致）：render = Σ w × bone_world × bind × v
func _render_aabb(inst: Node) -> Vector3:
	var skel: Skeleton3D = null
	var mi: MeshInstance3D = null
	for n in _collect(inst):
		if skel == null and n is Skeleton3D:
			skel = n
		if mi == null and n is MeshInstance3D and n.mesh is ArrayMesh and n.skin != null:
			mi = n
	if skel == null or mi == null:
		_log("  !! no skinned mesh (skel=%s mi=%s)" % [skel, mi])
		return Vector3.ZERO
	var m: ArrayMesh = mi.mesh
	var skin: Skin = mi.skin
	var bcnt: int = skin.get_bind_count()
	var vmin := Vector3(1e9, 1e9, 1e9)
	var vmax := Vector3(-1e9, -1e9, -1e9)
	for s in range(m.get_surface_count()):
		var arr := m.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		for i in range(verts.size()):
			var v: Vector3 = verts[i]
			var wpos := Vector3.ZERO
			for k in 4:
				var bind_idx: int = bones[i * 4 + k]
				var w: float = weights[i * 4 + k]
				if w <= 0.0 or bind_idx < 0 or bind_idx >= bcnt:
					continue
				var bname: String = skin.get_bind_name(bind_idx)
				var skel_bone: int = skel.find_bone(bname) if bname != "" else skin.get_bind_bone(bind_idx)
				if skel_bone < 0:
					continue
				var bone_world: Transform3D = skel.global_transform * skel.get_bone_global_pose(skel_bone)
				wpos += w * (bone_world * skin.get_bind_pose(bind_idx) * v)
			vmin = vmin.min(wpos)
			vmax = vmax.max(wpos)
	return vmax - vmin

func _collect(n: Node, out: Array = []) -> Array:
	out.append(n)
	for c in n.get_children():
		_collect(c, out)
	return out

func _initialize() -> void:
	_log("=== 保守预览 v3：原始FBX + 整体缩放 ===")
	# 1) 飞虎队渲染高度（基准）
	var feihu: Node = load(FEIHU_SCENE).instantiate()
	root.add_child(feihu)
	await process_frame
	await process_frame
	var feihu_h: float = _render_aabb(feihu).y
	_log("飞虎队渲染高度 = %.3f" % feihu_h)
	feihu.queue_free()
	# 2) 新 FBX 渲染高度
	var swat: Node = load(NEW_FBX).instantiate()
	root.add_child(swat)
	await process_frame
	await process_frame
	var swat_h: float = _render_aabb(swat).y
	_log("原始RifleAiming渲染高度 = %.3f" % swat_h)
	# 3) 计算整体缩放并应用
	var scale := feihu_h / swat_h
	_log("整体缩放 scale = %.6f (%.3f / %.3f)" % [scale, feihu_h, swat_h])
	swat.scale = Vector3.ONE * scale
	await process_frame
	await process_frame
	var after_h: float = _render_aabb(swat).y
	_log("缩放后渲染高度 = %.3f" % after_h)
	# 4) 打包保存
	var ps := PackedScene.new()
	var err := ps.pack(swat)
	_log("pack err=%d" % err)
	if err == OK:
		err = ResourceSaver.save(ps, TARGET_SCENE)
		_log("save err=%d -> %s" % [err, TARGET_SCENE])
	swat.queue_free()
	_log("DONE")
	_flush()
	quit(0)
