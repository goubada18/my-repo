extends SceneTree
## 持环（拉环末帧）姿态下，双手世界位置相对身体（Hips）——判断穿模。
## 输出：左右手在身体前/后、左/右、高/低的偏移，以及身体前后向。

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
	player._switch_to_weapon(player._weapon_system.select_by_id("gaobao"))
	await process_frame
	var skel = player._weapon_skel
	var hi: int = skel.find_bone("mixamorig_Hips")
	var rh: int = skel.find_bone("mixamorig_RightHand")
	var lh: int = skel.find_bone("mixamorig_LeftHand")
	var sh: int = skel.find_bone("mixamorig_RightShoulder")

	player._start_grenade_pull()
	player._grenade_held = true
	for i in 45:
		player._drive_grenade_arms(1.0 / 60.0)   # 0.75s > 0.644s → 持环末帧
	print("pulling=%s holding=%s" % [player._grenade_pulling, player._grenade_holding])
	var hp: Vector3 = skel.get_bone_global_pose(hi).origin
	var hp_rh: Vector3 = skel.get_bone_global_pose(rh).origin
	var hp_lh: Vector3 = skel.get_bone_global_pose(lh).origin
	var hp_sh: Vector3 = skel.get_bone_global_pose(sh).origin
	# 身体前向 = Hips 全局旋转的 -Z（Mixamo 角色面朝 +Z？先打印两种）
	var q: Quaternion = skel.get_bone_global_pose(hi).basis.get_rotation_quaternion()
	var fwd: Vector3 = q * Vector3(0, 0, 1)
	var right: Vector3 = q * Vector3(1, 0, 0)
	print("Hips 前向=%s 右向=%s" % [fwd, right])
	for tag, p in [["RightHand", hp_rh], ["LeftHand", hp_lh], ["RightShoulder", hp_sh]]:
		var d := p - hp
		print("%-14s 相对Hips: 前=%6.1f 右=%6.1f 高=%6.1f   (长度%.0f)" % [
			tag, d.dot(fwd), d.dot(right), d.y, d.length()])
	quit(0)
