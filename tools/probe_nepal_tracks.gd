extends SceneTree
## Dump track paths of midslash1 vs midslash2 (nepal viewmodel) to find
## model-root translation tracks that shift the gun off the calibrated pose.
func _init():
	var ps: PackedScene = load("res://fp_viewmodel/nepal/nepal_kukri_viewmodel.gltf")
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
	for an in ["midslash1", "midslash2", "draw", "stab"]:
		var anim: Animation = ap.get_animation(an)
		if anim == null:
			print("%s: missing" % an)
			continue
		print("== %s len=%.3f tracks=%d ==" % [an, anim.length, anim.get_track_count()])
		for t in range(anim.get_track_count()):
			var sp := str(anim.track_get_path(t))
			var tt: String = str(anim.track_get_type(t))
			print("   %-55s type=%s keys=%d" % [sp, tt, anim.track_get_key_count(t)])
	quit(0)
