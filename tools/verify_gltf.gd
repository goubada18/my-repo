extends Node

func _ready() -> void:
	print("\n========== M82A1 viewmodel 导入验证 ==========")
	var path := "res://fp_viewmodel/m82a1_viewmodel.gltf"
	var state := GLTFState.new()
	var doc := GLTFDocument.new()
	var err := doc.append_from_file(path, state)
	if err != OK:
		push_error("glTF 解析失败 (%d): %s" % [err, path])
		get_tree().quit(1)
		return
	print("网格: %d  材质: %d  骨骼节点: %d  动画: %d" % [len(state.meshes), len(state.materials), len(state.skeletons), len(state.animations)])
	if len(state.animations) > 0:
		for i in range(len(state.animations)):
			var anim = state.animations[i]
			print("  anim[%d] name=%s tracks=%d length=%.2fs" % [i, anim.resource_name, anim.get_track_count(), anim.length])
	var scene := doc.generate_scene(state)
	scene.name = "M82ViewModel"
	add_child(scene)
	var meshes: Array = scene.find_children("*", "MeshInstance3D", true, false)
	var skels: Array = scene.find_children("*", "Skeleton3D", true, false)
	var ap: AnimationPlayer = scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
	print("实例化: MeshInstance3D=%d Skeleton3D=%d AnimationPlayer=%s" % [meshes.size(), skels.size(), ap != null])
	if ap != null:
		print("动画列表: %s" % str(ap.get_animation_list()))
	print("========== 验证完成 ==========")
	get_tree().quit(0)
