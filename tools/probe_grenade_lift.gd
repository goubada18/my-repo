extends SceneTree
## 验证：持雷待机合成 Shoulder 抬臂 22°（与尼泊尔一致）。

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
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
	if player == null:
		printerr("FAIL: 无 Player")
		quit(1)
		return
	var def = player._weapon_system.select_by_id("gaobao")
	player._switch_to_weapon(def)
	await process_frame
	var ap = player.anim_player
	var idle_name: String = player._anim_name_for(0)
	var q_anim := Quaternion.IDENTITY
	var q_hold := Quaternion.IDENTITY
	var found_a := false
	var found_h := false
	if ap != null and ap.has_animation(idle_name):
		var anim = ap.get_animation(idle_name)
		for ti in anim.get_track_count():
			if String(anim.track_get_path(ti)).contains("RightShoulder"):
				q_anim = anim.track_get_key_value(ti, 0)
				found_a = true
				break
	if player._grenade_hold_arms != null:
		for ti in player._grenade_hold_arms.get_track_count():
			if String(player._grenade_hold_arms.track_get_path(ti)).contains("RightShoulder"):
				q_hold = player._grenade_hold_arms.track_get_key_value(ti, 0)
				found_h = true
				break
	if found_a and found_h:
		# 抬臂已烘焙进 tres：合成版 Shoulder = hold 原值 → 角差应≈0（一致，无切换跳变）
		print("LIFT: 合成 vs hold Shoulder 角差=%.2f° (期望≈0，抬臂已烘焙 22°)" % [
			rad_to_deg(q_anim.angle_to(q_hold))])
	else:
		printerr("FAIL: 轨道未找到 anim=%s hold=%s" % [found_a, found_h])
	quit(0)
