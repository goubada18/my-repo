extends SceneTree
## 手雷 3P 运行时验证（Toss Grenade 裁剪版）。
## 用法: godot --headless --path . --script res://tools/probe_grenade_runtime.gd
## 验证：换装→待机合成→拉环直驱→持环等待(拉环末帧)→投掷→回收。

const ARMS := ["LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
	"RightShoulder", "RightArm", "RightForeArm", "RightHand"]

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	await process_frame
	var ps := load("res://scenes/main_multichar.tscn") as PackedScene
	if ps == null:
		printerr("FAIL: 主场景加载失败")
		quit(1)
		return
	var scene = ps.instantiate()
	get_root().add_child(scene)
	await process_frame
	await process_frame
	var player = scene.get_node_or_null("Player")
	if player == null:
		var stack := [scene]
		while not stack.is_empty() and player == null:
			var n = stack.pop_back()
			for c in n.get_children():
				if c is CharacterBody3D and c.get_script() != null:
					player = c
					break
				stack.push_back(c)
	if player == null:
		printerr("FAIL: 找不到 Player")
		quit(1)
		return
	print("STEP1 Player 就绪: ", player.name)

	# ---- 切到手雷 ----
	var def = player._weapon_system.select_by_id("gaobao")
	if def == null:
		printerr("FAIL: 注册表无 gaobao")
		quit(1)
		return
	player._switch_to_weapon(def)
	await process_frame
	print("STEP2 换装: weapon_type=", def.weapon_type,
			"  _is_grenade_weapon=", player._is_grenade_weapon())
	print("STEP2a 合成: hold=", player._grenade_hold_arms != null,
			"  备份=", player._grenade_saved.size(),
			"  已应用=", player._grenade_applied.size())

	# ---- 待机合成 8 臂骨 ----
	var ap = player.anim_player
	var idle_name: String = player._anim_name_for(0)
	var anim = null
	var have := {}
	if ap != null and ap.has_animation(idle_name):
		anim = ap.get_animation(idle_name)
		for i in anim.get_track_count():
			var p := String(anim.track_get_path(i))
			var ci := p.rfind(":")
			if ci >= 0:
				have[p.substr(ci + 1).replace("mixamorig_", "")] = true
	var miss := []
	for b in ARMS:
		if not have.has(b):
			miss.append(b)
	print("STEP3 待机合成 8臂骨: ", "齐全 OK" if miss.is_empty() else "缺失 " + str(miss),
			"  动画='%s' 轨道=%d" % [idle_name, anim.get_track_count() if anim != null else -1])

	# ---- 直驱链路（FP 真播 + 3P 跟随）----
	var skel = player._weapon_skel
	if skel == null:
		printerr("FAIL: _weapon_skel 为空")
		quit(1)
		return
	var bidx: int = skel.find_bone("mixamorig_RightArm")
	var pose0: Quaternion = skel.get_bone_pose_rotation(bidx)
	var fp_mode: bool = player._fp_mode and player._fp_vm != null \
			and player._fp_vm.has_method("get_grenade_phase")
	if fp_mode:
		print("STEP4 [FP模式] FP 真播 plugin，3P 影子逐帧跟随：")
		player._fp_vm.trigger_pull()
		player._grenade_held = true
		for i in 30:
			player._fp_vm._ap.advance(1.0 / 60.0)
			player._drive_grenade_arms(1.0 / 60.0)
	else:
		print("STEP4 [3P模式] 本地时间轴拉环:")
		player._grenade_held = true
		player._start_grenade_pull()
		for i in 30:
			player._drive_grenade_arms(1.0 / 60.0)
	var pose1: Quaternion = skel.get_bone_pose_rotation(bidx)
	print("      拉环 0.5s 后 RightArm 角差=%.2f° (%s)" % [
		rad_to_deg(pose0.angle_to(pose1)), "在动 OK" if rad_to_deg(pose0.angle_to(pose1)) > 1.0 else "!! 未动"])

	if fp_mode:
		for i in 90:
			player._fp_vm._ap.advance(1.0 / 60.0)
			player._drive_grenade_arms(1.0 / 60.0)
	else:
		for i in 80:
			player._drive_grenade_arms(1.0 / 60.0)
	print("STEP5 拉环完仍按住: holding=", player._grenade_holding,
			"  pulling=", player._grenade_pulling,
			"  FP_holding=", (player._fp_vm.is_grenade_holding() if fp_mode else "-"),
			"  (期望 holding=true)")
	var pose_hold: Quaternion = skel.get_bone_pose_rotation(bidx)
	# 期望 = pull 末关键帧（长按停拉环末帧）
	var expect: Quaternion = Quaternion.IDENTITY
	var found_ra := false
	if player._grenade_pull_arms != null:
		for ti in player._grenade_pull_arms.get_track_count():
			if String(player._grenade_pull_arms.track_get_path(ti)).contains("RightArm"):
				var kcn: int = player._grenade_pull_arms.track_get_key_count(ti)
				expect = player._grenade_pull_arms.track_get_key_value(ti, kcn - 1)
				found_ra = true
				break
	print("      hold(拉环末帧) RightArm 偏差=%.5f (期望≈0, 找到RA轨道=%s)" % [
		pose_hold.angle_to(expect), found_ra] if found_ra else "      pull 资源缺失")

	if fp_mode:
		player._grenade_held = false
		var was_h: bool = player._fp_vm.is_grenade_holding()
		player._fp_vm.release_pull(was_h)
		if was_h:
			player._start_grenade_throw()
	else:
		player._grenade_held = false
		player._start_grenade_throw()
	print("STEP6 投掷启动: throwing=", player._grenade_throwing)
	if fp_mode:
		for i in 60:
			player._fp_vm._ap.advance(1.0 / 60.0)
			player._drive_grenade_arms(1.0 / 60.0)
	else:
		for i in 40:
			player._drive_grenade_arms(1.0 / 60.0)
	print("STEP7 投掷完回收: throwing=", player._grenade_throwing,
			"  holding=", player._grenade_holding,
			"  (期望全 false，手臂回持雷待机)")
	quit(0)
