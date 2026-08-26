class_name WeaponRig
extends Node

# P0-2：显式 preload 标定资源，确保无头模式下 WeaponRigConfig 全局类可解析。
const WeaponRigConfig = preload("res://scripts/weapon_rig_config.gd")

# ============================================================================
# WeaponRig — 第三人称武器握持系统（P0-1 从 player.gd 抽离）
# 封装：双手皮肤标注点连线定位 + 枪身轴线对齐 + 完美握持锚点 + 跳跃/换弹分支。
# 标定常量来自 WeaponRigConfig 资源（P0-2），与 AK47 模型 / Mixamo 骨骼解耦。
#
# 使用：Player._ready 中 new() 并 add_child，再调用 setup()；Player._process 每帧
# 在「上半身俯仰叠加之后」调用 update()。
# 设计要点（与 player.gd 协同）：
#   - 枪身轴线 = 固定常量 (0,0,-1)（模型 -Z 端=枪口，GLB 惯例），不读标注球；
#   - 手点 = 骨骼 × 固化 offset，拖标注球不再影响枪；
#   - 斜率差 SLOPE_R 仅双手直线分支、且在【角色本地系】旋转（转身由 char_basis 吸收）。
# ============================================================================

# ---- 运行时缓存 ----
var _weapon_skel: Skeleton3D = null        # 武器挂载目标 Skeleton3D
var _weapon_holder: Node3D = null          # Weapon_AK47 节点
# 【P3 多武器】动态 3P 枪（非 AK47 的 world_model 实例）：true = 跳过每帧握持跟随，
# 保持 player 初始摆位。原因：握把锚点(grip_real_local)按 AK47 网格标定，其它武器
# （如 M82 狙击枪）网格几何/握把位置不同，硬套 AK47 锚点会被摆到错误位置（悬空）。
var skip_follow: bool = false
var _weapon_bone_idx: int = -1             # RightHand 骨骼索引
var _lhand_bone_idx: int = -1              # LeftHand 骨骼索引（双手连线定位）
var _forearm_bone_idx: int = -1            # RightForeArm 骨骼索引（肘标注球基准）
var _skel_global: Transform3D = Transform3D.IDENTITY  # 每帧缓存的骨架全局变换（_bone_world 复用）

# 枪身轴线（Weapon_AK47 局部系，枪口方向）：固定常量 (0,0,-1)=模型 -Z=枪口。
var _gun_axis_local: Vector3 = Vector3(0, 0, -1)
# 目标枪口方向平滑（角色本地系 slerp）：只平滑动画内双手/前臂相对变化。
var _dir_local_smooth: Vector3 = Vector3.FORWARD
# 上一次的 one-shot（换弹/受击/投掷）标志：用于检测"一次性动画结束"下降沿，
# 在结束瞬间硬重置平滑方向，让枪身轴线与动画完成时机精确对齐（不再慢收敛延迟）。
var _prev_one_shot := false
# 握把点相对 Weapon_AK47 的局部位置（来自标定资源）
var _grip_rh_local: Vector3 = Vector3.ZERO

# ---- 设计常量（与具体资产无关，属握持系统行为）----
const DUAL_HAND_TURN_SPEED: float = 18.0   # 双手连线转向平滑速度（1/s）
# 跳跃时枪口固定方向（角色本地系）：= 待机完美枪口方向 固化。
# 跳跃动画手臂大幅挥动，用前臂方向会导致枪口乱转/朝上，固定端枪方向最稳。
const JUMP_MUZZLE_LOCAL: Vector3 = Vector3(-0.052436, -0.05635, 0.997033)
# 换弹结束前提前切回双手连线方向的窗口（秒）。基础 0.4s（FP 实装前动画层根治后
# 调定：换弹动画末帧已对齐待机首帧、回位尾巴 0.35s，双手末段本身在回位，提前量≈
# 回位时长即可），用户后追加提前 0.5s+0.1s → 1.0s。绝对提前量，与换弹总时长无关。
var one_shot_prelead: float = 1.0

# ---- 标定（来自 WeaponRigConfig，运行时可改 .tres 调整）----
var ak47_scale: float = 0.0706
var grip_real_local: Vector3 = Vector3(-0.134841, 0.022478, -0.115572)
var grip_rh_offset: Vector3 = Vector3(-89.13281, 451.4172, 71.25647)
var grip_lh_offset: Vector3 = Vector3(104.7581, 585.998, 63.58203)
var grip_elbow_offset: Vector3 = Vector3(103.0625, -531.6064, 258.6724)
var slope_r: Basis = Basis.IDENTITY
# 【P3 用户微调】跟手摆位后叠加的相对偏移（m / 弧度）。见 WeaponRigConfig.user_offset_*。
var user_offset_pos: Vector3 = Vector3.ZERO
var user_offset_rot: Vector3 = Vector3.ZERO
# 【手枪横握】true = 正常持枪时枪口方向用角色前向(char_basis.z)而非双手连线
#（手枪横握双手连线≈横向会把枪转横）。步枪默认 false 原逻辑零变化。
var dir_use_forward: bool = false
# 【手枪枪口水平修正】dir_use_forward 时绕世界 UP 的附加偏转（弧度，正=右转）
var dir_yaw_offset: float = 0.0
# 【手枪枪口俯仰修正】绕右轴的附加俯仰（弧度，正=枪口上抬）
var dir_pitch_offset: float = 0.0

## 【P3 标定】运行时覆盖枪身轴线（编辑器标注球标定用）：axis 为枪模型本地系单位向量。
func set_gun_axis_local(axis: Vector3) -> void:
	if axis.length() > 0.01:
		_gun_axis_local = axis.normalized()


# 绑定骨架 / 武器节点与标定资源，缓存骨骼索引、隐藏纯标注球、初始化握把局部点。
# 标注球（GripPoint_*）为纯编辑标注、不参与运行时计算：游戏内隐藏。
func setup(skel: Skeleton3D, weapon_holder: Node3D, config: WeaponRigConfig) -> void:
	_weapon_skel = skel
	_weapon_holder = weapon_holder
	if config != null:
		ak47_scale = config.ak47_scale
		_gun_axis_local = config.gun_axis_local   # 【P3 多武器】武器专属枪身轴线（M82 等非 -Z）
		grip_real_local = config.grip_real_local   # 【F-08 资产约束】必须武器本地系（非角色骨架空间 k 换算），否则握把锚点错位
		user_offset_pos = config.user_offset_pos
		user_offset_rot = config.user_offset_rot
		grip_rh_offset = config.grip_rh_offset
		grip_lh_offset = config.grip_lh_offset
		grip_elbow_offset = config.grip_elbow_offset
		slope_r = config.slope_r
		dir_use_forward = config.dir_use_forward
		dir_yaw_offset = config.dir_yaw_offset
		dir_pitch_offset = config.dir_pitch_offset
	# 【100%换皮】握持偏移 grip_*_offset 是【飞虎队 A 空间】（Armature scale=0.00026，
	# 骨骼坐标千位级）标定的。新角色骨架（如 SWAT）在 N 空间（Armature scale=0.013795），
	# offset 直接套用会被放大 ~53 倍 → 枪飞远/悬空。
	# 换算：N_offset = A_offset × (0.00026 / skeleton_space_scale)。
	# 标定值读 config.skeleton_space_scale（资产生成时按角色写入），不再用骨架测量
	# 推断——测量依赖骨架结构，特殊骨架可能误判；数据驱动则角色差异全在资产里。
	var k: float = 0.00026
	if config != null and config.skeleton_space_scale > 0.0:
		k = 0.00026 / config.skeleton_space_scale
	if absf(k - 1.0) > 0.0001:
		grip_rh_offset *= k
		grip_lh_offset *= k
		grip_elbow_offset *= k
	if _weapon_skel != null:
		_weapon_bone_idx = _weapon_skel.find_bone("mixamorig_RightHand")
		_lhand_bone_idx = _weapon_skel.find_bone("mixamorig_LeftHand")
		_forearm_bone_idx = _weapon_skel.find_bone("mixamorig_RightForeArm")
	# 握把锚点(Weapon_AK47 局部系) = 重标定常量 grip_real_local。
	# 运行时 anchor = rh_hand - basis × _grip_rh_local → 枪上握把点恒=右手球（完美握持）。
	_grip_rh_local = grip_real_local
	# 隐藏纯标注球（编辑器仍可见；本节点非 @tool，_ready 不在编辑器执行）。
	# 球分布：GripPoint_Muzzle/Butt 在 Weapon_AK47 下；其余在 character_visual 根下，
	# 故先在 Weapon_AK47 子树递归找，再从 character_visual 根递归找。
	if _weapon_holder != null:
		var visual_root: Node = _weapon_holder.get_parent()
		for gp_name in ["GripPoint_RH", "GripPoint_LH", "GripPoint_Elbow_RH",
						"GripPoint_Muzzle", "GripPoint_Butt", "GripPoint_GunGrip"]:
			var gp = _weapon_holder.find_child(gp_name, true, false)
			if gp == null and visual_root != null:
				gp = visual_root.find_child(gp_name, true, false)
			if gp != null:
				gp.visible = false
	if _weapon_holder == null:
		push_warning("武器挂载：未找到 Weapon_AK47 节点（character.tscn），AK47 未挂载")


# 每帧更新武器世界变换（在 Player 上半身俯仰叠加之后调用）。
# is_one_shot：是否处于一次性动画覆盖（换弹/投掷/受击/死亡）；is_jump：是否跳跃态。
# oneshot_remaining：一次性动画剩余时间（秒）。换弹接近结束时（<=ONE_SHOT_PRELEAD）
# 提前切回"双手连线"方向，让枪身轴线在动画完成前就平滑转到待机方向，避免
# 换弹末帧双手未回位导致的轴线延迟/跳变。默认 INF=不提前（其他 one-shot 保持原行为）。
func update(delta: float, char_basis: Basis, is_one_shot: bool, is_jump: bool,
		oneshot_remaining: float = INF) -> void:
	if _weapon_holder == null or _weapon_skel == null or _weapon_bone_idx < 0:
		return
	# 【P3 多武器】动态 3P 枪跳过握持跟随：保持 player 初始摆位（M82 等非 AK47 武器）
	if skip_follow:
		return
	# 每帧缓存骨架全局变换（_bone_world 复用，避免重复层级回溯）
	_skel_global = _weapon_skel.global_transform
	# 手点 = 骨骼 × 固化 offset（与球无关，拖球不影响枪）
	# 【修复 M4】左手/前臂骨骼可能缺失（换皮新骨架结构差异）：索引无效(-1)时
	# 不调 get_bone_global_pose(-1)（否则每帧 push_error + 方向算错），而是默认=右手点，
	# 使下方方向分支 length<=0.01 自动回退到角色前向，保证不崩且枪朝向合理。
	var rh_hand: Vector3 = _bone_world(_weapon_bone_idx, grip_rh_offset)
	var lh_hand: Vector3 = rh_hand
	var elbow_world: Vector3 = rh_hand
	if _lhand_bone_idx >= 0:
		lh_hand = _bone_world(_lhand_bone_idx, grip_lh_offset)
	if _forearm_bone_idx >= 0:
		elbow_world = _bone_world(_forearm_bone_idx, grip_elbow_offset)
	# 是否使用"双手连线"方向：非 one-shot，或 one-shot 已进入提前收尾窗口（换弹结束前）
	var use_dual: bool = (not is_one_shot) or (oneshot_remaining <= one_shot_prelead)
	var dir: Vector3
	if not use_dual:
		if dir_use_forward:
			# 【手枪】一次性动作（换弹/投掷/受击等）枪口也跟手（前臂方向+偏转）——
			# 与普通持枪一致，避免动作时枪口跳向别处。
			dir = _pistol_dir()
		elif is_jump:
			dir = char_basis * JUMP_MUZZLE_LOCAL
		else:
			dir = rh_hand - elbow_world
			if dir.length() <= 0.01:
				dir = char_basis.z
	else:
		if dir_use_forward:
			# 【手枪】枪口方向 = 手腕→手(前臂)方向 + 用户标注偏转（yaw/pitch）。
			# 用户方案：枪轴(枪托→枪口)匹配手腕→手连线 → 任何动作枪口都跟手偏转、
			# 枪身跟手位移。偏转量来自 deagle_rig_preview 标注（Muzzle2-Butt 相对
			# Hand-Elbow 的 yaw/pitch），写入 dir_yaw_offset/dir_pitch_offset。
			dir = _pistol_dir()
		else:
			dir = lh_hand - rh_hand
			if dir.length() <= 0.01:
				dir = char_basis.z
	dir = dir.normalized()
	if dir.dot(char_basis.z) < 0.0:
		dir = -dir
	# 双手直线/前臂方向 → 角色本地系（转身由 char_basis 吸收）
	var dir_local: Vector3 = (char_basis.inverse() * dir).normalized()
	# 应用固化斜率差（仅双手直线分支）：在【本地系】旋转，而非世界系！
	# dir_use_forward（手枪前臂方向）本身就是枪口方向，跳过 slope 标定（AK47 的
	# slope 会把前臂方向转偏，实测俯仰 -7.7°）。
	if use_dual and not dir_use_forward:
		dir_local = (slope_r * dir_local).normalized()
	# 一次性动画（换弹等）结束的下降沿：枪身轴线立即匹配新目标方向（兜底；
	# 提前切换后此处方向已一致，不会产生跳变）。
	if _prev_one_shot and not is_one_shot:
		_dir_local_smooth = dir_local
	_prev_one_shot = is_one_shot
	# 本地系平滑（只平滑动画内双手/前臂相对变化；转身被 char_basis 瞬时吸收）
	_dir_local_smooth = _dir_local_smooth.slerp(dir_local, clampf(delta * DUAL_HAND_TURN_SPEED, 0.0, 1.0))
	var dir_eff: Vector3 = (char_basis * _dir_local_smooth).normalized()
	# 枪身真实轴线（固定常量 0,0,-1=模型-Z=枪口）对齐目标方向（up 约束 roll）
	var basis: Basis = _align_axis_to_dir(_gun_axis_local, dir_eff, char_basis.y, char_basis.z)
	# 位置补偿：枪上握把点精确钉在右手皮肤点（rh_hand）——完美握持。
	var anchor: Vector3 = rh_hand - basis * _grip_rh_local
	_weapon_holder.global_transform = Transform3D(basis, anchor)
	# 【P3 用户微调】跟手摆位后叠加相对偏移：枪随角色动（跟手），但在手中位置/朝向
	# 可被用户微调（编辑器 scenes/m82_3p_adjust.tscn 调 user_offset_pos/rot 后抄回配置）。
	# 顺序：先跟手摆位（basis, anchor），再乘以用户旋转/平移（相对枪身局部系）。
	if user_offset_pos != Vector3.ZERO or user_offset_rot != Vector3.ZERO:
		var off := Transform3D(Basis.from_euler(user_offset_rot), user_offset_pos)
		_weapon_holder.global_transform = _weapon_holder.global_transform * off


## 【手枪】枪口方向 = 手腕→手骨骼方向（跟手）+ 用户标注偏转（yaw/pitch）。
## 用户方案：枪轴(枪托→枪口)匹配手腕→手连线 → 任何动作枪口都跟手偏转、枪身跟手位移。
## 偏转量来自 deagle_rig_preview 标注（Muzzle2-Butt 相对 Hand-Elbow），写入配置。
func _pistol_dir() -> Vector3:
	var d: Vector3 = _skel_global.basis.z
	if _weapon_skel != null and _forearm_bone_idx >= 0 and _weapon_bone_idx >= 0:
		var p0: Vector3 = (_skel_global * _weapon_skel.get_bone_global_pose(_forearm_bone_idx)).origin
		var p1: Vector3 = (_skel_global * _weapon_skel.get_bone_global_pose(_weapon_bone_idx)).origin
		var dd: Vector3 = p1 - p0
		if dd.length() > 0.01:
			d = dd.normalized()
	if dir_yaw_offset != 0.0:
		d = d.rotated(Vector3.UP, dir_yaw_offset)
	if dir_pitch_offset != 0.0:
		var right: Vector3 = Vector3.UP.cross(d).normalized()
		if right.length() < 0.01:
			right = Vector3.RIGHT
		d = d.rotated(right, dir_pitch_offset)
	return d

# 构建 basis：使 basis × axis_local = dir（枪身真实轴线对齐目标枪口方向），
# 且绕 dir 的 roll 尽量使枪"上"（basis.y）贴近 up（世界/角色上方向）。
# 【修复 #10】近竖直瞄准时 up 与 dir 近平行 → up_proj 退化 → 枪身 roll 奇点（突翻）。
# 用 fwd（角色前向，竖直瞄准时恒与 dir 垂直）按"平行度"平滑混入 roll 参考，
# 保证参考连续非退化；仅影响近竖直瞄准带（正常瞄准 sin²(up,dir) 大，走原逻辑，零回归）。
func _align_axis_to_dir(axis_local: Vector3, dir: Vector3, up: Vector3, fwd: Vector3 = Vector3.FORWARD) -> Basis:
	var a: Vector3 = axis_local.normalized()
	var d: Vector3 = dir.normalized()
	var basis: Basis = _rot_from_to(a, d)
	var up_proj: Vector3 = up - d * up.dot(d)
	var sin2: float = up_proj.length_squared()  # = sin²(angle(up,dir))（up 为单位向量）
	if sin2 < 0.04:  # 约 < 11.5° 视为近平行，进入退化带
		var fproj: Vector3 = fwd - d * fwd.dot(d)
		if fproj.length_squared() > 1e-4:
			var blend: float = clampf(sin2 / 0.04, 0.0, 1.0)  # 完全平行→0 全用 fwd；远离→1 用 up
			var ref: Vector3 = fproj * (1.0 - blend) + up_proj * blend
			if ref.length_squared() > 1e-6:
				up_proj = ref - d * ref.dot(d)
	var cur_y: Vector3 = basis.y
	var cur_proj: Vector3 = cur_y - d * cur_y.dot(d)
	if cur_proj.length() > 0.01:
		var ang: float = cur_proj.angle_to(up_proj)
		if cur_proj.cross(up_proj).dot(d) < 0.0:
			ang = -ang
		basis = Basis(d, ang) * basis
	return basis


# from 旋转到 to 的最短旋转（axis-angle；反平行时绕垂直轴 180°）
func _rot_from_to(from: Vector3, to: Vector3) -> Basis:
	var f: Vector3 = from.normalized()
	var t: Vector3 = to.normalized()
	var d: float = f.dot(t)
	if d > 0.9999:
		return Basis.IDENTITY
	if d < -0.9999:
		var perp: Vector3 = f.cross(Vector3.RIGHT)
		if perp.length() < 1e-6:
			perp = f.cross(Vector3.UP)
		return Basis(perp.normalized(), PI)
	var axis: Vector3 = f.cross(t).normalized()
	return Basis(axis, acos(clampf(d, -1.0, 1.0)))


# 更新标注球世界位置（跟随骨骼蒙皮），返回球的世界坐标
# 数学：皮肤点在骨架空间 = rest_pose⁻¹ × grip_skel；动画中该点 = anim_pose × (rest_pose⁻¹ × grip_skel)
# 手点世界位置 = 骨骼全局姿态 × 固化 offset（骨架空间皮肤点，与球无关）
func _bone_world(bone_idx: int, offset: Vector3) -> Vector3:
	var bone_pose: Transform3D = _skel_global * _weapon_skel.get_bone_global_pose(bone_idx)
	return bone_pose * offset
