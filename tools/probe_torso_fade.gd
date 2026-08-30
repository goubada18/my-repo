extends SceneTree
## 回归探针：待机↔行走切换瞬间上半身抖动（用户报告：待机→行走朝右下抖、
## 行走→待机朝右上抖）。机理：俯仰叠加层基准在 0.15s 交叉淡入期间把旧动画的
## 脊柱贡献瞬间清零 → 腰部骨骼切换帧弹跳（哨兵检测修复前）。
## 方法：--fixed-fps 60 固定帧率（物理=渲染=1:1），探针【绝不自行驱动叠加层】
## （游戏 _process 每帧自驱动），每帧采样一次 Spine 渲染旋转，
## 断言切换窗口单帧最大变化量 ≤ 12°（行走动画自身脊柱摆动约 2~4°/帧；
## 基准清零 bug 复发时会出现 15~40° 单帧跳变）。
const SPINE := "mixamorig_Spine"
const THRESHOLD_DEG := 12.0

func _init():
	var ps = load("res://scenes/main_multichar.tscn")
	var m = ps.instantiate()
	root.add_child(m)
	for i in range(40):
		await process_frame
	var p = root.find_child("Player", true, false)
	var skel = p.get("_weapon_skel")
	var cam = p.get("_camera_ctrl")
	if p == null or skel == null or cam == null:
		printerr("PROBE_FAIL: 未就绪")
		quit(1)
		return
	var spine_idx: int = skel.find_bone(SPINE)
	cam.pitch = 0.4   # 低头（俯仰叠加激活，正对用户实际游玩场景）
	p.is_crouching = false
	p.current_state = p.AnimState.IDLE_AIM

	# 阶段A：待机稳定期基线
	var prev := _rot(skel, spine_idx)
	var base_max := 0.0
	for i in range(40):
		await process_frame
		p.current_state = p.AnimState.IDLE_AIM
		var cur := _rot(skel, spine_idx)
		base_max = maxf(base_max, rad_to_deg(prev.angle_to(cur)))
		prev = cur

	# 阶段B：待机→行走（状态机自然切换，含 0.15s 淡入）
	Input.action_press("move_forward")
	var max_a := 0.0
	var anim_b := "?"
	for i in range(30):
		await process_frame
		var cur := _rot(skel, spine_idx)
		max_a = maxf(max_a, rad_to_deg(prev.angle_to(cur)))
		prev = cur
		var ap = p.get("anim_player")
		if ap != null:
			anim_b = str(ap.current_animation)
	Input.action_release("move_forward")

	# 阶段C：行走→待机
	var max_b := 0.0
	var anim_c := "?"
	for i in range(30):
		await process_frame
		var cur := _rot(skel, spine_idx)
		max_b = maxf(max_b, rad_to_deg(prev.angle_to(cur)))
		prev = cur
		var ap = p.get("anim_player")
		if ap != null:
			anim_c = str(ap.current_animation)

	print("PROBE: 待机基线=%.2f° 待机→行走=%.2f°(anim=%s) 行走→待机=%.2f°(anim=%s) 阈值=%.0f°" % [
		base_max, max_a, anim_b, max_b, anim_c, THRESHOLD_DEG])
	if max_a > THRESHOLD_DEG or max_b > THRESHOLD_DEG:
		print("PROBE_FAIL>>> 切换瞬间 Spine 跳变超阈值（基准清零 bug 复发）")
		quit(1)
	print("PROBE_OK>>> 切换淡入平滑，无单帧跳变")
	quit(0)

func _rot(skel: Skeleton3D, idx: int) -> Quaternion:
	return skel.get_bone_pose(idx).basis.get_rotation_quaternion()
