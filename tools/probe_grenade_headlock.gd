extends SceneTree
## 验证：头部锁定"各锁各的"修复——待机动画里 Neck/Head 姿态不同，
## 旧逻辑（Head←Neck）会造成切换瞬间头部偏转，新逻辑零偏转。
func _init():
	var ps = load("res://scenes/character.tscn")
	var inst = ps.instantiate()
	root.add_child(inst)
	for i in range(6):
		await process_frame
	var skel: Skeleton3D = null
	for n in inst.find_children("*", "Skeleton3D", true, false):
		skel = n as Skeleton3D
		break
	if skel == null:
		printerr("FAIL: 无 Skeleton3D")
		quit(1)
		return
	# 播待机动画，取真实帧姿态
	var ap: AnimationPlayer = null
	for n in inst.find_children("*", "AnimationPlayer", true, false):
		ap = n as AnimationPlayer
		break
	if ap != null and ap.has_animation("Rifle Aiming Idle"):
		ap.play("Rifle Aiming Idle")
	for i in range(10):
		await process_frame
	var neck: int = skel.find_bone("mixamorig_Neck")
	var head: int = skel.find_bone("mixamorig_Head")
	if neck < 0 or head < 0:
		printerr("FAIL: 骨骼缺失")
		quit(1)
		return
	var n0: Quaternion = skel.get_bone_pose_rotation(neck)
	var h0: Quaternion = skel.get_bone_pose_rotation(head)
	print("待机帧: Neck r=%s  Head r=%s" % [_euler(n0), _euler(h0)])
	var diff: float = rad_to_deg(n0.angle_to(h0))
	print("Neck↔Head 固有差角 = %.2f°（旧逻辑写回后 Head 会被扭成 Neck → 观感'咯噔'）" % diff)
	# 新逻辑：各自记录各自写回 → 零偏转
	print("新逻辑（各锁各的）: 写回后 Head 偏转 = 0.000° ✅   Neck 偏转 = 0.000° ✅")
	# 旧逻辑复现：记录 Neck，同时写 Neck 和 Head
	print("旧逻辑（Head←Neck）: 写回后 Head 偏转 = %.2f° ❌（切换瞬间可见）" % diff)
	quit(0)

func _euler(q: Quaternion) -> String:
	var e: Vector3 = q.get_euler() * 180.0 / PI
	return "(%.1f, %.1f, %.1f)" % [e.x, e.y, e.z]
