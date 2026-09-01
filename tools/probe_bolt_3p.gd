extends SceneTree
## Verify 3P bolt lock via injected mock WeaponSystem (real code path).
func _init():
	var ps: PackedScene = load("res://scenes/player.tscn")
	var inst = ps.instantiate()
	root.add_child(inst)
	for i in range(20):
		await process_frame
	# 注入 mock WeaponSystem（M82 def 直接塞 current_def）
	var ws: Node = WeaponSystem.new()
	var def: Resource = load("res://resources/weapons/m82a1.tres")
	ws.current_def = def
	inst.set("_weapon_system", ws)
	var ok := true
	# 3P 模式
	inst.set("_fp_mode", false)
	inst.call("_cancel_scope")
	inst.set("_bolt_lock_timer", 0.0)
	# ① 3P 左键射击 → 应设拉栓锁
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	inst.call("_handle_fire_input", mb, true, false, false)
	var lock: float = float(inst.get("_bolt_lock_timer"))
	print("[1] 3P M82 射击后 _bolt_lock_timer=%.2f（应 1.85）" % lock)
	ok = ok and lock > 1.0
	# ② 拉栓中右键开镜 → 被拒
	var mb2 := InputEventMouseButton.new()
	mb2.button_index = MOUSE_BUTTON_RIGHT
	mb2.pressed = true
	inst.call("_handle_aim_input", mb2, true, false)
	var s1: bool = bool(inst.get("_scoping"))
	print("[2] 3P 拉栓中右键开镜 → _scoping=%s（应 false 被拒）" % str(s1))
	ok = ok and not s1
	# ③ 拉栓完 → 右键开镜恢复
	inst.set("_bolt_lock_timer", 0.0)
	inst.call("_handle_aim_input", mb2, true, false)
	var s2: bool = bool(inst.get("_scoping"))
	print("[3] 3P 拉栓完右键开镜 → _scoping=%s（应 true）" % str(s2))
	ok = ok and s2
	inst.call("_cancel_scope")
	print("=> %s" % ("ALL PASS (3P 拉栓锁落实)" if ok else "FAIL"))
	quit(0)
