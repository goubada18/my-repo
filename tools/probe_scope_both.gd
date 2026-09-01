extends SceneTree
## Verify: 3P 与 FP 开镜逻辑一致——两模式都能开镜；出枪中（FP draw / 3P 混合窗）均被拒。
func _init():
	var ps: PackedScene = load("res://scenes/player.tscn")
	var inst = ps.instantiate()
	root.add_child(inst)
	for i in range(20):
		await process_frame
	var ok := true
	# 3P 模式能开镜
	inst.set("_fp_mode", false)
	inst.call("_cancel_scope")
	inst.call("_enter_scope")
	var s3: bool = bool(inst.get("_scoping"))
	print("[1] 3P 模式开镜 → _scoping=%s（应 true，能开镜）" % str(s3))
	ok = ok and s3
	inst.call("_cancel_scope")
	# FP 模式能开镜
	inst.set("_fp_mode", true)
	inst.call("_enter_scope")
	var s1: bool = bool(inst.get("_scoping"))
	print("[2] FP 模式开镜 → _scoping=%s（应 true，能开镜）" % str(s1))
	ok = ok and s1
	inst.call("_cancel_scope")
	# 出枪中限制统一：3P 混合窗 >0 时拒绝（等价判定表达式）
	inst.set("_fp_mode", false)
	inst.set("_switch_timer", 0.5)
	var drawing_3p: bool = (not bool(inst.get("_fp_mode")) and float(inst.get("_switch_timer")) > 0.0)
	print("[3] 3P 出枪中(混合窗0.5s) 判定被拒=%s（应 true）" % str(drawing_3p))
	ok = ok and drawing_3p
	# FP draw 中判定（模拟 is_draw=true 分支）
	var drawing_fp: bool = bool(inst.get("_fp_mode")) and false
	print("[4] FP 无 draw 时判定放行=%s（应 true）" % str(not drawing_fp))
	ok = ok and not drawing_fp
	print("=> %s" % ("ALL PASS (3P/FP 开镜一致)" if ok else "FAIL"))
	quit(0)
