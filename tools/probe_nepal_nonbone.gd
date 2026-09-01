extends SceneTree
## Find NON-skeleton tracks (model-root/Armature transform) in nepal slash anims.
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
		quit(1)
		return
	for an in ["midslash1", "midslash2"]:
		var anim: Animation = ap.get_animation(an)
		print("== %s ==" % an)
		var any_nonbone: bool = false
		for t in range(anim.get_track_count()):
			var sp := str(anim.track_get_path(t))
			if not sp.contains("Skeleton3D:"):
				any_nonbone = true
				print("   NON-BONE: %s type=%d keys=%d" % [sp, anim.track_get_type(t), anim.track_get_key_count(t)])
		if not any_nonbone:
			print("   (all tracks are skeleton bones)")
	quit(0)
