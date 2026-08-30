extends SceneTree
## sync_swat_anim_lib.gd —— SWAT 动画库校验/再生成工具（"换皮不换骨"数据同步链固化）
##
## 背景：飞虎队 mixamo_lib.tres 是动画数据【唯一事实源】；SWAT 的 mixamo_lib_swat.tres
## 是 2026-08-14 换皮时生成的衍生库。经逐轨道诊断（tools/probe_lib_pair.gd），两库实测关系：
##   旋转层：两库【同源】——除 Hips(根骨)前乘 90°X 外全部恒等（651/651 轨道全键拟合通过）
##   位置层：SWAT 是按自身体型的【独立导出】——逐骨骼各自不同的缩放比(0.0098~0.0261)
##           + 部分骨骼位置随时间变化的真差异（约 31 轨道/动画），非机械变换可表达
##   例外：Rifle Aiming Idle 两库完全相同——2026-08-28 日志记载的跨库复制事故（量化确认）
## 因此本工具不做全局模型假设，采用【逐轨道变换解算 + 全键一致性验证】：
##
##   校准：对每个共有动画的每对同名轨道，从数据直接解出变换——
##     位置 = (帧旋转 R, 均匀缩放 s)；旋转 = 恒等 / 前乘 qX / 后乘 qX / 共轭 qX 四模型择优；
##     然后用该轨道【全部关键帧】验证解出的变换（最大误差入报告）。
##   判定：轨道变换全键自洽 → 可同步；不自洽 → 独立数据（再生成时保留 SWAT 侧）。
##   再生成（--write）：旋转层全同步 + 可同步位置轨道按变换重建 + 其余保留 SWAT 原值；
##     写前自动备份 .bak（已被 .gitignore 覆盖）；飞虎库只读，绝不修改。
##
## 用法：
##   godot --headless --path . --script res://tools/sync_swat_anim_lib.gd              # 校验
##   godot --headless --path . --script res://tools/sync_swat_anim_lib.gd -- --write   # 再生成
##
## 容差：.tres 为 float32 存储，重算有固有抖动（实测 ~0.04°）；阈值为"关系=纯变换"判据。

const SRC_PATH := "res://resources/mixamo_lib.tres"
const DST_PATH := "res://resources/mixamo_lib_swat.tres"
const EPS_POS_REL := 2e-3      # 位置相对误差阈
const EPS_ROT_DEG := 0.2       # 旋转角误差阈（度）
const EPS_QCONSIST_DEG := 0.5  # pre/post 模型 qX 逐键一致性阈（度）
const EPS_PARALLEL_DEG := 5.0  # 解算旋转帧时"非平行"第二向量的最小夹角（度）

func _init() -> void:
	var write_mode: bool = OS.get_cmdline_user_args().has("--write")
	var src: AnimationLibrary = load(SRC_PATH) as AnimationLibrary
	var dst: AnimationLibrary = load(DST_PATH) as AnimationLibrary
	if src == null or dst == null:
		printerr("SYNC_FAIL>>> 无法加载动画库")
		quit(1)
		return
	var common: Array = []
	for n in src.get_animation_list():
		if dst.has_animation(n):
			common.append(n)
		else:
			print("SYNC: 仅飞虎库有: %s" % n)
	for n in dst.get_animation_list():
		if not src.has_animation(n):
			print("SYNC: 仅 SWAT 库有: %s" % n)
	print("SYNC: 共有动画 %d 个" % common.size())
	if common.is_empty():
		printerr("SYNC_FAIL>>> 两库无同名动画")
		quit(1)
		return

	# ---- 逐动画校准 ----
	var ok_anims: Array = []
	var diverged: Array = []
	var model_stat := {}
	for n in common:
		var r := _calibrate_animation(src.get_animation(n), dst.get_animation(n), n)
		for k in r.stat:
			model_stat[k] = model_stat.get(k, 0) + r.stat[k]
		if r.ok:
			ok_anims.append(n)
			print("SYNC: [可同步] %s（%s）" % [n, r.summary])
		else:
			diverged.append(n)
			print("SYNC: [发散] %s（%s）" % [n, r.summary])
	print("SYNC: 汇总 可同步 %d / 发散 %d；逐轨道变换模型统计 %s" % [
		ok_anims.size(), diverged.size(), str(model_stat)])
	if not diverged.is_empty():
		print("SYNC: 发散动画=两库关系被手改/污染（如 Rifle Aiming Idle 跨库复制事故），再生成时保留现存 SWAT 版")

	if write_mode:
		_write_lib(src, dst, common)
	elif diverged.is_empty():
		print("SYNC_VERIFY_PASS>>> 两库关系为纯逐轨道变换，可安全再生成")
	else:
		print("SYNC_VERIFY_NOTE>>> %d 个动画含独立数据。实测结构：旋转层两库同源(恒等/Hips前乘90°X)可机械同步；位置层为 SWAT 按自身体型的独立导出(逐骨比例+时变差异)，仅恒定比例轨道可同步。--write 将同步旋转层与可同步位置轨道，其余保留 SWAT 原值" % diverged.size())
	quit(0)

# ================= 逐动画校准 =================
## 返回 {ok: bool, summary: String, tracks: [{i, j, kind, transform, ok}]}
## transform 结构：{type:"pos", s: float, q: Quaternion} / {type:"rot", model:"id|pre|post|conj", q: Quaternion}
func _calibrate_animation(a: Animation, b: Animation, anim_name: String) -> Dictionary:
	var tracks: Array = []
	var ok := true
	var stat := {}
	var missing := 0
	for i in a.get_track_count():
		var t: int = a.track_get_type(i)
		var path := String(a.track_get_path(i))
		var j := _find_track(b, t, path)
		if j < 0:
			missing += 1
			ok = false
			tracks.append({"i": i, "j": -1, "kind": "missing", "ok": false})
			continue
		var kc: int = a.track_get_key_count(i)
		if kc != b.track_get_key_count(j):
			# 关键帧数不一致：逐键变换模型失效
			ok = false
			tracks.append({"i": i, "j": j, "kind": "keycount", "ok": false})
			stat["keycount不一致"] = stat.get("keycount不一致", 0) + 1
			continue
		if kc == 0:
			tracks.append({"i": i, "j": j, "kind": "empty", "ok": true})
			continue
		if t == Animation.TYPE_POSITION_3D:
			var r := _solve_pos_track(a, i, b, j)
			stat[r.stat_key] = stat.get(r.stat_key, 0) + 1
			if not r.ok:
				ok = false
			tracks.append({"i": i, "j": j, "kind": "pos", "transform": r, "ok": r.ok})
		elif t == Animation.TYPE_ROTATION_3D:
			var r2 := _solve_rot_track(a, i, b, j)
			stat[r2.stat_key] = stat.get(r2.stat_key, 0) + 1
			if not r2.ok:
				ok = false
			tracks.append({"i": i, "j": j, "kind": "rot", "transform": r2, "ok": r2.ok})
		else:
			# VALUE/METHOD 等其它轨道：要求逐键完全一致
			var same := true
			for k in kc:
				if a.track_get_key_time(i, k) != b.track_get_key_time(j, k) \
						or a.track_get_key_value(i, k) != b.track_get_key_value(j, k):
					same = false
					break
			var key2 := "其它轨道一致" if same else "其它轨道不一致"
			stat[key2] = stat.get(key2, 0) + 1
			if not same:
				ok = false
			tracks.append({"i": i, "j": j, "kind": "verbatim", "ok": same})
	var failed_names: Array = []
	for t in tracks:
		if not t.ok and t.kind != "missing" and t.kind != "keycount":
			var p := String(a.track_get_path(t.i))
			var bone: String = p.substr(p.rfind(":") + 1)
			var err_s := "?"
			if t.has("transform"):
				err_s = str(t.transform.max_err)
			failed_names.append("%s(%s err=%s)" % [bone, t.kind, err_s])
	var pos_ok := 0
	var pos_keep := 0
	var rot_ok := 0
	for t in tracks:
		if t.kind == "pos":
			if t.ok:
				pos_ok += 1
			else:
				pos_keep += 1
		elif t.kind == "rot" and t.ok:
			rot_ok += 1
	var summary := "轨道%d 条%s%s 旋转可同步%d 位置可同步%d/独立%d 失败轨道: %s" % [
		a.get_track_count(),
		" 缺失%d" % missing if missing > 0 else "",
		"" if ok else "",
		rot_ok, pos_ok, pos_keep,
		str(failed_names) if not failed_names.is_empty() else "无"]
	return {"ok": ok, "summary": summary, "tracks": tracks, "stat": stat}

## 位置轨道：解 s 与帧旋转 R（两条非平行向量构造正交基直接解，全键验证）。
func _solve_pos_track(a: Animation, i: int, b: Animation, j: int) -> Dictionary:
	var kc: int = a.track_get_key_count(i)
	# 比率中位数
	var ratios: Array = []
	for k in kc:
		var va: Vector3 = a.track_get_key_value(i, k)
		var vb: Vector3 = b.track_get_key_value(j, k)
		if va.length() > 1e-6 and vb.length() > 1e-6:
			ratios.append(vb.length() / va.length())
	if ratios.is_empty():
		return {"ok": false, "stat_key": "pos无有效样本", "s": -1.0, "q": Quaternion.IDENTITY, "max_err": -1.0}
	var s: float = _median(ratios)
	# 帧旋转解算：取第一条向量 + 第一条与之夹角 > EPS_PARALLEL 的向量
	var qR := Quaternion.IDENTITY
	var solved := false
	var base_a: Vector3
	var base_ap: Vector3
	var base_b: Vector3
	var base_bp: Vector3
	for x in kc:
		var vax: Vector3 = a.track_get_key_value(i, x)
		var vbx: Vector3 = b.track_get_key_value(j, x)
		if vax.length() <= 1e-6 or vbx.length() <= 1e-6:
			continue
		if not solved:
			base_a = vax.normalized()
			base_ap = vbx.normalized()
			solved = true
			continue
		var bx: Vector3 = vax.normalized()
		if rad_to_deg(bx.angle_to(base_a)) < EPS_PARALLEL_DEG:
			continue
		base_b = bx
		base_bp = vbx.normalized()
		solved = true
		break
	if solved and base_b != Vector3.ZERO:
		var c: Vector3 = base_a.cross(base_b)
		var cp: Vector3 = base_ap.cross(base_bp)
		if c.length() > 1e-6 and cp.length() > 1e-6:
			var m_src := Basis(base_a, base_b, c.normalized())
			var m_dst := Basis(base_ap, base_bp, cp.normalized())
			qR = (m_dst * m_src.inverse()).get_rotation_quaternion()
	# 全键验证
	var max_err := 0.0
	for k in kc:
		var va: Vector3 = a.track_get_key_value(i, k)
		var vb: Vector3 = b.track_get_key_value(j, k)
		var vt: Vector3 = (Basis(qR) * va) * s
		if vb.length() > 1e-6:
			max_err = maxf(max_err, (vt - vb).length() / vb.length())
		else:
			max_err = maxf(max_err, vt.length())
	var key := "pos(s=%.4f,%s)" % [s, "R=" + _qkey(qR) if solved else "R=退化"]
	return {"ok": max_err <= EPS_POS_REL, "stat_key": key, "s": s, "q": qR, "max_err": max_err}

## 旋转轨道：四模型择优（恒等/前乘/后乘/共轭），全键验证。
func _solve_rot_track(a: Animation, i: int, b: Animation, j: int) -> Dictionary:
	var kc: int = a.track_get_key_count(i)
	var best := {"model": "none", "q": Quaternion.IDENTITY, "max_err": INF, "stat_key": "rot无解"}
	# 模型1：恒等
	var err_id := 0.0
	for k in kc:
		err_id = maxf(err_id, rad_to_deg((a.track_get_key_value(i, k) as Quaternion).angle_to(b.track_get_key_value(j, k) as Quaternion)))
	best = {"model": "id", "q": Quaternion.IDENTITY, "max_err": err_id, "stat_key": "rot(恒等)"}
	# 模型2/3：前乘/后乘 qX（qX 逐键解出后须恒定）
	for model in ["pre", "post"]:
		var q_first: Quaternion
		var consistent := true
		var prev := Quaternion.IDENTITY
		for k in kc:
			var qa: Quaternion = a.track_get_key_value(i, k)
			var qb: Quaternion = b.track_get_key_value(j, k)
			var qx: Quaternion = qb * qa.inverse() if model == "pre" else qa.inverse() * qb
			if k == 0:
				q_first = qx
				prev = qx
				continue
			if rad_to_deg(qx.angle_to(prev)) > EPS_QCONSIST_DEG:
				consistent = false
				break
			prev = qx
		if not consistent:
			continue
		var err := 0.0
		for k in kc:
			var qa: Quaternion = a.track_get_key_value(i, k)
			var qb: Quaternion = b.track_get_key_value(j, k)
			var pred: Quaternion = q_first * qa if model == "pre" else qa * q_first
			err = maxf(err, rad_to_deg(pred.angle_to(qb)))
		if err < best.max_err:
			best = {"model": model, "q": q_first, "max_err": err,
				"stat_key": "rot(%s %s %.1f°)" % [model, _qkey(q_first), rad_to_deg(q_first.get_angle())]}
	# 模型4：共轭（轴随帧旋转、角度不变）——仅当逐键角度一致时可能成立
	var angle_consistent := true
	for k in kc:
		var qa: Quaternion = a.track_get_key_value(i, k)
		var qb: Quaternion = b.track_get_key_value(j, k)
		if absf(rad_to_deg(qa.get_angle()) - rad_to_deg(qb.get_angle())) > EPS_QCONSIST_DEG:
			angle_consistent = false
			break
	if angle_consistent:
		var qR: Variant = _solve_frame_from_axes(a, i, b, j)
		if qR != null:
			var err2 := 0.0
			for k in kc:
				var qa: Quaternion = a.track_get_key_value(i, k)
				var qb: Quaternion = b.track_get_key_value(j, k)
				var pred: Quaternion = qR * qa * qR.inverse()
				err2 = maxf(err2, rad_to_deg(pred.angle_to(qb)))
			if err2 < best.max_err:
				best = {"model": "conj", "q": qR, "max_err": err2,
					"stat_key": "rot(conj %s %.1f°)" % [_qkey(qR), rad_to_deg(qR.get_angle())]}
	best.ok = best.max_err <= EPS_ROT_DEG
	return best

## 由一条旋转轨道的逐键轴对样本解帧旋转 qR（两条非平行轴构造正交基）。
func _solve_frame_from_axes(a: Animation, i: int, b: Animation, j: int) -> Variant:
	var base_a: Vector3
	var base_ap: Vector3
	var base_b: Vector3
	var base_bp: Vector3
	var got_first := false
	var kc: int = a.track_get_key_count(i)
	for k in kc:
		var qa: Quaternion = a.track_get_key_value(i, k)
		var qb: Quaternion = b.track_get_key_value(j, k)
		if qa.get_angle() < 0.05 or qb.get_angle() < 0.05:
			continue
		var ax: Vector3 = qa.get_axis()
		var bx: Vector3 = qb.get_axis()
		if not got_first:
			base_a = ax
			base_ap = bx
			got_first = true
			continue
		if rad_to_deg(ax.angle_to(base_a)) < EPS_PARALLEL_DEG:
			continue
		base_b = ax
		base_bp = bx
		var c: Vector3 = base_a.cross(base_b)
		var cp: Vector3 = base_ap.cross(base_bp)
		if c.length() < 1e-6 or cp.length() < 1e-6:
			return null
		var m_src := Basis(base_a, base_b, c.normalized())
		var m_dst := Basis(base_ap, base_bp, cp.normalized())
		return (m_dst * m_src.inverse()).get_rotation_quaternion()
	return null

# ================= 再生成写入 =================
## 逐轨道同步策略（基于两库真实结构的实测结论）：
##   旋转轨道：两库同源（恒等 / Hips 前乘 90°X，651/651 全键拟合通过）→ 一律按模型同步飞虎数据
##   位置轨道：SWAT 为按自身体型的独立导出 → 仅"恒定变换关系"轨道按变换同步，
##     时变差异轨道保留 SWAT 原值（防机械同步破坏 SWAT 动画）
##   其它轨道：一致→同步飞虎；不一致→保留 SWAT
##   SWAT 独有动画：原样保留
func _write_lib(src: AnimationLibrary, dst: AnimationLibrary, common: Array) -> void:
	# ① 备份（.bak 已被 .gitignore 覆盖，不入库）
	var backup := DST_PATH + ".bak"
	var da := DirAccess.open("res://")
	if da != null:
		var err := da.copy(DST_PATH.replace("res://", ""), backup.replace("res://", ""))
		print("SYNC: 备份 %s → %s (err=%d)" % [DST_PATH, backup, err])
	# ② 预校准（基于原始 dst 数据）+ 留存原 SWAT 动画引用
	var calib := {}
	for n in common:
		calib[n] = _calibrate_animation(src.get_animation(n), dst.get_animation(n), n)
	var old_swat := {}
	for n in dst.get_animation_list():
		old_swat[n] = dst.get_animation(n)
	# ③ 清空重建
	var stat := {"rot_sync": 0, "pos_sync": 0, "pos_keep": 0, "verbatim_sync": 0,
		"verbatim_keep": 0, "skip": 0, "swat_only": 0}
	for n in old_swat:
		dst.remove_animation(n)
	for n in old_swat:
		if not src.has_animation(n):
			dst.add_animation(n, old_swat[n])   # SWAT 独有动画原样保留
			stat.swat_only += 1
	for n in src.get_animation_list():
		var a: Animation = src.get_animation(n)
		var old_b: Animation = old_swat.get(n)
		var out := Animation.new()
		out.length = a.length
		out.loop_mode = a.loop_mode
		out.step = a.step
		out.resource_name = a.resource_name
		var tlist: Array = calib[n].tracks
		for t in tlist:
			var i: int = t.i
			var tp: int = a.track_get_type(i)
			var path: NodePath = a.track_get_path(i)
			if t.kind == "missing" or t.kind == "keycount" or t.kind == "empty":
				stat.skip += 1
				continue
			var use_feihu: bool = t.ok
			if t.kind == "rot":
				use_feihu = true   # 旋转层两库同源（651/651 拟合通过），一律同步
			if use_feihu:
				# imported 标志沿用现存 SWAT 轨道（保持原库语义）
				var imported: bool = old_b.track_is_imported(t.j) if (old_b != null and t.j >= 0) else a.track_is_imported(i)
				var ni := out.add_track(tp)
				out.track_set_path(ni, path)
				out.track_set_imported(ni, imported)
				out.track_set_interpolation_type(ni, a.track_get_interpolation_type(i))
				for k in a.track_get_key_count(i):
					var kt: float = a.track_get_key_time(i, k)
					var v: Variant = a.track_get_key_value(i, k)
					var tr: float = a.track_get_key_transition(i, k)
					if tp == Animation.TYPE_POSITION_3D and t.kind == "pos":
						var tf: Dictionary = t.transform
						v = (Basis(tf.q) * (v as Vector3)) * tf.s
					elif tp == Animation.TYPE_ROTATION_3D and t.kind == "rot":
						var tf2: Dictionary = t.transform
						var qa: Quaternion = v
						match tf2.model:
							"pre":
								v = tf2.q * qa
							"post":
								v = qa * tf2.q
							"conj":
								v = tf2.q * qa * tf2.q.inverse()
							_:
								v = qa
					out.track_insert_key(ni, kt, v, tr)
				if t.kind == "rot":
					stat.rot_sync += 1
				elif t.kind == "pos":
					stat.pos_sync += 1
				else:
					stat.verbatim_sync += 1
			else:
				# 保留 SWAT 原轨道（位置时变差异等独立数据，不机械同步）
				if old_b == null:
					stat.skip += 1
					continue
				var j: int = t.j
				var ni2 := out.add_track(tp)
				out.track_set_path(ni2, path)
				out.track_set_imported(ni2, old_b.track_is_imported(j))
				out.track_set_interpolation_type(ni2, old_b.track_get_interpolation_type(j))
				for k in old_b.track_get_key_count(j):
					out.track_insert_key(ni2, old_b.track_get_key_time(j, k),
						old_b.track_get_key_value(j, k), old_b.track_get_key_transition(j, k))
				if t.kind == "pos":
					stat.pos_keep += 1
				else:
					stat.verbatim_keep += 1
		dst.add_animation(n, out)
	print("SYNC: 轨道统计 旋转同步=%d 位置同步=%d 位置保留SWAT=%d 其它同步=%d 其它保留=%d 跳过=%d SWAT独有动画=%d" % [
		stat.rot_sync, stat.pos_sync, stat.pos_keep, stat.verbatim_sync, stat.verbatim_keep, stat.skip, stat.swat_only])
	var err2 := ResourceSaver.save(dst, DST_PATH)
	if err2 != OK:
		printerr("SYNC_FAIL>>> 保存失败 err=%d" % err2)
		quit(1)
		return
	print("SYNC_WRITE_DONE>>> 已覆盖 %s（备份在同目录 .bak）——请在编辑器实机目检 SWAT 后再提交" % DST_PATH)

# ================= 小工具 =================
func _find_track(anim: Animation, type: int, path: String) -> int:
	for i in anim.get_track_count():
		if anim.track_get_type(i) == type and String(anim.track_get_path(i)) == path:
			return i
	return -1

func _median(arr: Array) -> float:
	if arr.is_empty():
		return -1.0
	var s := arr.duplicate()
	s.sort()
	return s[s.size() / 2]

## 四元数量化为字典键（用于统计聚合）
func _qkey(q: Quaternion) -> String:
	return "(%.2f,%.2f,%.2f|%.0f°)" % [q.get_axis().x, q.get_axis().y, q.get_axis().z, rad_to_deg(q.get_angle())]
