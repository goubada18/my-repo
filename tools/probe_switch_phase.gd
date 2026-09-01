extends SceneTree
## 验证"切武器保腿相位"的 seek 恢复机制：
## 模拟 走路动画 → (换装) stop → 重播 → seek(原位置) 后，播放位置应无缝衔接。
func _init():
	var ps = load("res://scenes/character.tscn")
	var inst = ps.instantiate()
	root.add_child(inst)
	for i in range(6):
		await process_frame
	var ap: AnimationPlayer = null
	for n in inst.find_children("*", "AnimationPlayer", true, false):
		ap = n as AnimationPlayer
		break
	if ap == null:
		printerr("FAIL: 无 AnimationPlayer")
		quit(1)
		return
	# 动态挂载动画库（角色场景由脚本挂载，headless 探针自己挂）
	var lib: AnimationLibrary = load("res://resources/mixamo_lib.tres") as AnimationLibrary
	if lib != null and not ap.has_animation_library(""):
		ap.add_animation_library("", lib)
	if not ap.has_animation("Walking"):
		printerr("FAIL: 无 Walking 动画")
		quit(1)
		return
	ap.play("Walking")
	for i in range(30):
		await process_frame   # 让动画跑起来
	var p0: float = ap.current_animation_position
	print("走路动画位置 = %.3f / %.3f" % [p0, ap.current_animation_length])
	# 模拟换装打断：stop → 重播 → seek 回原位置（_restart_stance_animation 新逻辑）
	ap.stop()
	var pos_after_stop: float = ap.current_animation_position
	ap.play("Walking")
	ap.seek(p0, true)
	await process_frame
	var p1: float = ap.current_animation_position
	var drift: float = absf(p1 - p0)
	print("stop 后位置保留 = %.3f（%.1f%% 相位）" % [pos_after_stop, pos_after_stop / p0 * 100.0])
	print("重播+seek 后位置 = %.3f  漂移 = %.4f  → %s" % [
		p1, drift,
		"✅ 相位无缝衔接（腿不会跳变）" if drift < 0.05 else "❌ 位置漂移，仍会卡顿"])
	quit(0)
