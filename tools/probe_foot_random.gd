extends SceneTree
## Verify random clip selection (no sequential pattern, no immediate repeat).
func _init():
	var ps: PackedScene = load("res://scenes/player.tscn")
	var inst = ps.instantiate()
	root.add_child(inst)
	for i in range(15):
		await process_frame
	var fs: Node = null
	for n in inst.get_children():
		var scr: String = str(n.get_script().resource_path) if n.get_script() != null else ""
		if "footstep_system.gd" in scr:
			fs = n
			break
	if fs == null:
		printerr("FAIL: no footstep system")
		quit(1)
		return
	var seq: Array = []
	for k in range(20):
		fs.call("_play_next_clip")
		seq.append(int(fs.get("_clip_idx")))
	print("播放序列: %s" % str(seq))
	var sequential: bool = true
	var repeat: bool = false
	for i in range(1, seq.size()):
		if seq[i] != (seq[i-1] + 1) % 5:
			sequential = false
		if seq[i] == seq[i-1]:
			repeat = true
	var uniq: Array = []
	for v in seq:
		if not uniq.has(v):
			uniq.append(v)
	print("非顺序=%s  无相邻重复=%s  覆盖切片=%d/5" % [str(not sequential), str(not repeat), uniq.size()])
	var ok: bool = (not sequential) and (not repeat) and uniq.size() >= 4
	print("=> %s" % ("ALL PASS (随机播放)" if ok else "FAIL"))
	quit(0)
