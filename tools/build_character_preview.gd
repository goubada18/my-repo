extends SceneTree

# 生成 character_preview.tscn：复制原 character.tscn 的 AnimationPlayer/武器/握持点，
# 仅把 Armature（Skeleton3D+蒙皮网格）替换为新角色 FBX 的“Armature”补偿节点
# （FBX 内部 root -> Armature -> Skeleton3D，该节点携带把身体摆正的旋转/缩放），
# 使动画轨道路径 Armature/Skeleton3D:mixamorig_* 解析。
#
# 关键坑（2026-08-14 实测）：
#  1) 新 FBX 骨骼 rest 原点不在身体上（Hips rest 在 Y≈-419），FBX 内部 "Armature" 节点
#     带旋转把它摆正；若只 duplicate Skeleton3D 丢掉该节点，身体被甩到地下几百单位（看不到）。
#  2) 新角色骨骼以“厘米”存储，而 飞虎队 场景整体带 cm->m 缩放，二者单位基准不同——
#     光用 cm/cm 高度比(0.5568)仍会比 飞虎队 大几十倍。故这里直接量两角色的世界骨骼高度，
#     动态求缩放比，再平移让脚落在 y=0。整个过程不改任何现有文件。

const LOG := "C:/Users/93343/Desktop/demo/build_log2.txt"

func _log(s: String) -> void:
	var f := FileAccess.open(LOG, FileAccess.READ_WRITE)
	if f != null:
		f.seek_end(0)
		f.store_string(s + "\n")
		f.close()

# 量某实例里 Skeleton3D 的“世界骨骼高度”与最低/中心，用于对齐尺寸与落地。
func _measure_skel(inst: Node) -> Dictionary:
	var skel := inst.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null:
		return {"ok": false}
	skel.force_update_transform()
	var min_y := INF
	var max_y := -INF
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for i in range(skel.get_bone_count()):
		var wp := skel.global_transform * skel.get_bone_global_pose(i)
		min_y = min(min_y, wp.origin.y); max_y = max(max_y, wp.origin.y)
		min_x = min(min_x, wp.origin.x); max_x = max(max_x, wp.origin.x)
		min_z = min(min_z, wp.origin.z); max_z = max(max_z, wp.origin.z)
	return {
		"ok": true,
		"height": max_y - min_y,
		"min_y": min_y, "max_y": max_y,
		"cx": (min_x + max_x) * 0.5, "cz": (min_z + max_z) * 0.5,
	}

func _initialize() -> void:
	var lf := FileAccess.open(LOG, FileAccess.WRITE)
	if lf != null:
		lf.close()
	_log("START")

	var orig_ps: PackedScene = load("res://scenes/character.tscn")
	var new_ps:  PackedScene = load("res://新角色/Rifle Aiming Idle_fixed.fbx")
	if orig_ps == null or new_ps == null:
		_log("LOAD_FAIL")
		quit(1)
		return

	var orig: Node = orig_ps.instantiate()
	var newroot: Node = new_ps.instantiate()

	# 取 FBX 内部 "Armature" 补偿节点（root -> Armature -> Skeleton3D）
	var fbx_arm: Node = newroot.find_child("Armature", true, true)
	if fbx_arm == null and newroot.get_child_count() > 0:
		fbx_arm = newroot.get_child(0)
	if fbx_arm == null:
		_log("NEW_ARMATURE_MISSING")
		quit(1)
		return
	_log("fbx_arm class=" + fbx_arm.get_class() + " is_Node3D=" + str(fbx_arm is Node3D))

	var old_arm: Node = orig.get_node_or_null("Armature")
	if old_arm != null:
		orig.remove_child(old_arm)
	newroot.remove_child(fbx_arm)
	orig.add_child(fbx_arm)
	fbx_arm.owner = orig
	_set_owner_recursive(fbx_arm, orig)

	# 先把 fbx_arm 放树上，量出新角色与 飞虎队 的世界骨骼高度，动态求缩放比
	root.add_child(orig)
	var cha_inst: Node = load("res://scenes/character.tscn").instantiate()
	root.add_child(cha_inst)
	await create_timer(0.05).timeout

	var m_n := _measure_skel(orig)
	var m_f := _measure_skel(cha_inst)
	_log("NEWSWAT height=" + str(m_n.height if m_n.ok else -1) + " FEIHU height=" + str(m_f.height if m_f.ok else -1))
	if not (m_n.ok and m_f.ok) or m_n.height < 0.001:
		_log("MEASURE_FAIL")
		quit(1)
		return

	# 动态缩放比：让新角色高度 == 飞虎队 高度（消除 cm/m 单位基准差）
	var size_ratio: float = float(m_f.height) / float(m_n.height)
	_log("SIZE_RATIO=" + str(size_ratio))
	if fbx_arm is Node3D:
		fbx_arm.transform = fbx_arm.transform.scaled(Vector3(size_ratio, size_ratio, size_ratio))

	# 重新量（缩放后）并平移，让脚落到 y=0、身体 X/Z 居中
	var m_n2 := _measure_skel(orig)
	if m_n2.ok:
		fbx_arm.position += Vector3(float(-m_n2.cx), float(-m_n2.min_y), float(-m_n2.cz))
		_log("REPOSITION shift=(" + str(-m_n2.cx) + ", " + str(-m_n2.min_y) + ", " + str(-m_n2.cz) + ")")

	root.remove_child(orig)
	root.remove_child(cha_inst)

	# 保存
	var ps := PackedScene.new()
	var err := ps.pack(orig)
	_log("pack err=" + str(err))
	if err != OK:
		_log("PACK_FAIL " + str(err)); quit(1); return
	err = ResourceSaver.save(ps, "res://scenes/character_preview.tscn")
	_log("save err=" + str(err))
	if err != OK:
		_log("SAVE_FAIL " + str(err)); quit(1); return

	var reload: PackedScene = load("res://scenes/character_preview.tscn")
	var inst: Node = reload.instantiate()
	root.add_child(inst)
	await create_timer(0.05).timeout
	var m_check := _measure_skel(inst)
	_log("CHECK height=" + str(m_check.height if m_check.ok else -1) +
		" min_y=" + str(m_check.min_y if m_check.ok else -1) +
		" max_y=" + str(m_check.max_y if m_check.ok else -1))
	root.remove_child(inst)
	_log("PREVIEW_SAVED")
	quit(0)

func _set_owner_recursive(n: Node, owner: Node) -> void:
	n.owner = owner
	for c in n.get_children():
		_set_owner_recursive(c, owner)
