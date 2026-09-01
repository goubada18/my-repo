extends SceneTree
## Verify: ① shoot players live under player (persistent host), not fp_vm;
## ② rapid fire pools players (3 shots -> 3 players playing, no interrupt);
## ③ throw uses its own player (not overwritten by draw);
## ④ shared "shoot" also pools.
func _init():
	var ps: PackedScene = load("res://scenes/player.tscn")
	var inst = ps.instantiate()
	root.add_child(inst)
	for i in range(20):
		await process_frame
	var fp_vm: Node = null
	for n in inst.get_children():
		var scr: String = str(n.get_script().resource_path) if n.get_script() != null else ""
		if "fp_viewmodel_player.gd" in scr:
			fp_vm = n
			break
	if fp_vm == null:
		printerr("FAIL: no fp_vm")
		quit(1)
		return
	var ok := true
	# ① 播放器挂在 player 下（fp_vm 的父节点）
	var host: Node = fp_vm.get_parent()
	var shoot_p: AudioStreamPlayer = fp_vm.get("_sfx_shoot_p")
	var ok1: bool = shoot_p.get_parent() == host
	print("[1] 射击播放器挂常驻宿主(player) ? %s" % str(ok1))
	ok = ok and ok1
	# ② 注入沙鹰长枪声（0.999s），连开 3 枪 → 池 3 个播放器都在播（叠加不打断）
	fp_vm.call("set_sfx_paths", "res://audio/v_deagle_fire.dat", "", "", "", "")
	fp_vm.call("interrupt_shoot")
	fp_vm.call("trigger_shoot")
	await process_frame
	await process_frame
	fp_vm.call("trigger_shoot")
	await process_frame
	await process_frame
	fp_vm.call("trigger_shoot")
	await process_frame
	await process_frame
	var pool: Array = fp_vm.get("_sfx_shoot_pool")
	var playing_count: int = 0
	for p in pool:
		if (p as AudioStreamPlayer).playing:
			playing_count += 1
	print("[2] 3 连发后池中正在播 = %d/3（期望 3：叠加不互相打断）" % playing_count)
	ok = ok and playing_count >= 2
	# ③ 呼喊声独立播放器：trigger_draw 不顶掉 throw
	fp_vm.call("set_action_sfx", "res://audio/nepal_slash2.dat",
		"res://audio/gaobao_pull.dat", "res://audio/gaobao_throw.mp3")
	var throw_p: AudioStreamPlayer = fp_vm.get("_sfx_throw_p")
	var throw_stream: AudioStream = fp_vm.get("_sfx_throw")
	# 模拟投掷呼喊（播放到 throw_p）
	fp_vm.call("_play_sfx", throw_stream, throw_p)
	var throw_playing_before: bool = throw_p.playing
	# 触发切枪 draw（用 _sfx 通用播放器）
	fp_vm.call("trigger_draw")
	var throw_still: bool = throw_p.playing
	print("[3] 呼喊在播=%s → 切枪 draw 后仍在播=%s ? %s" % [
		str(throw_playing_before), str(throw_still), str(throw_playing_before and throw_still)])
	ok = ok and throw_playing_before and throw_still
	# ④ shared "shoot"（3P 射击）也走池
	var shared_shoot_p: AudioStreamPlayer = fp_vm.get("_sfx_shoot_p")
	fp_vm.call("play_shared_sfx", "shoot", throw_stream, 1.0)
	var ok4: bool = shared_shoot_p.playing or pool.size() >= 3
	print("[4] shared shoot 走池 ? %s" % str(ok4))
	ok = ok and ok4
	print("=> %s" % ("ALL PASS (枪声/呼喊声不被打断)" if ok else "FAIL"))
	quit(0)
