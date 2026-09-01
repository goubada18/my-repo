extends SceneTree
## Verify quickswitch bolt-accelerate: switch away during bolt lock -> mark;
## switch back to bolt weapon -> lock = BOLT_LOCK/1.4 (40% faster).
func _init():
	var ps: PackedScene = load("res://scenes/player.tscn")
	var inst = ps.instantiate()
	root.add_child(inst)
	for i in range(20):
		await process_frame
	var m82: Resource = load("res://resources/weapons/m82a1.tres")
	var ak: Resource = load("res://resources/weapons/ak47.tres")
	var ws: Node = WeaponSystem.new()
	ws.current_def = m82
	inst.set("_weapon_system", ws)
	var ok := true
	# 拉栓中（锁 1.85）
	inst.set("_bolt_lock_timer", 1.85)
	inst.set("_bolt_quickswitch", false)
	# ① 拉栓中切走（→AK）：锁清零 + 标记 true
	ws.current_def = ak
	inst.call("_do_switch_weapon", ak)
	var qs1: bool = bool(inst.get("_bolt_quickswitch"))
	var lock1: float = float(inst.get("_bolt_lock_timer"))
	print("[1] 拉栓中切走 → 标记=%s 锁=%.2f（应 true / 0）" % [str(qs1), lock1])
	ok = ok and qs1 and lock1 == 0.0
	# ② 切回 M82：拉栓提速 40%（1.85/1.4≈1.32）
	ws.current_def = m82
	inst.call("_do_switch_weapon", m82)
	var qs2: bool = bool(inst.get("_bolt_quickswitch"))
	var lock2: float = float(inst.get("_bolt_lock_timer"))
	var expect: float = 1.85 / 2.0
	print("[2] 切回 M82 → 标记=%s 锁=%.3f（应 false / %.3f）" % [str(qs2), lock2, expect])
	ok = ok and not qs2 and absf(lock2 - expect) < 0.02
	# ③ 拉栓跑完后再切非 bolt（→AK）：锁 0 + 标记清
	inst.set("_bolt_lock_timer", 0.0)   # 拉栓已完
	ws.current_def = ak
	inst.call("_do_switch_weapon", ak)
	var qs3: bool = bool(inst.get("_bolt_quickswitch"))
	var lock3: float = float(inst.get("_bolt_lock_timer"))
	print("[3] 切回 AK → 标记=%s 锁=%.2f（应 false / 0）" % [str(qs3), lock3])
	ok = ok and not qs3 and lock3 == 0.0
	print("=> %s" % ("ALL PASS (切枪加速拉栓技巧)" if ok else "FAIL"))
	quit(0)
