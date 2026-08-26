extends SceneTree
## 冒烟：实例化 player_preview.tscn（含 player.gd），跑 40 帧，抓脚本报错 + 骨骼状态。

var _errors: PackedStringArray = PackedStringArray()

func _init() -> void:
	pass

func _error_handler(msg: String, _callstack: Array, _error: int) -> void:
	_errors.append(msg)

func _collect(n: Node, out: Array = []) -> Array:
	out.append(n)
	for c in n.get_children():
		_collect(c, out)
	return out

func _initialize() -> void:
	# 挂错误捕获
	for i in range(10):
		var c = 0
		c += 1
	# 用 Godot 的全局错误打印即可（脚本错误会打到 stdout）
	var inst: Node = load("res://scenes/player_preview.tscn").instantiate()
	root.add_child(inst)
	var frames := 0
	while frames < 40 and not _check_quit():
		await process_frame
		frames += 1
	# 采样骨骼
	var skel: Skeleton3D = null
	for n in _collect(inst):
		if n is Skeleton3D:
			skel = n
			break
	if skel:
		var ymin := 1e9
		var ymax := -1e9
		for i in skel.get_bone_count():
			var w: Vector3 = skel.global_transform * skel.get_bone_global_pose(i).origin
			if w.y < ymin: ymin = w.y
			if w.y > ymax: ymax = w.y
		print("SMOKE 骨骼 Y[%.2f..%.2f] h=%.2f" % [ymin, ymax, ymax - ymin])
		var ap: AnimationPlayer = null
		for n in _collect(inst):
			if n is AnimationPlayer:
				ap = n
				break
		if ap:
			print("SMOKE AnimationPlayer 当前动画=%s 正在播放=%s" % [ap.current_animation, ap.is_playing()])
	print("SMOKE 帧数=%d" % frames)
	print("SMOKE DONE")
	inst.queue_free()
	quit(0)

func _check_quit() -> bool:
	return false
