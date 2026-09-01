extends SceneTree
func _init():
	for p in ["res://fp_viewmodel/fp_view_preview.tscn",
			"res://fp_viewmodel/fp_idle.tscn",
			"res://fp_viewmodel/fp_shoot1.tscn"]:
		var ps: PackedScene = load(p)
		if ps == null:
			printerr("FAIL: 无法加载 " + p)
			quit(1)
			return
		var inst = ps.instantiate()
		root.add_child(inst)
		await process_frame
		print("OK  %s  实例化成功，脚本=%s" % [p.get_file(), str(inst.get_script().resource_path if inst.get_script() != null else "null")])
		inst.queue_free()
		await process_frame
	print("验证完成")
	quit(0)
