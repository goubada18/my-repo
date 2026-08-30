extends SceneTree
# 回归探针：躯干俯仰叠加的累积型失控旋转（用户实机反馈）。
# 场景还原：蹲下 + 低头 + 挥刀。挥刀(方案C)不切换状态 → CROUCH_IDLE_AIM 仍在
# 俯仰白名单内，叠加层持续激活；挥刀下半身跟随重合成(_nepal_maybe_follow_lower →
# stop/install/play)会让 AnimationPlayer 出现【不重写 Spine 骨】的窗口帧。
# 旧实现的俯仰基准读实时骨骼姿态(get_bone_pose)=读-改-写：窗口帧里上一帧的
# 输出成为本帧输入 → 逐帧累积 → 上半身绕水平轴不停旋转。
# 验证方法：AP 停播（模拟无重写窗口）后连续驱动叠加层 200 帧，
# Spine 相对 rest 的偏转必须保持有界（修复前会累积到数千度）。
func _init():
	var ps = load("res://scenes/main_multichar.tscn")
	if ps == null:
		printerr("PROBE_FAIL: cannot load scene")
		quit(1)
		return
	var m = ps.instantiate()
	root.add_child(m)
	for i in range(30):
		await process_frame
	var p = root.find_child("Player", true, false)
	if p == null or not p.has_method("_select_weapon_by_id"):
		printerr("PROBE_FAIL: no player")
		quit(1)
		return
	p._select_weapon_by_id("nepal_kukri")
	for i in range(10):
		await process_frame
	var skel = p.get("_weapon_skel")
	var ap = p.get("anim_player")
	var cam = p.get("_camera_ctrl")
	if skel == null or ap == null or cam == null:
		printerr("PROBE_FAIL: missing skel/ap/cam")
		quit(1)
		return
	var spine_idx: int = skel.find_bone("mixamorig_Spine")
	if spine_idx < 0:
		printerr("PROBE_FAIL: no spine bone")
		quit(1)
		return
	var rest_q: Quaternion = skel.get_bone_rest(spine_idx).basis.get_rotation_quaternion()
	cam.pitch = 0.6   # 低头（弧度）
	p.is_crouching = true
	p.current_state = p.AnimState.CROUCH_IDLE_AIM
	# 阶段1：AP 正常播放下驱动 120 帧——新旧实现都应有界（AP 每帧重写 Spine）
	for i in range(120):
		await process_frame
		p.current_state = p.AnimState.CROUCH_IDLE_AIM
		p._apply_torso_pitch_overlay(1.0 / 60.0)
	var q1: Quaternion = skel.get_bone_pose(spine_idx).basis.get_rotation_quaternion()
	var a1: float = rad_to_deg(rest_q.angle_to(q1))
	# 阶段2：AP 停播（=重合成/切换窗口：无重写）再连续驱动 200 帧
	ap.stop()
	var max_dev: float = a1
	for i in range(200):
		p.current_state = p.AnimState.CROUCH_IDLE_AIM
		p._apply_torso_pitch_overlay(1.0 / 60.0)
		var qq: Quaternion = skel.get_bone_pose(spine_idx).basis.get_rotation_quaternion()
		max_dev = maxf(max_dev, rad_to_deg(rest_q.angle_to(qq)))
	print("PROBE: 播放期偏转=%.1f° 停播200帧最大偏转=%.1f°" % [a1, max_dev])
	# 有界判定：俯仰极限 ±50° + 动画自身 Spine 摆动余量；失控累积会到数千度
	if max_dev > 120.0:
		print("PROBE_FAIL>>> Spine 旋转失控(累积型): max=%.1f°" % max_dev)
		quit(1)
	else:
		print("PROBE_OK>>> Spine 旋转有界: max=%.1f°" % max_dev)
		quit(0)
