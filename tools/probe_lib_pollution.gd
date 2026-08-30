extends SceneTree
## 回归探针：标定场景不得污染共享动画库（mixamo_lib / mixamo_lib_swat）。
## 机制复现：同进程内资源缓存共享——加载两库并快照 "Rifle Aiming Idle" 的轨道，
## 实例化标定场景（feihu→swat）后重读同一资源对象，任何变化=污染复发。
func _init():
	var feihu: AnimationLibrary = load("res://resources/mixamo_lib.tres")
	var swat: AnimationLibrary = load("res://resources/mixamo_lib_swat.tres")
	var snap := _snapshot(feihu)
	var snap_s := _snapshot(swat)

	var ps = load("res://scenes/nepal_knife_calib.tscn")
	var node = ps.instantiate()
	root.add_child(node)
	for i in range(30):
		await process_frame
	node.character_id = "swat"
	for i in range(30):
		await process_frame

	var after := _snapshot(feihu)
	var after_s := _snapshot(swat)
	var dirty := []
	if snap.size() != after.size():
		dirty.append("feihu轨道数 %d→%d" % [snap.size(), after.size()])
	for k in snap:
		if str(snap[k]) != str(after.get(k, "<缺失>")):
			dirty.append("feihu:" + k)
	if snap_s.size() != after_s.size():
		dirty.append("swat轨道数 %d→%d" % [snap_s.size(), after_s.size()])
	for k in snap_s:
		if str(snap_s[k]) != str(after_s.get(k, "<缺失>")):
			dirty.append("swat:" + k)
	if dirty.is_empty():
		print("PROBE_OK>>> 共享动画库零污染（轨道数与关键值未变）")
		quit(0)
	else:
		print("PROBE_FAIL>>> 共享库被污染: ", str(dirty))
		quit(1)

func _snapshot(lib: AnimationLibrary) -> Dictionary:
	var out := {}
	for n in lib.get_animation_list():
		var a: Animation = lib.get_animation(n)
		out[n + "/轨道数"] = a.get_track_count()
		# 记录一条手臂轨道首值（如存在）
		for i in a.get_track_count():
			if a.track_get_type(i) == Animation.TYPE_ROTATION_3D \
					and String(a.track_get_path(i)).contains("RightArm"):
				out[n + "/RightArm首值"] = str(a.track_get_key_value(i, 0))
				break
	return out
