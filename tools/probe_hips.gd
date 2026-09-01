extends SceneTree
## 实测：① 运行时待机时 Hips 骨骼 pose ② 源动画 Rifle Aiming Idle 的 Hips 旋转轨道值。

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	# ① 源动画 Hips rotation 值
	var lib: AnimationLibrary = load("res://resources/mixamo_lib.tres") as AnimationLibrary
	var idle: Animation = lib.get_animation("Rifle Aiming Idle") as Animation
	for ti in idle.get_track_count():
		if idle.track_get_type(ti) != Animation.TYPE_ROTATION_3D:
			continue
		if String(idle.track_get_path(ti)).contains("Hips"):
			var q: Quaternion = idle.track_get_key_value(ti, 0)
			var e := q.get_euler()
			print("SRC Rifle Aiming Idle Hips rotation q=(%.4f,%.4f,%.4f,%.4f) 欧拉=%.1f°,%.1f°,%.1f°" % [
				q.x, q.y, q.z, q.w, rad_to_deg(e.x), rad_to_deg(e.y), rad_to_deg(e.z)])
			break
	# ② 运行时待机 Hips pose
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
	var def = player._weapon_system.select_by_id("gaobao")
	player._switch_to_weapon(def)
	await process_frame
	var skel = player._weapon_skel
	var hi: int = skel.find_bone("mixamorig_Hips")
	var qp: Quaternion = skel.get_bone_pose_rotation(hi)
	var ep := qp.get_euler()
	print("RUNTIME 待机 Hips pose q=(%.4f,%.4f,%.4f,%.4f) 欧拉=%.1f°,%.1f°,%.1f°" % [
		qp.x, qp.y, qp.z, qp.w, rad_to_deg(ep.x), rad_to_deg(ep.y), rad_to_deg(ep.z)])
	# 节点旋转
	print("RUNTIME 角色节点旋转 Y=%.1f°" % rad_to_deg(scene.rotation.y if scene is Node3D else 0.0))
	quit(0)
