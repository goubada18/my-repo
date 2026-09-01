extends SceneTree
## Sample foot bone world-Y during walk animation to design touch detection.
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
	# 播走路动画
	var ap: AnimationPlayer = inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var walk_name := ""
	for a in ap.get_animation_list():
		if "Walking" in a or "walk" in a:
			walk_name = a
			break
	if walk_name == "":
		print("no walk anim, list:")
		for a in ap.get_animation_list():
			print("  ", a)
		quit(1)
		return
	print("walk anim: %s len=%.3f" % [walk_name, ap.get_animation(walk_name).length])
	ap.play(walk_name)
	ap.speed_scale = 1.0
	# 采样 2.5s，每帧记录两脚世界 Y（相对角色原点）
	var base_y: float = inst.global_position.y
	var out_l: Array = []
	var out_r: Array = []
	for i in range(150):
		await process_frame
		var ly: float = (skel.get_bone_global_pose(li)).origin.y
		var ry: float = (skel.get_bone_global_pose(ri)).origin.y
		out_l.append(ly)
		out_r.append(ry)
	# 统计：min/max/均值 + 谷（局部极小）数量（两种判定对比）
	var mn := INF
	var mx := -INF
	for y in out_l: mn = minf(mn, y); mx = maxf(mx, y)
	print("L foot Y range: %.4f ~ %.4f (amp %.4f)" % [mn, mx, mx - mn])
	mn = INF; mx = -INF
	for y in out_r: mn = minf(mn, y); mx = maxf(mx, y)
	print("R foot Y range: %.4f ~ %.4f (amp %.4f)" % [mn, mx, mx - mn])
	# 谷检测对比：V形严格 vs 差分变号
	for name in ["L", "R"]:
		var arr: Array = out_l if name == "L" else out_r
		var vcount: int = 0
		var zcount: int = 0
		for i in range(2, arr.size()):
			if arr[i-2] > arr[i-1] and arr[i-1] < arr[i]:
				vcount += 1
			var v_prev: float = arr[i-1] - arr[i-2]
			var v_cur: float = arr[i] - arr[i-1]
			if v_prev < 0.0 and v_cur >= 0.0:
				zcount += 1
		print("%s: strict-V valleys=%d  zero-cross valleys=%d  (2.5s walk)" % [name, vcount, zcount])
	# 打印 L 脚前 60 帧曲线概览（每 3 帧）
	var s := ""
	for i in range(0, 60, 3):
		s += "%.3f " % out_l[i]
	print("L curve head: " + s)
	quit(0)
