extends SceneTree
## grenade_toss_kit.gd —— 从 Mixamo "Toss Grenade" 全身动画裁剪手雷 3P 手臂动画
## 用户方案（2026-09-01）：取原版扔手雷动画，只取 拉环 5-37 帧 / 抛出 38-48 帧（30fps），
## 只裁剪上半身（8 臂骨 + 5 躯干骨旋转轨道，观感好），加速匹配第一人称时长
## （FP plugin 拉环 0.6444s / Throw 投掷 0.2250s），待机复用尼泊尔手臂姿势
## （nepal3p/nepal_idle_arms.tres），两个衔接处（待机→拉环、抛出→待机）用 slerp
## 关键帧做丝滑过渡。
##
## 用法: godot --headless --path . --script res://tools/grenade_toss_kit.gd
## 输出: resources/animations/grenade3p/grenade_pull_arms.tres（过渡0.12s+拉环0.6444s）
##       grenade_hold_arms.tres（= 尼泊尔手臂姿态，待机）
##       grenade_throw_arms.tres（抛出0.225s+过渡0.12s回待机）

const LIB_PATH := "res://resources/mixamo_lib.tres"
const ANIM_NAME := "Toss Grenade"
const HOLD_SRC := "res://resources/animations/nepal3p/nepal_idle_arms.tres"
const OUT_DIR := "res://resources/animations/grenade3p/"

const FPS := 30.0
const PULL_F1 := 5      # 拉环起始帧
const PULL_F2 := 46     # 拉环结束帧（用户 2026-09-01：45+1 再延，看效果）
const THROW_F1 := 47    # 抛出起始帧（随拉环顺延，避免重叠）
const THROW_F2 := 57    # 抛出结束帧
const FP_PULL_DUR := 0.6444    # FP plugin 拉环时长
const FP_THROW_DUR := 0.2250   # FP Throw 投掷时长
const BLEND_LEAD := 0.12       # 待机→拉环 过渡时长（秒）
const BLEND_TAIL := 0.12       # 抛出→待机 过渡时长（秒）
const THROW_LEAD := 0.08       # 拉环末帧(46)→抛出首帧(47) 过渡时长（消除投掷瞬间跳变）
const BLEND_STEPS := 5         # 过渡段关键帧段数（越密越丝滑）
# 抬臂角：烘焙进全部 tres（Shoulder 骨左乘），运行时待机合成与直驱都用同一份数据，
# 消除"待机(抬臂22°)↔直驱(不抬臂)"切换跳变。与尼泊尔 NEPAL_ARM_LIFT_DEG 一致。
const ARM_LIFT_DEG := 22.0

# 只 8 臂骨（躯干交回状态机动画！躯干直驱成常量会与蹲过渡/蹲走动画冲突 →
# 站蹲过渡上半身晃动、蹲左走磕头，历轮实测；状态机动画躯干天然垂直不后仰，
# 拉环/投掷末帧后仰问题由"源动画只取手臂段"规避）
const UPPER_BONES := [
	"LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
	"RightShoulder", "RightArm", "RightForeArm", "RightHand",
]
# 常量骨（已弃用：躯干交回状态机，不烘焙进 tres）
const TRUNK_BONES := []

func _init() -> void:
	_build()
	quit(0)

func _bone_of(p: String) -> String:
	var idx := p.rfind(":")
	if idx < 0:
		return ""
	return p.substr(idx + 1).replace("mixamorig_", "")

## 插值采样（Godot 4 无 track_sample，本地实现）
func _sample_toss(a: Animation, ti: int, t: float) -> Quaternion:
	var kc := a.track_get_key_count(ti)
	if kc == 0:
		return Quaternion.IDENTITY
	if t <= a.track_get_key_time(ti, 0):
		return a.track_get_key_value(ti, 0)
	for k in range(kc - 1):
		var t0: float = a.track_get_key_time(ti, k)
		var t1: float = a.track_get_key_time(ti, k + 1)
		if t >= t0 and t <= t1:
			var d := t1 - t0
			if d < 0.0001:
				return a.track_get_key_value(ti, k)
			var w := (t - t0) / d
			var q0: Quaternion = a.track_get_key_value(ti, k)
			var q1: Quaternion = a.track_get_key_value(ti, k + 1)
			return q0.slerp(q1, w)
	return a.track_get_key_value(ti, kc - 1)

## 抬臂烘焙：全部 Shoulder 骨关键帧左乘 22° 抬臂
func _apply_lift(a: Animation) -> void:
	var lift := Quaternion(Vector3(1.0, 0.0, 0.0), deg_to_rad(-ARM_LIFT_DEG))
	for ti in a.get_track_count():
		if a.track_get_type(ti) != Animation.TYPE_ROTATION_3D:
			continue
		if not String(a.track_get_path(ti)).contains("Shoulder"):
			continue
		for k in range(a.track_get_key_count(ti)):
			var q: Quaternion = a.track_get_key_value(ti, k)
			a.track_set_key_value(ti, k, lift * q)

## 拉环 2 关键帧版（用户 2026-09-01：Toss 拉环段动作太多，只取 待机→拉环末帧 两个关键帧，
## 时长 = FP plugin 0.6444s）：起点=待机姿态（与运行时持雷待机完全一致，无跳变）、
## 终点=拉环末帧（46 帧姿态，躯干垂直）；躯干全程待机垂直。
func _build_pull_simple(toss: Animation, hold_q: Dictionary) -> Animation:
	var pull := Animation.new()
	pull.length = FP_PULL_DUR
	pull.loop_mode = Animation.LOOP_NONE
	var t_end := PULL_F2 / FPS
	for b in UPPER_BONES:
		var q_end := Quaternion.IDENTITY
		var path := ""
		for ti in toss.get_track_count():
			if toss.track_get_type(ti) != Animation.TYPE_ROTATION_3D:
				continue
			var p := String(toss.track_get_path(ti))
			if p.contains(b):
				q_end = _sample_toss(toss, ti, t_end)
				path = p
				break
		if path == "":
			printerr("FAIL: 骨骼 %s 在 Toss Grenade 无轨道" % b)
			quit(1)
			return pull
		var q0: Quaternion = hold_q.get(b, Quaternion.IDENTITY)
		if TRUNK_BONES.has(b):
			q_end = hold_q.get(b, Quaternion.IDENTITY)   # 躯干全程待机垂直
		var nt := pull.add_track(Animation.TYPE_ROTATION_3D)
		pull.track_set_path(nt, path)
		pull.track_set_interpolation_type(nt, Animation.INTERPOLATION_LINEAR)
		pull.track_insert_key(nt, 0.0, q0)
		pull.track_insert_key(nt, FP_PULL_DUR, q_end)
	return pull

## 从源动画提取指定骨骼的 rotation_3d 轨道（时间区间裁剪 + 时间缩放 + 值替换）
## src: 源 Animation；bones: 要提取的骨骼名；t_from/t_to: 源时间区间；
## scale_k: 时间缩放系数；t0: 目标起始时间偏移
## out: 输出 Animation（调用方创建）；hold_q: 骨骼->四元数 待机姿态（过渡起点）
## blend_before: 是否在动作前插入 hold→首帧 过渡；blend_after: 是否在动作后插入 末帧→hold 过渡
## blend_len_before/blend_len_after: 前后过渡时长
## trunk_const: 躯干骨（Spine/Neck/Head）是否回正为待机垂直常量（拉环用 true——
## Toss Grenade 拉环末帧躯干后仰，用户反馈奇怪；投掷用 false 保留发力姿态）
func _extract(src: Animation, out: Animation, t_from: float, t_to: float,
		scale_k: float, t0: float, hold_q: Dictionary,
		blend_before: bool, blend_after: bool,
		blend_len_before: float, blend_len_after: float,
		trunk_const: bool = false) -> void:
	# 骨骼 -> 源轨道索引
	var track_of := {}
	for ti in src.get_track_count():
		if src.track_get_type(ti) != Animation.TYPE_ROTATION_3D:
			continue
		var b := _bone_of(String(src.track_get_path(ti)))
		if b != "" and UPPER_BONES.has(b):
			track_of[b] = ti
	var missing := []
	for b in UPPER_BONES:
		if not track_of.has(b):
			missing.append(b)
	if not missing.is_empty():
		printerr("FAIL: 源动画缺骨骼轨道: " + ", ".join(missing))
		quit(1)
		return
	# 每骨：采集源区间关键帧
	var seg_dur := (t_to - t_from) * scale_k   # 加速后的动作段时长
	for b in UPPER_BONES:
		var si: int = track_of[b]
		var nt := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(nt, src.track_get_path(si))
		out.track_set_interpolation_type(nt, Animation.INTERPOLATION_LINEAR)
		# 躯干回正：整轨写待机垂直常量（首尾同值），跳过动作/过渡逻辑
		if trunk_const and TRUNK_BONES.has(b):
			var qv: Quaternion = hold_q.get(b, Quaternion.IDENTITY)
			out.track_insert_key(nt, 0.0, qv)
			if out.length > 0.001:
				out.track_insert_key(nt, out.length, qv)
			continue
		var q_hold: Quaternion = hold_q.get(b, Quaternion.IDENTITY)
		var q_first := Quaternion.IDENTITY
		var q_last := Quaternion.IDENTITY
		var kc := src.track_get_key_count(si)
		var times: Array = []
		var quats: Array = []
		for k in range(kc):
			var t: float = src.track_get_key_time(si, k)
			if t < t_from - 0.001 or t > t_to + 0.001:
				continue
			var q: Quaternion = src.track_get_key_value(si, k)
			times.append(t)
			quats.append(q)
		if times.is_empty():
			printerr("FAIL: 骨骼 %s 在 [%.3f,%.3f] 无关键帧" % [b, t_from, t_to])
			quit(1)
			return
		q_first = quats[0]
		q_last = quats[quats.size() - 1]
		# 过渡段（前）：hold → 首帧 slerp（跳过最后一个关键帧，避免与动作首帧时间碰撞）
		if blend_before:
			for i in range(BLEND_STEPS):
				var s: float = smoothstep(0.0, 1.0, float(i) / BLEND_STEPS)
				var tt := blend_len_before * float(i) / BLEND_STEPS
				out.track_insert_key(nt, tt, q_hold.slerp(q_first, s))
		# 动作段：时间缩放
		for i in range(times.size()):
			var tt: float = t0 + (times[i] - t_from) * scale_k
			out.track_insert_key(nt, tt, quats[i])
		# 过渡段（后）：末帧 → hold slerp（从 i=1 开始，避免与动作末帧时间碰撞）
		if blend_after:
			var seg_end: float = t0 + seg_dur
			for i in range(1, BLEND_STEPS + 1):
				var s: float = smoothstep(0.0, 1.0, float(i) / BLEND_STEPS)
				var tt := seg_end + blend_len_after * float(i) / BLEND_STEPS
				out.track_insert_key(nt, tt, q_last.slerp(q_hold, s))

func _build() -> void:
	var lib: AnimationLibrary = load(LIB_PATH) as AnimationLibrary
	if lib == null:
		printerr("FAIL: 加载 " + LIB_PATH)
		quit(1)
		return
	var toss: Animation = lib.get_animation(ANIM_NAME) as Animation
	if toss == null:
		printerr("FAIL: 库中无 " + ANIM_NAME)
		quit(1)
		return
	var hold_src: Animation = load(HOLD_SRC) as Animation
	if hold_src == null:
		printerr("FAIL: 加载 " + HOLD_SRC)
		quit(1)
		return
	print("Toss Grenade: length=%.3f 轨道=%d" % [toss.length, toss.get_track_count()])

	# 待机姿态（hold）：8 臂骨 = 尼泊尔手臂姿势（用户指定，勿改！）；
	# 躯干骨 = 待机动画首帧值（过渡起点一致性）
	var hold_q := {}
	for ti in hold_src.get_track_count():
		if hold_src.track_get_type(ti) != Animation.TYPE_ROTATION_3D:
			continue
		var b := _bone_of(String(hold_src.track_get_path(ti)))
		if b != "":
			hold_q[b] = hold_src.track_get_key_value(ti, 0)
	var idle: Animation = lib.get_animation("Rifle Aiming Idle") as Animation
	if idle == null:
		printerr("WARN: 库中无 Rifle Aiming Idle，躯干过渡起点退化为 identity")
	else:
		for ti in idle.get_track_count():
			if idle.track_get_type(ti) != Animation.TYPE_ROTATION_3D:
				continue
			var b := _bone_of(String(idle.track_get_path(ti)))
			if b != "" and UPPER_BONES.has(b) and not hold_q.has(b):
				hold_q[b] = idle.track_get_key_value(ti, 0)
	# 【Hips 不烘焙】Mixamo 动画 Hips 旋转是"角色朝向"的一部分（Rifle Aiming Idle 的
	# Hips ≈108.8°），写死会躺平/偏航；运行时锁定拉环开始时的实际 Hips 值（player.gd）。
	if hold_q.has("Hips"):
		hold_q.erase("Hips")

	# 时间区间（30fps）
	var t_pull_from := PULL_F1 / FPS
	var t_pull_to := PULL_F2 / FPS
	var t_throw_from := THROW_F1 / FPS
	var t_throw_to := THROW_F2 / FPS
	var pull_k := FP_PULL_DUR / (t_pull_to - t_pull_from)
	var throw_k := FP_THROW_DUR / (t_throw_to - t_throw_from)
	print("拉环段 %.3f..%.3fs (%.3f s -> %.3f s, k=%.4f)  抛出段 %.3f..%.3fs (%.3f -> %.3f, k=%.4f)" % [
		t_pull_from, t_pull_to, t_pull_to - t_pull_from, FP_PULL_DUR, pull_k,
		t_throw_from, t_throw_to, t_throw_to - t_throw_from, FP_THROW_DUR, throw_k])

	# 拉环：2 关键帧（待机→拉环末帧46帧），时长 = FP_PULL_DUR（对齐 FP，无前置过渡）
	var pull := _build_pull_simple(toss, hold_q)
	print("拉环: length=%.3f 轨道=%d" % [pull.length, pull.get_track_count()])

	# 抛出：前过渡0.08s(拉环末帧46→抛出首帧47，消除投掷瞬间跳变) + 动作(0.225s) + 尾过渡0.12s 回待机
	# 躯干也回正（trunk_const=true）：拉环/投掷躯干都垂直 → 衔接无缝无抽搐（用户反馈
	# 拉环到抛出瞬间躯干猛甩）
	var throw_anim := Animation.new()
	throw_anim.length = THROW_LEAD + FP_THROW_DUR + BLEND_TAIL
	throw_anim.loop_mode = Animation.LOOP_NONE
	_extract(toss, throw_anim, t_throw_from, t_throw_to, throw_k, THROW_LEAD, hold_q, true, true, THROW_LEAD, BLEND_TAIL, true)
	print("抛出: length=%.3f 轨道=%d" % [throw_anim.length, throw_anim.get_track_count()])

	# 待机 = 尼泊尔手臂姿态（独立副本，用户指定）
	var hold := Animation.new()
	hold.length = 0.0166667
	hold.loop_mode = Animation.LOOP_LINEAR
	for ti in hold_src.get_track_count():
		if hold_src.track_get_type(ti) != Animation.TYPE_ROTATION_3D:
			continue
		var nt := hold.add_track(Animation.TYPE_ROTATION_3D)
		hold.track_set_path(nt, hold_src.track_get_path(ti))
		hold.track_set_interpolation_type(nt, Animation.INTERPOLATION_LINEAR)
		hold.track_insert_key(nt, 0.0, hold_src.track_get_key_value(ti, 0))
	print("待机: length=%.4f 轨道=%d" % [hold.length, hold.get_track_count()])

	# 【抬臂烘焙】三个动画的 Shoulder 全部左乘 22°，运行时不再单独抬臂（消除待机↔直驱跳变）
	_apply_lift(pull)
	_apply_lift(throw_anim)
	_apply_lift(hold)

	# 保存
	DirAccess.make_dir_recursive_absolute(OUT_DIR.replace("res://", "C:/Users/93343/Desktop/demo/"))
	var err := ResourceSaver.save(pull, OUT_DIR + "grenade_pull_arms.tres")
	print("SAVE grenade_pull_arms.tres err=%d" % err)
	err = ResourceSaver.save(hold, OUT_DIR + "grenade_hold_arms.tres")
	print("SAVE grenade_hold_arms.tres err=%d" % err)
	err = ResourceSaver.save(throw_anim, OUT_DIR + "grenade_throw_arms.tres")
	print("SAVE grenade_throw_arms.tres err=%d" % err)
	print("BUILD_DONE>>> 三 tres 就绪，下一步接入手雷运行时")
