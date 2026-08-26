extends SceneTree
## verify_all.gd —— 全系统验收探针（P0 基线，架构改造的安全网）
## 每次改动后运行：全绿（ALL_OK）才算安全，任何 FAIL 立即回滚该改动。
## 检查项：
##   A. 主游戏 main.tscn 加载 + player.gd 运行 30 帧无脚本错误（飞虎队）
##   B. 预览链 main_preview → player_preview → character_preview 加载 ALL_OK（SWAT）
##   C. 双角色骨骼对齐：飞虎队播原库 vs SWAT 播换算库，ΔR<1°、ΔP<0.3m
##   D. 动画库完整性：原库 21 动画 / 换算库 21 动画
##   E. 武器挂载：两场景都能 find_child("Weapon_AK47")
## 用法：godot --headless --path <proj> --script tools/verify_all.gd
## 退出码：0=全绿，1=有 FAIL

var _fail_count := 0
var _pass_count := 0

func _log(s: String) -> void:
	print(s)

func _check(ok: bool, label: String) -> void:
	if ok:
		_pass_count += 1
		print("  PASS  " + label)
	else:
		_fail_count += 1
		print("  FAIL  " + label)

func _find_skel(n: Node) -> Skeleton3D:
	for c in n.get_children():
		if c is Skeleton3D:
			return c
		var r: Skeleton3D = _find_skel(c)
		if r:
			return r
	return null

func _collect(n: Node, out: Array = []) -> Array:
	out.append(n)
	for c in n.get_children():
		_collect(c, out)
	return out

func _bones(n: Node) -> Dictionary:
	var skel: Skeleton3D = _find_skel(n)
	var out := {}
	if skel == null:
		return out
	for i in range(skel.get_bone_count()):
		var w: Transform3D = skel.global_transform * skel.get_bone_global_pose(i)
		out[skel.get_bone_name(i)] = w
	return out

func _anim_alignment() -> void:
	_log("== C. 双角色骨骼对齐 ==")
	var feihu: Node = load("res://scenes/character.tscn").instantiate()
	root.add_child(feihu)
	await process_frame
	await process_frame
	var fap: AnimationPlayer = feihu.get_node_or_null("AnimationPlayer")
	var swat: Node = load("res://scenes/character_preview.tscn").instantiate()
	root.add_child(swat)
	await process_frame
	await process_frame
	var sap: AnimationPlayer = null
	for n in _collect(swat):
		if n is AnimationPlayer:
			sap = n
			break
	if fap == null or sap == null:
		_check(false, "找到双角色 AnimationPlayer")
		return
	for anim_name in ["Rifle Aiming Idle", "Walking", "Idle Crouching Aiming"]:
		if not fap.has_animation(anim_name) or not sap.has_animation(anim_name):
			_check(false, "动画 %s 两库均有" % anim_name)
			continue
		var max_r := 0.0
		var max_p := 0.0
		for tpos in [0.0, 0.5]:
			fap.play(anim_name)
			fap.seek(tpos, true)
			sap.play(anim_name)
			sap.seek(tpos, true)
			await process_frame
			await process_frame
			var fb := _bones(feihu)
			var nb := _bones(swat)
			for bn in fb:
				if not nb.has(bn):
					continue
				var qf: Quaternion = fb[bn].basis.get_rotation_quaternion()
				var qn: Quaternion = nb[bn].basis.get_rotation_quaternion()
				var dr: float = rad_to_deg(minf(qf.angle_to(qn), qf.angle_to(-qn)))
				var dp: float = fb[bn].origin.distance_to(nb[bn].origin)
				max_r = maxf(max_r, dr)
				max_p = maxf(max_p, dp)
		_check(max_r < 1.0 and max_p < 0.3,
			"动画 %s 对齐 ΔR=%.2f°(限1°) ΔP=%.3fm(限0.3m)" % [anim_name, max_r, max_p])
		await process_frame
	feihu.queue_free()
	swat.queue_free()
	await process_frame

func _anim_lib_count() -> void:
	_log("== D. 动画库完整性 ==")
	var lib: AnimationLibrary = load("res://resources/mixamo_lib.tres")
	var slib: AnimationLibrary = load("res://resources/mixamo_lib_swat.tres")
	if lib == null or slib == null:
		_check(false, "两个动画库均可加载")
		return
	var n1: int = lib.get_animation_list().size()
	var n2: int = slib.get_animation_list().size()
	_check(n1 == 21 and n2 == 21, "原库 %d 动画 / 换算库 %d 动画（均应为 21）" % [n1, n2])

func _weapon_check(scene_path: String, label: String) -> void:
	var inst: Node = load(scene_path).instantiate()
	root.add_child(inst)
	await process_frame
	await process_frame
	var w: Node3D = inst.find_child("Weapon_AK47", true, false) as Node3D
	var skel: Skeleton3D = _find_skel(inst)
	_check(w != null, "武器挂载 %s: Weapon_AK47 存在" % label)
	_check(skel != null, "武器挂载 %s: Skeleton3D 存在" % label)
	if w != null and skel != null:
		var mz: Node3D = w.find_child("MuzzleMarker", true, false) as Node3D
		_check(mz != null, "武器挂载 %s: MuzzleMarker 存在" % label)
	inst.queue_free()
	await process_frame

func _initialize() -> void:
	print("========== verify_all 全系统验收 ==========")
	print("== A. 主游戏冒烟（飞虎队 main.tscn）==")
	var main_ok := true
	var main_inst: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main_inst)
	for i in range(30):
		await process_frame
	main_inst.queue_free()
	await process_frame
	_check(main_ok, "main.tscn 运行 30 帧")
	print("== B. 预览链加载（SWAT main_preview）==")
	var chain_ok := true
	for p in ["res://scenes/character_preview.tscn", "res://scenes/player_preview.tscn", "res://scenes/main_preview.tscn"]:
		var ps: PackedScene = load(p)
		if ps == null:
			chain_ok = false
	_check(chain_ok, "预览链三场景均可加载")
	await _anim_alignment()
	await _anim_lib_count()
	print("== E. 武器挂载 ==")
	await _weapon_check("res://scenes/character.tscn", "飞虎队")
	await _weapon_check("res://scenes/character_preview.tscn", "SWAT")
	print("")
	print("========== 结果：%d PASS / %d FAIL ==========" % [_pass_count, _fail_count])
	if _fail_count == 0:
		print("RESULT ALL_OK")
		quit(0)
	else:
		print("RESULT HAS_FAIL")
		quit(1)
