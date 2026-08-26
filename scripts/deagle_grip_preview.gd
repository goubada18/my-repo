@tool
extends Node
# ============================================================================
# deagle_grip_preview.gd — 手枪握持校准场景控制（挂在 deagle_rig_preview.tscn 根）。
# 编辑器内：合成「手枪待机双臂 + swat Rifle Aiming Idle 其余」并钉到第 0 帧。
# 合成逻辑与实机 player.gd `_pistol_combine()` **完全一致**（ARMS_BONES 双臂裁剪 +
# 整周期长度 + LOOP_LINEAR），保证标注场景的持枪姿势 = 游戏里 3P 手枪待机姿势（所见即所得）。
# 为什么合成而不是直接播 pistol_idle：pistol_idle 的 Hips 轨道是 Blender 坐标系
# （相对带 R_x90 的 rest），直接播 → Hips 被转 80°+ → 角色躺倒/腿拉长；
# 下半身用 swat 库（Hips 已按项目坐标系换算）→ 角色正常站立。
# 运行时(@tool 关闭)此脚本不干预任何逻辑。
# ============================================================================
const PISTOL_ANIM := preload("res://resources/animations/pistol_idle_swat.tres")
const ANIM_NAME := "pistol_rig"
# 独立"preview"库中的完整播放路径（AnimationPlayer.play 需带库前缀；
# has_animation() 只查默认库，查不到 preview 库的动画）
const ANIM_PATH := "preview/pistol_rig"
# 与 player.gd ARMS_BONES 一致：只裁剪双手（肩/臂/前臂/手），脊柱/头/腿沿用原动画
const ARMS_BONES: Array = [
	"LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
	"RightShoulder", "RightArm", "RightForeArm", "RightHand",
]
# 下半身必须与实机同源：swat 库的 Rifle Aiming Idle（2.633s，Spine 130.2°）。
# ⚠️ 不能用场景 AnimationPlayer 里同名的 Rifle Aiming Idle——它可能是手枪动画
#（1.367s / Spine 123.5°），合成出来姿势 ≠ 实机（Spine 被手枪姿态污染）。
const SWAT_LIB_PATH := "res://resources/mixamo_lib_swat.tres"
# 实机握把锚点配置（绑定用同一 grip 值，编辑器所见=实机）
const RIG_CFG_PATH := "res://resources/weapons/weapon_rig_config_v_deagle.tres"

func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	call_deferred("_pin")

func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	var ap: AnimationPlayer = get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null:
		return
	if ap.current_animation != ANIM_PATH:
		_pin()
	_bind_gun()

## 【绑定】编辑器里把手枪钉到右手球（HandMarker 位置）+ 枪口方向。
## 枪口方向 = 场景骨骼【手腕→手】方向 + 配置偏转(dir_yaw/pitch_offset) —— 与实机
## WeaponRig._pistol_dir() 完全同源，所见即所得。MuzzleMarker2/ButtMarker 挂在
## DeagleModel 下（枪口/枪托标记，随枪动），仅作枪轴可视化，不参与方向计算。
func _bind_gun() -> void:
	var hand: Node3D = get_node_or_null("Weapon_Deagle/HandMarker") as Node3D
	var elbow: Node3D = get_node_or_null("Weapon_Deagle/ElbowMarker") as Node3D
	var model: Node3D = get_node_or_null("Weapon_Deagle/DeagleAdjust/DeagleModel") as Node3D
	if hand == null or model == null:
		return
	# 枪口方向：场景骨架前臂（右手-右前臂，与实机同源）
	var dir: Vector3 = Vector3.ZERO
	var skel: Skeleton3D = null
	for n in get_parent().find_children("*", "Skeleton3D", true, false):
		skel = n as Skeleton3D
		break
	if skel != null:
		var fw: int = skel.find_bone("mixamorig_RightForeArm")
		var rw: int = skel.find_bone("mixamorig_RightHand")
		if fw >= 0 and rw >= 0:
			var p0: Vector3 = (skel.global_transform * skel.get_bone_global_pose(fw)).origin
			var p1: Vector3 = (skel.global_transform * skel.get_bone_global_pose(rw)).origin
			dir = p1 - p0
	if dir.length() < 0.01 and elbow != null:
		dir = hand.global_position - elbow.global_position
	if dir.length() < 0.01:
		return
	dir = dir.normalized()
	# 配置偏转（与实机同值：枪轴相对前臂的 yaw/pitch）
	var cfg: WeaponRigConfig = load(RIG_CFG_PATH) as WeaponRigConfig
	if cfg != null:
		if cfg.dir_yaw_offset != 0.0:
			dir = dir.rotated(Vector3.UP, cfg.dir_yaw_offset)
		if cfg.dir_pitch_offset != 0.0:
			var right: Vector3 = Vector3.UP.cross(dir).normalized()
			if right.length() < 0.01:
				right = Vector3.RIGHT
			dir = dir.rotated(right, cfg.dir_pitch_offset)
	# basis：z=枪口方向，up≈世界UP，x=up×z
	var up := Vector3.UP
	var x: Vector3 = up.cross(dir).normalized()
	if x.length() < 0.01:
		x = Vector3.RIGHT
	var y: Vector3 = dir.cross(x).normalized()
	var basis := Basis(x, y, dir)
	# 握把锚点 grip_real_local 落 HandMarker（与实机 WeaponRig 同公式）
	var grip: Vector3 = Vector3(0.116224, -0.194484, 0.770624)
	if cfg != null:
		grip = cfg.grip_real_local
	var anchor: Vector3 = hand.global_position - basis * grip
	model.global_transform = Transform3D(basis, anchor)

func _pin() -> void:
	var ap: AnimationPlayer = get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null:
		return
	if not ap.has_animation_library(&"preview"):
		_build(ap)
	else:
		var lib: AnimationLibrary = ap.get_animation_library(&"preview")
		if lib == null or not lib.has_animation(ANIM_NAME):
			_build(ap)
	if not ap.has_animation_library(&"preview"):
		return
	var lib2: AnimationLibrary = ap.get_animation_library(&"preview")
	if lib2 == null or not lib2.has_animation(ANIM_NAME):
		return
	ap.play(ANIM_PATH)
	ap.seek(0.0, true)
	ap.pause()

func _build(ap: AnimationPlayer) -> void:
	# ⚠️ 必须用独立"preview"库：AnimationPlayer 的 "" 库指向共享的
	# mixamo_lib_swat.tres（实机动画库），往它 add_animation 会把合成动画写进
	# swat 库文件（曾污染出 pistol_rig 条目）。独立库仅存在于场景内存/场景文件。
	var lib: AnimationLibrary = null
	if not ap.has_animation_library(&"preview"):
		lib = AnimationLibrary.new()
		ap.add_animation_library(&"preview", lib)
	else:
		lib = ap.get_animation_library(&"preview")
	# 下半身来源：swat 库 Rifle Aiming Idle（实机 3P 默认待机，Hips 已是项目坐标系）。
	# 优先从 swat 库显式加载（与实机 _get_cached_animation 同源），场景内同名动画不可信。
	var lower: Animation = null
	var swat_lib: AnimationLibrary = load(SWAT_LIB_PATH) as AnimationLibrary
	if swat_lib != null and swat_lib.has_animation(&"Rifle Aiming Idle"):
		lower = swat_lib.get_animation(&"Rifle Aiming Idle")
	if lower == null and ap.has_animation("Rifle Aiming Idle"):
		lower = ap.get_animation("Rifle Aiming Idle")
	if lower == null:
		for an in ap.get_animation_list():
			if String(an).contains("Aiming Idle"):
				lower = ap.get_animation(an)
				break
	if lower == null:
		return
	# —— 与 player.gd `_pistol_combine()` 相同实现 ——
	var combined := Animation.new()
	combined.length = lower.length
	combined.loop_mode = Animation.LOOP_LINEAR
	# 1) 非手臂轨道：原动画原样（整周期，无缝）
	for i in lower.get_track_count():
		if AnimationCombiner.is_upper_body_track(str(lower.track_get_path(i)), ARMS_BONES):
			continue
		AnimationCombiner.copy_track(lower, i, combined, -1)
	# 2) 手臂轨道：手枪待机循环铺满 + Shoulder 抬臂（与实机 `_pistol_combine` 一致）
	var _lift_deg: float = 0.0
	var _cfg2: WeaponRigConfig = load(RIG_CFG_PATH) as WeaponRigConfig
	if _cfg2 != null:
		_lift_deg = _cfg2.arm_lift_deg
	for i in PISTOL_ANIM.get_track_count():
		var sp := str(PISTOL_ANIM.track_get_path(i))
		if not AnimationCombiner.is_upper_body_track(sp, ARMS_BONES):
			continue
		if PISTOL_ANIM.track_get_type(i) != Animation.TYPE_ROTATION_3D:
			continue
		var _is_sh: bool = sp.contains("Shoulder")
		var _q_lift: Quaternion = Quaternion.IDENTITY
		if _is_sh and absf(_lift_deg) > 0.01:
			# 与实机相同：绕骨骼局部 x 轴负方向抬臂（肩骨位置不动）
			_q_lift = Quaternion(Vector3(1.0, 0.0, 0.0), deg_to_rad(-_lift_deg))
		var _ni := combined.add_track(Animation.TYPE_ROTATION_3D)
		combined.track_set_path(_ni, PISTOL_ANIM.track_get_path(i))
		var _plen: float = PISTOL_ANIM.length
		var _kc: int = PISTOL_ANIM.track_get_key_count(i)
		for _j in range(_kc):
			var _t: float = PISTOL_ANIM.track_get_key_time(i, _j)
			var _v: Quaternion = PISTOL_ANIM.track_get_key_value(i, _j)
			if _is_sh and _q_lift != Quaternion.IDENTITY:
				_v = _q_lift * _v
			var _t2: float = _t
			while _t2 <= combined.length + 0.001:
				combined.track_insert_key(_ni, _t2, _v)
				_t2 += _plen
		combined.track_set_interpolation_type(_ni, Animation.INTERPOLATION_LINEAR)
	lib.add_animation(ANIM_NAME, combined)
