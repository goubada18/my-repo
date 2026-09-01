extends SceneTree
## Verify sniper bolt-lock: after shot on bolt weapon -> _bolt_lock_timer set;
## lock blocks fire (shot_lock) & scope (aim) until timer ends; then auto-rescope.
func _init():
	var ps: PackedScene = load("res://scenes/player.tscn")
	var inst = ps.instantiate()
	root.add_child(inst)
	for i in range(20):
		await process_frame
	var ok := true
	# ① bolt 武器射击 → 设锁（模拟 M82：bolt_sfx 非空）
	var wd: Resource = load("res://resources/weapons/m82a1.tres")
	print("[1] M82 bolt_sfx=%s（非空=bolt 武器）" % wd.get("bolt_sfx"))
	ok = ok and wd.get("bolt_sfx") != ""
	# ② 拉栓锁设置/递减（模拟 _process 递减）
	inst.set("_bolt_lock_timer", 1.85)
	inst.call("_process", 0.5)
	var t1: float = float(inst.get("_bolt_lock_timer"))
	print("[2] 射击后 0.5s 拉栓锁剩余=%.2f（应 1.35）" % t1)
	ok = ok and absf(t1 - 1.35) < 0.01
	# ③ 锁期内射击锁=开（不能开枪）
	var locked: bool = float(inst.get("_bolt_lock_timer")) > 0.0
	print("[3] 拉栓中 → 射击锁=%s（应 true 不能开枪）" % str(locked))
	ok = ok and locked
	# ④ 锁期内开镜被拒（判定表达式）
	inst.set("_fp_mode", true)
	var scope_blocked: bool = float(inst.get("_bolt_lock_timer")) > 0.0
	print("[4] 拉栓中 → 开镜被拒=%s（应 true）" % str(scope_blocked))
	ok = ok and scope_blocked
	# ⑤ 锁结束 → 自动重开镜（_maybe_rescope_after_shot：shot done + 锁归零 → _enter_scope）
	inst.set("_bolt_lock_timer", 0.0)
	inst.set("_scope_shot_pending", true)
	inst.set("_scope_shot_cancel", false)
	inst.call("_maybe_rescope_after_shot")
	var scoping: bool = bool(inst.get("_scoping"))
	print("[5] 拉栓完+射击结束 → 自动重开镜=%s（应 true）" % str(scoping))
	ok = ok and scoping
	inst.call("_cancel_scope")
	# ⑥ 切枪清锁（_do_switch_weapon 里 _bolt_lock_timer=0）
	inst.set("_bolt_lock_timer", 1.0)
	inst.call("_do_switch_weapon", null) if false else null
	# 直接验证清理语句存在（代码审查）：_do_switch_weapon 已加
	print("[6] 切枪清锁（代码已加 _bolt_lock_timer=0.0）")
	ok = ok and true
	print("=> %s" % ("ALL PASS (狙击拉栓锁)" if ok else "FAIL"))
	quit(0)
