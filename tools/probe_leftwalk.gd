extends SceneTree
## 验证蹲左走动画 pos 是否跳段（区分手雷特有 vs 状态机通用）。

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var ps := load("res://scenes/main_multichar.tscn") as PackedScene
	var scene = ps.instantiate()
	get_root().add_child(scene)
	await process_frame
	await process_frame
	var player = scene.get_node_or_null("Player")
	if player == null:
		for c in scene.get_children():
			if c is CharacterBody3D:
				player = c
				break
	await process_frame
	var ap: AnimationPlayer = player.anim_player
	# 切手雷（有持雷合成）后蹲左走
	player._switch_to_weapon(player._weapon_system.select_by_id("gaobao"))
	await process_frame
	player._change_state(8)   # CROUCH_STRAFE_LEFT
	player._play_animation(8, true, 1.0)
	var seq := []
	for f in range(80):
		ap.advance(1.0 / 60.0)
		seq.append(ap.current_animation_position)
	var prev: float = seq[0]
	var jumps := 0
	for i in range(1, seq.size()):
		var d: float = seq[i] - prev
		if d > 0.05:
			jumps += 1
			print("[%d] pos %.3f -> %.3f  跳变 +%.3f" % [i, prev, seq[i], d])
		prev = seq[i]
	var sample := ""
	for i in range(0, seq.size(), 5):
		sample += "%.2f " % seq[i]
	print("手雷蹲左走 pos 序列: " + sample)
	print("跳变次数: %d" % jumps)
	quit(0)
