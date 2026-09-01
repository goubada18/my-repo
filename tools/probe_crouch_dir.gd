extends SceneTree
## 检查蹲走动画各方向的 Hips 朝向（方向反/磕头根源排查）。
## 不拉环状态下直接切状态，读 Hips 全局旋转 Y（角色面向）。
## 角色面朝 +Z 为正常（forward 状态应 ≈0°）。

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
	var states := {
		"CROUCH_IDLE": 1, "CROUCH_WALK_FWD": 6, "CROUCH_WALK_BCK": 7,
		"CROUCH_STRAFE_L": 8, "CROUCH_STRAFE_R": 9,
		"IDLE": 0, "WALK_FWD": 2, "STRAFE_L": 4, "STRAFE_R": 5,
	}
	for s in states.keys():
		player._change_state(states[s])
		player._play_animation(states[s], true, 1.0)
		await process_frame
		await process_frame
		var q: Quaternion = skel.get_bone_global_pose(hi).basis.get_rotation_quaternion()
		var e := q.get_euler()
		print("%-18s Hips 全局旋转欧拉=(%6.1f°, %6.1f°, %6.1f°)  (前走应≈Y=0 面朝+Z)" % [
			s, rad_to_deg(e.x), rad_to_deg(e.y), rad_to_deg(e.z)])
	quit(0)
