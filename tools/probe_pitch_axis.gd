extends SceneTree
## 实测：拉环态站立时 torso pitch 的 right_skel 方向（双手连线叉乘结果）。
## 目标：拉环期间固定此方向 → 蹲走不再翻转（站立保持原方向不变）。

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
	var rh: int = skel.find_bone("mixamorig_RightHand")
	var lh: int = skel.find_bone("mixamorig_LeftHand")

	# ① 待机（未拉环）双手连线方向
	var rhg: Transform3D = skel.get_bone_global_pose(rh)
	var lhg: Transform3D = skel.get_bone_global_pose(lh)
	var d: Vector3 = (lhg.origin - rhg.origin).normalized()
	var up: Vector3 = (skel.global_transform.basis.inverse() * Vector3.UP).normalized()
	var rs: Vector3 = d.cross(up)
	print("待机  双手连线=%s  叉乘=%s  -> 方向=%s" % [
		d, rs, "LEFT" if rs.dot(Vector3.RIGHT) < 0.0 else "RIGHT"])

	# ② 拉环态（推进到 0.3s）双手连线方向
	player._start_grenade_pull()
	player._grenade_held = true
	for i in 20:
		player._drive_grenade_arms(1.0 / 60.0)
	rhg = skel.get_bone_global_pose(rh)
	lhg = skel.get_bone_global_pose(lh)
	d = (lhg.origin - rhg.origin).normalized()
	rs = d.cross(up)
	print("拉环  双手连线=%s  叉乘=%s  -> 方向=%s" % [
		d, rs, "LEFT" if rs.dot(Vector3.RIGHT) < 0.0 else "RIGHT"])
	quit(0)
