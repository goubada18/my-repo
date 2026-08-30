extends SceneTree
## 阶段B（正确版）：重建 character_preview.tscn —— 新SWAT 完整接入系统副本。
## 标准"重装+重绑定"算法：
##   1. 新骨架逐骨静止姿态 = 飞虎队静止姿态（进入动画坐标系 frame A）；
##   2. 顶点重装(repose)：v' = Σ w × rest_A_global[k] × (s·bind_old[k]) × v；
##   3. 绑定重烘焙：bind_new[j] = rest_A_global[skel_bone(j)]^{-1}。
## 这样静止渲染 = v'（精确自洽），动画渲染 = 标准蒙皮（精确自洽）。
## 用法：godot --headless --path <proj> --script tools/build_system_preview.gd

const FEIHU := "res://scenes/character.tscn"
const NEW_FBX := "res://新角色/Rifle Aiming Idle.fbx"
const OUT := "res://scenes/character_preview.tscn"

var _buf: PackedStringArray = PackedStringArray()

func _log(s: String) -> void:
	_buf.append(s)

func _flush() -> void:
	var f := FileAccess.open("res://probe_build_system.txt", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_buf) + "\n")
		f.close()
	for s in _buf:
		print(s)

func _collect(n: Node, out: Array = []) -> Array:
	out.append(n)
	for c in n.get_children():
		_collect(c, out)
	return out

func _find_skel(n: Node) -> Skeleton3D:
	for c in _collect(n):
		if c is Skeleton3D:
			return c
	return null

func _find_mesh(n: Node) -> MeshInstance3D:
	for c in _collect(n):
		if c is MeshInstance3D and c.mesh is ArrayMesh and c.skin != null:
			return c
	return null

func _render_aabb(inst: Node) -> Vector3:
	var skel: Skeleton3D = _find_skel(inst)
	var mi: MeshInstance3D = _find_mesh(inst)
	if skel == null or mi == null:
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

## 重装+重绑定（归一化版，正确）：
##   1. v_T = Σ w × rest_N[bone] × bind_old[bone] × v     （T-pose 渲染 = 角色真实几何）
##   2. v'   = Σ w × ref[bone] × s × rest_N[bone]^{-1} × v_T （干净小偏移重装到参考姿态）
##   3. bind_new[j] = ref[bone(j)]^{-1}
## 关键：用 rest_N^{-1}×v_T（物理小偏移）代替 bind_old×v（含帧转换的大偏移），避免交叉项放大。
func _repose_and_rebind(mi: MeshInstance3D, rest_N: Dictionary, ref: Dictionary, s: float, skel: Skeleton3D) -> void:
	var m: ArrayMesh = mi.mesh
	var skin: Skin = mi.skin
	var m2: ArrayMesh = m.duplicate(true)
	var s2: Skin = skin.duplicate(true)
	var bcnt: int = skin.get_bind_count()
	var Sc := Transform3D(Basis.from_scale(Vector3.ONE * s), Vector3.ZERO)
	# 预计算：bind j → 骨架骨索引；bind_clean[j] = rest_N^{-1}；bind_new[j] = ref^{-1}
	var bind_skel := []
	var bind_clean := []
	var bind_new := []
	for j in range(bcnt):
		var bname: String = skin.get_bind_name(j)
		var skel_bone: int = skel.find_bone(bname) if bname != "" else skin.get_bind_bone(j)
		bind_skel.append(skel_bone)
		var rname: String = skel.get_bone_name(skel_bone) if skel_bone >= 0 else ""
		var rn: Transform3D = rest_N.get(rname, Transform3D.IDENTITY)
		var rf: Transform3D = ref.get(rname, Transform3D.IDENTITY)
		bind_clean.append(rn.affine_inverse())
		bind_new.append(rf.affine_inverse())
	for j in range(bcnt):
		s2.set_bind_pose(j, bind_new[j])
	# 顶点/法线/切线重装
	var prims := []
	var mats := []
	var arrays_list := []
	for surf in range(m2.get_surface_count()):
		prims.append(m2.surface_get_primitive_type(surf))
		mats.append(m2.surface_get_material(surf))
		var arr := m2.surface_get_arrays(surf)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var new_verts := PackedVector3Array()
		new_verts.resize(verts.size())
		var new_norms: PackedVector3Array = PackedVector3Array()
		if arr.has(Mesh.ARRAY_NORMAL):
			new_norms.resize(verts.size())
		var new_tans: PackedFloat32Array = PackedFloat32Array()
		if arr.has(Mesh.ARRAY_TANGENT):
			new_tans.resize(verts.size() * 4)
		for i in range(verts.size()):
			var v: Vector3 = verts[i]
			# 1) v_T = Σ w × rest_N × bind_old × v（T-pose 渲染 = 真实几何）
			var vT := Vector3.ZERO
			for k in 4:
				var bind_idx: int = bones[i * 4 + k]
				var w: float = weights[i * 4 + k]
				if w <= 0.0 or bind_idx < 0 or bind_idx >= bcnt: continue
				var skel_bone: int = bind_skel[bind_idx]
				if skel_bone < 0: continue
				var rname: String = skel.get_bone_name(skel_bone)
				var rn: Transform3D = rest_N.get(rname, Transform3D.IDENTITY)
				vT += w * (rn * skin.get_bind_pose(bind_idx) * v)
			# 2) v' = Σ w × ref[bone] × s × rest_N[bone]^{-1} × v_T（干净偏移重装）
			var pos := Vector3.ZERO
			var dom_bind := -1
			var dom_w := 0.0
			for k in 4:
				var bind_idx: int = bones[i * 4 + k]
				var w: float = weights[i * 4 + k]
				if w <= 0.0 or bind_idx < 0 or bind_idx >= bcnt: continue
				var skel_bone: int = bind_skel[bind_idx]
				if skel_bone < 0: continue
				if w > dom_w:
					dom_w = w
					dom_bind = bind_idx
				var rname: String = skel.get_bone_name(skel_bone)
				var rf: Transform3D = ref.get(rname, Transform3D.IDENTITY)
				pos += w * (rf * (Sc * bind_clean[bind_idx]) * vT)
			new_verts[i] = pos
			# 法线/切线：主导骨骼的重装旋转（ref.basis × bind_old.basis）
			if dom_bind >= 0:
				var skel_bone: int = bind_skel[dom_bind]
				if skel_bone >= 0:
					var rname: String = skel.get_bone_name(skel_bone)
					var rf: Transform3D = ref.get(rname, Transform3D.IDENTITY)
					var rot: Basis = rf.basis * Basis(skin.get_bind_pose(dom_bind).basis.get_rotation_quaternion())
					if new_norms.size() > 0:
						new_norms[i] = (rot * arr[Mesh.ARRAY_NORMAL][i]).normalized()
					if new_tans.size() > 0:
						var tans_src: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT]
						var t3 := Vector3(tans_src[i * 4], tans_src[i * 4 + 1], tans_src[i * 4 + 2])
						t3 = (rot * t3).normalized()
						new_tans[i * 4] = t3.x
						new_tans[i * 4 + 1] = t3.y
						new_tans[i * 4 + 2] = t3.z
						new_tans[i * 4 + 3] = tans_src[i * 4 + 3]
		arr[Mesh.ARRAY_VERTEX] = new_verts
		if new_norms.size() > 0:
			arr[Mesh.ARRAY_NORMAL] = new_norms
		if new_tans.size() > 0:
			arr[Mesh.ARRAY_TANGENT] = new_tans
		arrays_list.append(arr)
	m2.clear_surfaces()
	for surf in range(arrays_list.size()):
		m2.add_surface_from_arrays(prims[surf], arrays_list[surf])
		if mats[surf] != null:
			m2.surface_set_material(surf, mats[surf])
	mi.mesh = m2
	mi.skin = s2

## 新骨架逐骨 rest = 参考姿态 G_ref 的局部（按骨名）
func _copy_rest_from_ref(nskel: Skeleton3D, ref_global: Dictionary) -> void:
	for i in range(nskel.get_bone_count()):
		var name: String = nskel.get_bone_name(i)
		if not ref_global.has(name):
			continue
		var g: Transform3D = ref_global[name]
		var parent: int = nskel.get_bone_parent(i)
		var local: Transform3D = g
		if parent >= 0:
			var gp: Transform3D = ref_global.get(nskel.get_bone_name(parent), Transform3D.IDENTITY)
			local = gp.affine_inverse() * g
		nskel.set_bone_rest(i, local)

func _set_owner(n: Node, owner: Node) -> void:
	n.owner = owner
	for c in n.get_children():
		_set_owner(c, owner)

func _dump_tree(n: Node, indent: String, out: String) -> String:
	var s: String = out + indent + n.name + "\n"
	for c in n.get_children():
		s = _dump_tree(c, indent + "  ", s)
	return s

func _initialize() -> void:
	_log("=== 阶段B：重装+重绑定（正确版）===")
	var feihu: Node = load(FEIHU).instantiate()
	root.add_child(feihu)
	await process_frame
	await process_frame
	var fskel: Skeleton3D = _find_skel(feihu)
	# 参考姿态 G_ref = 飞虎队 + mixamo_lib "Rifle Aiming Idle" 第0帧（干净人形姿态，frame A）
	var fap: AnimationPlayer = null
	for c in _collect(feihu):
		if c is AnimationPlayer:
			fap = c
			break
	if fap == null or not fap.has_animation("Rifle Aiming Idle"):
		_log("!! 飞虎队 AnimationPlayer 无 Rifle Aiming Idle")
		_flush(); quit(1); return
	fap.play("Rifle Aiming Idle")
	fap.seek(0.0, true)
	await process_frame
	await process_frame
	var ref_global := {}
	for i in range(fskel.get_bone_count()):
		ref_global[fskel.get_bone_name(i)] = fskel.get_bone_global_pose(i)
	# 飞虎队世界渲染高度（含 Armature 补偿 → 2.838m）
	var feihu_render_h: float = _render_aabb(feihu).y
	var arm_scale: float = feihu.get_node("Armature").transform.basis.x.length()
	_log("飞虎队 世界渲染高=%.3f Armature补偿=%.6f" % [feihu_render_h, arm_scale])
	var swat: Node = load(NEW_FBX).instantiate()
	root.add_child(swat)
	await process_frame
	await process_frame
	var nskel: Skeleton3D = _find_skel(swat)
	var nmesh: MeshInstance3D = _find_mesh(swat)
	# 新骨架原始 rest 全局（frame N，重装前的静止姿态）
	var rest_N := {}
	for i in range(nskel.get_bone_count()):
		rest_N[nskel.get_bone_name(i)] = nskel.get_bone_global_pose(i)
	var swat_render_h: float = _render_aabb(swat).y
	# s：N单位偏移 → A单位偏移（字符身高对齐飞虎队）
	var s: float = feihu_render_h / (swat_render_h * arm_scale)
	_log("新SWAT N空间渲染高=%.2f -> s=%.4f" % [swat_render_h, s])
	# 重装+重绑定（归一化：v_T 真实几何 + 干净偏移重装到 G_ref）
	_repose_and_rebind(nmesh, rest_N, ref_global, s, nskel)
	# 新骨架 rest = G_ref 的局部姿态（编辑器静止显示也自洽）
	_copy_rest_from_ref(nskel, ref_global)
	await process_frame
	await process_frame
	var r_before := _render_aabb(swat)
	_log("重装后(原始FBX根, 未套Armature) 渲染AABB size=(%.1f %.1f %.1f) 位置应≈frame A" % [r_before.x, r_before.y, r_before.z])
	# 组装到模板
	var tpl: Node = load(FEIHU).instantiate()
	root.add_child(tpl)
	await process_frame
	await process_frame
	var arm: Node3D = tpl.get_node("Armature")
	var old_skel: Node = arm.get_node("Skeleton3D")
	arm.remove_child(old_skel)
	old_skel.queue_free()
	nskel.get_parent().remove_child(nskel)
	arm.add_child(nskel)
	# 关键：pack() 只序列化 owner==根 的节点 —— 从外部实例 reparent 进来的子树 owner 不对，必须重设
	_set_owner(nskel, tpl)
	await process_frame
	await process_frame
	var r_final := _render_aabb(tpl)
	_log("组装后(含Armature补偿) 渲染AABB size=(%.3f %.3f %.3f)" % [r_final.x, r_final.y, r_final.z])
	# 调试：打包前节点树
	var dbg: String = _dump_tree(tpl, "", "")
	_log("打包前节点树:\n" + dbg)
	var ps := PackedScene.new()
	var err := ps.pack(tpl)
	_log("pack err=%d" % err)
	if err == OK:
		err = ResourceSaver.save(ps, OUT)
		_log("save err=%d -> %s" % [err, OUT])
	tpl.queue_free(); feihu.queue_free(); swat.queue_free()
	await process_frame
	_log("DONE")
	_flush()
	quit(0)
