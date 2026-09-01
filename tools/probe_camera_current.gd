extends SceneTree
## 验证：player_preview.tscn（含 SWAT 角色）加载后 current 相机唯一（CameraPivot 的）。
func _init():
	var ps = load("res://scenes/player_preview.tscn")
	var inst = ps.instantiate()
	root.add_child(inst)
	for i in range(8):
		await process_frame
	var cams := []
	for n in inst.find_children("*", "Camera3D", true, true):
		var c := n as Camera3D
		cams.append("%s [current=%s]" % [n.get_path(), str(c.current)])
	print("相机列表:")
	for c in cams:
		print("  ", c)
	var cur: int = 0
	for n in inst.find_children("*", "Camera3D", true, true):
		if (n as Camera3D).current:
			cur += 1
	print("current 相机数 = %d → %s" % [cur, "✅ 唯一（玩家相机）" if cur == 1 else "❌ 仍有冲突"])
	quit(0)
