extends SceneTree
func _init():
	var ps = load("res://scenes/player_preview.tscn")
	var inst = ps.instantiate()
	root.add_child(inst)
	for i in range(15):
		await process_frame
	var player: Node3D = inst as Node3D
	var pivot: Node3D = player.get_node_or_null("CameraPivot") if player != null else null
	if player == null or pivot == null:
		printerr("FAIL: player=%s pivot=%s" % [str(player), str(pivot)])
		quit(1)
		return
	var cam: Camera3D = pivot.get("camera")
	if cam == null:
		printerr("FAIL: camera null")
		quit(1)
		return
	var pp: Vector3 = player.global_position
	var cp: Vector3 = cam.global_position
	var rel: Vector3 = cp - pp
	var fwd: Vector3 = player.global_transform.basis.z
	print("角色位置=%s 前向=%s" % [str(pp), str(fwd)])
	print("相机位置=%s 相对角色=(%s) 距离=%.2f" % [str(cp), str(rel), rel.length()])
	print("相机相对·角色前向 = %.2f（>0 前方 / <0 背后）" % rel.normalized().dot(fwd.normalized()))
	print("相机视线 = %s" % str(-cam.global_transform.basis.z))
	print("pivot y=%.2f spring_len=%.2f" % [pivot.position.y, (pivot.get("spring_arm") as SpringArm3D).spring_length])
	quit(0)
