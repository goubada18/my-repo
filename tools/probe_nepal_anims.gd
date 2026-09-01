extends SceneTree
func _init():
	var ps: PackedScene = load("res://fp_viewmodel/nepal/nepal_kukri_viewmodel.gltf")
	if ps == null:
		printerr("FAIL load")
		quit(1)
		return
	var inst = ps.instantiate()
	root.add_child(inst)
	await process_frame
	var ap: AnimationPlayer = null
	for n in inst.find_children("*", "AnimationPlayer", true, false):
		ap = n as AnimationPlayer
		break
	if ap == null:
		print("no AP")
		quit(1)
		return
	for a in ap.get_animation_list():
		var anim: Animation = ap.get_animation(a)
		if anim != null:
			print("%-14s len=%.3f" % [a, anim.length])
	quit(0)
