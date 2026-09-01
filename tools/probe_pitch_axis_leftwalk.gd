extends SceneTree
## 验证：手雷武器蹲左走时，双手连线叉乘(right_skel)方向是否每步翻转。
## 若翻转 → 俯仰叠加方向每步交替 = "磕头"（用户实测：抛完后左走，1s 一下）。

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
	await process_frame
	player._switch_to_weapon(player._weapon_system.select_by_id("gaobao"))
	await process_frame
	var skel: Skeleton3D = player._weapon_skel
	var ap: AnimationPlayer = player.anim_player
	var rhi := skel.find_bone("mixamorig_RightHand")
	var lhi := skel.find_bone("mixamorig_LeftHand")
	if rhi < 0 or lhi < 0:
		print("FAIL: 找不到手部骨骼")
		quit(1)
		return
	var skel_global := skel.global_transform
	# 状态：8=CROUCH_STRAFE_LEFT, 9=CROUCH_STRAFE_RIGHT, 6=CROUCH_WALK_FORWARD? 用枚举名查
	var st_name := "Crouch Walk Strafe Left"
	var st_idx := -1
	for s in player.AnimState.values() if "AnimState" in player else []:
		pass
	# 直接枚举值：查 player.gd enum 顺序，用名称匹配
	var enums: Dictionary = player.get("AnimState") if player.get("AnimState") != null else {}
	# get("AnimState") 返回 Dictionary（枚举名->值）
	for k in enums:
		if str(k) == st_name.replace(" ", "_").to_upper() or str(k).to_lower() == "crouch_strafe_left":
			st_idx = int(enums[k])
			break
	if st_idx < 0:
		# 兜底：按已知枚举值 8（CROUCH_STRAFE_LEFT，参考 probe_leftwalk.gd 用过 8）
		st_idx = 8
	player._change_state(st_idx)
	player._play_animation(st_idx, true, 1.0)
	# 逐帧算叉乘方向
	var seq := []
	for f in range(80):
		ap.advance(1.0 / 60.0)
		var rh_g: Vector3 = skel.get_bone_global_pose(rhi).origin
		var lh_g: Vector3 = skel.get_bone_global_pose(lhi).origin
		var d: Vector3 = (lh_g - rh_g).normalized()
		var up: Vector3 = (skel_global.basis.inverse() * Vector3.UP).normalized()
		var cross: Vector3 = d.cross(up)
		var dir_s := "L" if cross.dot(Vector3.RIGHT) < 0.0 else "R"
		var ang := rad_to_deg(acos(clampf(cross.normalized().dot(Vector3.RIGHT), -1.0, 1.0)))
		seq.append([dir_s, ang, d.x, d.y, d.z])
	# 输出方向序列
	var dirs := ""
	for s in seq:
		dirs += s[0]
	var flips := 0
	for i in range(1, seq.size()):
		if seq[i][0] != seq[i - 1][0]:
			flips += 1
	print("手雷蹲左走 叉乘方向序列(80帧): " + dirs)
	print("翻转次数: %d (0=方向稳定, >0=每步翻转=磕头根因)" % flips)
	print("采样(每8帧): d=(%.3f,%.3f,%.3f) cross_x角度=%5.1f dir=%s" % [
		seq[0][2], seq[0][3], seq[0][4], seq[0][1], seq[0][0]])
	for i in range(8, 80, 8):
		print("  [%d] d=(%.3f,%.3f,%.3f) cross_x角度=%5.1f dir=%s" % [
			i, seq[i][2], seq[i][3], seq[i][4], seq[i][1], seq[i][0]])
	quit(0)
