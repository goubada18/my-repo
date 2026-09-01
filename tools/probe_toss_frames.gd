extends SceneTree
## 检查 Toss Grenade 在拉环段(5-37帧)与抛出段(38-48帧)的真实关键帧分布。
## 帧号 = 时间秒 × 30（Mixamo 30fps）。

func _init() -> void:
	var lib: AnimationLibrary = load("res://resources/mixamo_lib.tres") as AnimationLibrary
	if lib == null:
		printerr("FAIL: mixamo_lib")
		quit(1)
		return
	var toss: Animation = lib.get_animation("Toss Grenade") as Animation
	if toss == null:
		printerr("FAIL: Toss Grenade")
		quit(1)
		return
	print("Toss Grenade length=%.3f 轨道=%d" % [toss.length, toss.get_track_count()])
	var names := {}
	for ti in toss.get_track_count():
		if toss.track_get_type(ti) != Animation.TYPE_ROTATION_3D:
			continue
		var p := String(toss.track_get_path(ti))
		var bn := p.substr(p.rfind(":") + 1)
		if not (bn.contains("Shoulder") or bn.contains("Arm") or bn.contains("ForeArm")
				or bn.contains("Hand") or bn.contains("Spine") or bn.contains("Neck")
				or bn.contains("Head")):
			continue
		var frames: Array = []
		for k in range(toss.track_get_key_count(ti)):
			var t: float = toss.track_get_key_time(ti, k)
			if t >= 0.0 and t <= 2.0:
				frames.append(int(round(t * 30.0)))
		names[bn] = frames
	for bn in names.keys():
		print("%-22s 关键帧帧号: %s" % [bn, str(names[bn])])
	quit(0)
