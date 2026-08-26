class_name AnimationDiagnostics
extends RefCounted

# ============================================================
# 动画诊断输出
#
# 从 player.gd 抽离的调试报告层。全部为静态函数，接收显式参数，
# 不持有任何状态，也不依赖 AnimState 枚举（一律以动画名字符串沟通）。
#
# 调用方（player.gd）负责判断 DEBUG_MODE；本类被调用即输出。
# 这样热路径上只有一次布尔判断，不会产生字符串拼接开销。
# ============================================================


## 打印全部动画的轨道构成（总数 / 位置 / 旋转 / 缩放 / 循环模式 / 时长）
static func print_all_animation_track_info(anim_player: AnimationPlayer, anim_names) -> void:
	print("========== 动画轨道信息检查 ==========")
	for anim_name in anim_names:
		if anim_name.is_empty():
			continue
		if not anim_player.has_animation(anim_name):
			print("  [警告] 动画不存在: " + anim_name)
			continue
		var anim := anim_player.get_animation(anim_name)
		var pos_tracks := 0
		var rot_tracks := 0
		var scale_tracks := 0
		for i in range(anim.get_track_count()):
			match anim.track_get_type(i):
				Animation.TYPE_POSITION_3D: pos_tracks += 1
				Animation.TYPE_ROTATION_3D: rot_tracks += 1
				Animation.TYPE_SCALE_3D: scale_tracks += 1
		print("  动画 [%s]: 总轨道=%d 位置=%d 旋转=%d 缩放=%d loop_mode=%d length=%s" % [
			anim_name, anim.get_track_count(), pos_tracks, rot_tracks, scale_tracks,
			anim.loop_mode, str(anim.length)
		])
	print("========================================")


## 验证指定动画的位置轨道确实已被移除
static func verify_position_tracks_removed(anim_player: AnimationPlayer, anim_names) -> void:
	print("========== 验证位置轨道移除结果 ==========")
	for anim_name in anim_names:
		if anim_name.is_empty() or not anim_player.has_animation(anim_name):
			continue
		var anim := anim_player.get_animation(anim_name)
		var offender := -1
		for i in range(anim.get_track_count()):
			if anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
				offender = i
				break
		if offender >= 0:
			print("  [失败] %s 仍有位置轨道! idx=%d path=%s" % [
				anim_name, offender, str(anim.track_get_path(offender))
			])
		else:
			print("  [成功] %s 已无位置轨道, 剩余轨道数=%d" % [anim_name, anim.get_track_count()])
	print("=========================================")


## 打印跳跃动画的 Hips 位置轨道首尾帧，用于诊断跳跃闪现
static func log_jump_anim_frames(anim_player: AnimationPlayer, anim_names) -> void:
	print("========== 跳跃动画首尾帧分析 ==========")
	for anim_name in anim_names:
		if anim_name.is_empty() or not anim_player.has_animation(anim_name):
			print("  [跳过] 动画不存在: " + str(anim_name))
			continue
		var anim := anim_player.get_animation(anim_name)
		var pos_count := 0
		print("  --- %s (length=%s) ---" % [anim_name, str(anim.length)])
		for i in range(anim.get_track_count()):
			if anim.track_get_type(i) != Animation.TYPE_POSITION_3D:
				continue
			pos_count += 1
			if str(anim.track_get_path(i)).find("Hips") < 0:
				continue
			var key_count := anim.track_get_key_count(i)
			if key_count < 2:
				continue
			var first_val = anim.track_get_key_value(i, 0)
			var last_val = anim.track_get_key_value(i, key_count - 1)
			print("    [Hips POS] 首帧 y=%s z=%s" % [str(snapped(first_val.y, 0.001)), str(snapped(first_val.z, 0.001))])
			print("    [Hips POS] 末帧 y=%s z=%s" % [str(snapped(last_val.y, 0.001)), str(snapped(last_val.z, 0.001))])
			print("    [Hips POS] 差异=%s" % str(snapped(first_val.distance_to(last_val), 0.001)))
		print("    位置轨道数=%d (移除前)" % pos_count)
	print("==========================================")


## 统一空间坐标日志：对比蹲姿待机与蹲姿移动时的各层 Y 坐标是否自洽。
## player 走鸭子类型传入，避免与 Player 形成 class_name 循环引用。
static func log_spatial_info(context: String, player, camera_controller) -> void:
	var skeleton: Skeleton3D = null
	var armature: Node3D = null
	if player.has_node("Character/Armature"):
		armature = player.get_node("Character/Armature")
	if player.has_node("Character/Armature/Skeleton3D"):
		skeleton = player.get_node("Character/Armature/Skeleton3D")

	var arm_global: Vector3 = armature.global_position if armature else Vector3.ZERO
	var hips_y := _bone_global_y(skeleton, "mixamorig_Hips")
	var head_y := _bone_global_y(skeleton, "mixamorig_Head")
	var left_foot_y := _bone_global_y(skeleton, "mixamorig_LeftFoot")

	var capsule := player.collision_shape.shape as CapsuleShape3D
	var cap_h: float = capsule.height if capsule else -1.0
	var cam: Dictionary = camera_controller.get_debug_info() if camera_controller else {}

	print(">>> [%s] state=%d crouch=%s | visual_y=%s cap_h=%s cap_pos_y=%s arm_y=%s hips_y=%s head_y=%s lfoot_y=%s player_y=%s on_floor=%s | CAM: pivot_y=%s tgt_pivot_y=%s look_h=%s tgt_look_h=%s cam_glb_y=%s pitch=%sdeg" % [
		context,
		player.current_state,
		str(player.is_crouching),
		str(snapped(player.character_visual.position.y, 0.001)),
		str(snapped(cap_h, 0.01)),
		str(snapped(player.collision_shape.position.y, 0.01)),
		str(snapped(arm_global.y, 0.001)),
		str(snapped(hips_y, 0.001)),
		str(snapped(head_y, 0.001)),
		str(snapped(left_foot_y, 0.001)),
		str(snapped(player.global_position.y, 0.001)),
		str(player.is_on_floor()),
		str(snapped(cam.get("pivot_y", -9), 0.001)),
		str(snapped(cam.get("target_pivot_y", -9), 0.01)),
		str(snapped(cam.get("look_h", -9), 0.001)),
		str(snapped(cam.get("target_look_h", -9), 0.01)),
		str(snapped(cam.get("cam_global_y", -9), 0.001)),
		str(snapped(cam.get("pitch_deg", -9), 0.1)),
	])


static func _bone_global_y(skeleton: Skeleton3D, bone_name: String) -> float:
	if skeleton == null:
		return -999.0
	var idx := skeleton.find_bone(bone_name)
	if idx < 0:
		return -999.0
	return (skeleton.global_transform * skeleton.get_bone_global_pose(idx)).origin.y
