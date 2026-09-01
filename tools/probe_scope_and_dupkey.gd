extends SceneTree
## Verify: ① 3P 模式 _enter_scope 不生效（狙击枪开镜仅 FP）；
## ② 数字键重复按当前武器 → _switch_to_weapon 直接忽略（不重装）。
## 加载 main.tscn（含 CharacterManager/WeaponSystem 真实链路）。
func _init():
	var ps: PackedScene = load("res://scenes/main.tscn")
	if ps == null:
		printerr("FAIL: main.tscn 加载失败")
		quit(1)
		return
	var inst = ps.instantiate()
	root.add_child(inst)
	for i in range(30):
		await process_frame
	# 找到 player
	var player: Node = null
	for n in inst.find_children("*", "CharacterBody3D", true, false):
		player = n
		break
	if player == null:
		printerr("FAIL: 无玩家节点")
		quit(1)
		return
	var ok := true
	# ① 3P 模式开镜被拒
	player.set("_fp_mode", false)
	player.call("_cancel_scope")
	player.call("_enter_scope")
	var scoping_3p: bool = bool(player.get("_scoping"))
	print("[1] 3P 模式 _enter_scope → _scoping=%s（应 false，禁止开镜）" % str(scoping_3p))
	ok = ok and not scoping_3p
	# FP 模式开镜正常
	player.set("_fp_mode", true)
	player.call("_enter_scope")
	var scoping_fp: bool = bool(player.get("_scoping"))
	print("[2] FP 模式 _enter_scope → _scoping=%s（应 true，开镜生效）" % str(scoping_fp))
	ok = ok and scoping_fp
	player.call("_cancel_scope")
	# ② 数字键重复按当前武器：_switch_to_weapon 忽略（不重装）
	var ws: Node = player.get("_weapon_system")
	var cur: Resource = ws.get_current_weapon() if ws != null else null
	var applied_before: String = String(player.get("_applied_weapon_id"))
	if cur != null:
		player.call("_switch_to_weapon", cur)   # 重复按当前武器
		var applied_after: String = String(player.get("_applied_weapon_id"))
		var ok2: bool = applied_before == applied_after
		print("[3] 重复按当前武器(%s) → _applied_weapon_id 未变=%s（无反应）" % [cur.get("id"), str(ok2)])
		ok = ok and ok2
	else:
		print("[3] 无武器系统，跳过")
	ok = ok and (cur != null)
	print("=> %s" % ("ALL PASS" if ok else "FAIL"))
	quit(0)
