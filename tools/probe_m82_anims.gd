extends SceneTree
## Dump M82 FP viewmodel animation durations (and compare with AK default viewmodel).
func _init():
	for path in ["res://fp_viewmodel/m82a1_viewmodel.gltf", "res://fp_viewmodel/ak47_viewmodel.gltf"]:
		var ps: PackedScene = load(path)
		if ps == null:
			print("== %s: LOAD FAIL" % path.get_file())
			continue
		var inst = ps.instantiate()
		root.add_child(inst)
		await process_frame
		var ap: AnimationPlayer = null
		for n in inst.find_children("*", "AnimationPlayer", true, false):
			ap = n as AnimationPlayer
			break
		print("== %s ==" % path.get_file())
		if ap == null:
			print("   no AnimationPlayer")
		else:
			var names: Array = ap.get_animation_list()
			names.sort()
			for a in names:
				var anim: Animation = ap.get_animation(a)
				if anim != null:
					print("   %-18s %6.3f s" % [a, anim.length])
		inst.queue_free()
		await process_frame
	quit(0)
