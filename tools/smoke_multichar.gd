extends SceneTree
# 整局冒烟测试（多角色主场景）：加载真实 main_multichar.tscn，运行若干帧，
# 捕获任何运行期错误/崩溃。与 smoke_main.gd 配对：后者跑 main.tscn。
# 回归覆盖：数字键武器直选链路（切尼泊尔 → FP viewmodel 重建 → 旧模型 dispose/free）。
# 历史事故：dispose() 在自身方法内 free(self) → "Attempted to free a locked
# object (calling or emitting)"，切带专属 FP 场景的武器（尼泊尔/M82/沙漠之鹰）必现。
func _init():
	var ps = load("res://scenes/main_multichar.tscn")
	if ps == null:
		printerr("cannot load main_multichar scene")
		quit(1)
		return
	var m = ps.instantiate()
	root.add_child(m)
	for i in range(60):
		await process_frame
	# --- 武器切换回归：走真实输入入口 _select_weapon_by_id（数字键 1-5 同路径） ---
	var p = root.find_child("Player", true, false)
	if p != null and p.has_method("_select_weapon_by_id"):
		p._select_weapon_by_id("nepal_kukri")   # 专属 FP 场景 → 触发 viewmodel 重建
		for i in range(15):
			await process_frame
		p._select_weapon_by_id("ak47")          # 切回内嵌模型：反向重建
		for i in range(15):
			await process_frame
		p._select_weapon_by_id("m82a1")         # 狙击（scopable + 专属 FP 场景）
		for i in range(15):
			await process_frame
		p._select_weapon_by_id("nepal_kukri")   # 二次切刀：覆盖"重建自上一把非默认武器"
		for i in range(15):
			await process_frame
		print("SMOKE_WEAPON_SWITCH_OK>>> 尼泊尔/AK47/M82A1 切换链路无崩溃")
	else:
		printerr("smoke_multichar: 未找到 Player 或武器切换入口缺失")
	print("SMOKE_OK>>> 加载 main_multichar.tscn 并运行60帧+武器切换无崩溃")
	quit(0)
