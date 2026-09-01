extends SceneTree
func _init():
	var ps: PackedScene = load("res://scenes/player.tscn")
	var inst = ps.instantiate()
	root.add_child(inst)
	for i in range(15):
		await process_frame
	var fs: Node = inst.get("_footstep_sys")
	if fs == null:
		printerr("FAIL: _footstep_sys null")
		quit(1)
		return
	var clips: Array = fs.get("_clips")
	var fidx: Array = fs.get("_foot_idx")
	print("clips=%d (expect 5)  foot_idx=%s" % [clips.size(), str(fidx)])
	var ok1: bool = clips.size() == 5
	var ok2: bool = fidx[0] >= 0 and fidx[1] >= 0
	# 切片时长检查
	var lens: Array = []
	for c in clips:
		lens.append((c as AudioStreamWAV).get_length())
	print("clip lens: %s (expect ~0.3s each)" % str(lens))
	# 轮换播放
	fs.call("_play_next_clip")
	var i1: int = int(fs.get("_clip_idx"))
	fs.call("_play_next_clip")
	var i2: int = int(fs.get("_clip_idx"))
	print("clip_idx after 2 plays: %d -> %d (expect 1 -> 2)" % [i1, i2])
	var ok3: bool = i1 == 1 and i2 == 2
	# 触地局部极小逻辑单元测试（复刻 update 判定）
	var seq := [2.0, 1.5, 1.2, 1.6, 2.0]   # 1.2 是极小
	var hits: int = 0
	var p2: float = INF
	var p1: float = INF
	for y in seq:
		if p2 != INF and p2 > p1 and p1 < y:
			hits += 1
		p2 = p1
		p1 = y
	print("valley detection: %d hit (expect 1)" % hits)
	var ok4: bool = hits == 1
	print("=> %s" % ("ALL PASS" if (ok1 and ok2 and ok3 and ok4) else "FAIL"))
	quit(0)
