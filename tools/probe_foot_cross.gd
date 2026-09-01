extends SceneTree
## Verify leg-cross detection: foot Y diff zero-crossings during walk anim.
## Expected: ~1 crossing per half gait cycle (walk 0.967s loop -> ~2 crossings per loop).
func _init():
	var ps: PackedScene = load("res://scenes/player.tscn")
	var inst = ps.instantiate()
	root.add_child(inst)
	for i in range(15):
		await process_frame
	var skel: Skeleton3D = inst.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null:
		printerr("no skel")
		quit(1)
		return
	var li: int = skel.find_bone("mixamorig_LeftFoot")
	var ri: int = skel.find_bone("mixamorig_RightFoot")
	var ap: AnimationPlayer = inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var walk_anim: Animation = ap.get_animation("Walking")
	walk_anim.loop_mode = 1
	ap.play("Walking")
	ap.speed_scale = 1.0
	var crossings: int = 0
	var prev_diff: float = INF
	var last_cross_ms: int = 0
	for i in range(150):   # 2.5s
		await process_frame
		var yl: float = skel.get_bone_global_pose(li).origin.y
		var yr: float = skel.get_bone_global_pose(ri).origin.y
		var d: float = yl - yr
		if prev_diff != INF:
			var crossed: bool = (d > 0.0 and prev_diff <= 0.0) or (d < 0.0 and prev_diff >= 0.0)
			if crossed:
				crossings += 1
		prev_diff = d
	print("2.5s 走路动画 两腿交叉次数 = %d (理论 ~4-5：0.967s/循环×2 次交叉)" % crossings)
	var ok: bool = crossings >= 3 and crossings <= 7
	print("=> %s" % ("ALL PASS (交叉频率合理)" if ok else "FAIL"))
	quit(0)
