class_name FPActionRetarget
extends Node
const AudioWavLoader = preload("res://scripts/audio_wav_loader.gd")
# ============================================================================
# 第三人称"刺刀/射击"动作叠加系统（复用第一人称动作的形态/时长，程序化实现）
# ----------------------------------------------------------------------------
# 第一人称 cidao1(刺刀,1.19s) / shoot2(射击,0.52s) 是"枪+双臂"视图模型动画，
# 第三人称 Mixamo 角色无对应资产。本系统用"程序化包络"复现其动作质感：
#   - 肩骨(mixamorig_RightArm/LeftArm)整条手臂链世界系平移（非旋转！旋转只能画弧
#     做不出纯前刺）=> 双臂前刺(刺刀)/后坐(射击)，前臂随之运动（满足"应用到手臂前臂和枪身"）。
#   - 世界枪(Weapon_AK47)经 WeaponRig 跟手，自然前推/后坐（方向取枪管轴向，已含俯仰）。
#   - 朝向关键：前刺/后坐方向取角色前向(char_basis.z，本角色实际朝 +Z)，正=远离射手=前刺，负=后坐。
#   - 枪口火光(射击) + 音效（.dat 运行时解析，绕开 BWF 崩溃）。
# 包络形状来自第一人称动画分析（前刺=蓄力→前刺→保持→收回；射击=急踢→回稳），
# 增益可独立调参（弧度/米），适配第三人称尺度。
# ============================================================================

# 动作时长（与第一人称一致）
const DUR_BAYONET := 1.19
const DUR_SHOOT := 0.52
# 长按左键自动连发间隔（秒/发，≈400发/分，与 FP 一致）
const AUTO_FIRE_INTERVAL := 0.15

# 换弹音效路径（与 FP 共用同一份 .dat，绕开 BWF 导入崩溃）
const RELOAD_SFX_PATH := "res://audio/AK47-HQL_RELOAD.dat"

# 【P3 多武器】连发间隔运行期覆盖（player 从 WeaponDef.fire_rate 注入；默认=原硬编码常量）
var _fire_interval: float = AUTO_FIRE_INTERVAL

# ---- 增益（调参用）----
# 前刺/后坐实现：肩骨(mixamorig_RightArm/LeftArm)整条手臂链世界系平移（非旋转！旋转只能
# 画弧做不出纯前刺）。平移使手确实"向前刺出"，但肩骨会从躯干皮肤扯开=手臂皮肤被拉长
# （旧版"随机拉长手臂"现象；用户 2026-08-15 要求恢复此前向观感故回退到此实现）。
const BAYONET_THRUST := 0.26         # 刺刀前刺包络峰值（米）：thrust=BAYONET_THRUST*_shape，沿角色前向平移肩骨
const SHOOT_KICK := 0.09             # 射击后坐（米）

# ---- 注入引用 ----
var skel: Skeleton3D = null
## 【性能】骨骼名→索引缓存：_translate_arms 射击期间每帧对 2 骨各做一次
## O(骨骼数) 的 find_bone 字符串查找。skel 引用在 setup 后不变，索引恒定。
var _bone_idx_cache: Dictionary = {}
var weapon_rig: WeaponRig = null
var gun_holder: Node3D = null
var muzzle_flash: Node3D = null

# ---- 音效 ----
# 射击/刺刀/换弹各自独立播放器：换弹/刺刀打断射击时枪声继续播完，互不切断。
var _sfx_player: AudioStreamPlayer = null           # 射击音效
var _sfx_player_bayonet: AudioStreamPlayer = null   # 刺刀音效
var _sfx_player_reload: AudioStreamPlayer = null    # 换弹音效
var _sfx_shoot: AudioStreamWAV = null
var _sfx_bayonet: AudioStreamWAV = null
var _sfx_reload: AudioStreamWAV = null

# ---- 状态 ----
var _active := false
var _action := ""          # "bayonet" / "shoot"
var _t := 0.0
var _dur := 0.0
var _hold := false
var _hold_timer := 0.0
var _fire_blocked := false  # 射击封锁（地面奔跑）：封锁时新射击/连发均不生效
var _reloading := false     # 换弹中：封锁新射击/连发（与 FP 视图模型 is_reload() 约束对齐）
var _last_char_basis: Basis = Basis.IDENTITY   # 最近一帧角色基（用于动作结束后把肩骨复位到 rest）
# 最近一帧"瞄准前向"（相机视线方向，含俯仰）：前刺/后坐沿此方向而非纯水平 char_basis.z。
# 【修复·刺刀俯仰】原先前刺方向取水平 char_basis.z，低头时水平前刺投影到屏幕变成"向上"，
# 表现为"头往下低、刺刀肩膀往上而不是往前"。改为跟随相机视线(含俯仰)后，低头时前刺朝下、
# 屏幕上呈"向前(纵深)"，与用户直觉一致；也跟第一人称视图模型(cidao1 在相机局部空间、天然
# 跟随相机)的观感对齐。未传入(|aim_forward|≈0)时回退水平 char_basis.z，保持旧行为兜底。
var _aim_forward: Vector3 = Vector3.ZERO
# 诊断：最近一次 _translate_arms 实际施加的世界平移(thrust 向量)，供探针核对方向/幅度（无副作用）。
var _last_trans: Vector3 = Vector3.ZERO

# 设置射击封锁（由 Player 每帧按"地面奔跑"状态更新）
func set_fire_blocked(v: bool) -> void:
	_fire_blocked = v

func is_fire_blocked() -> bool:
	return _fire_blocked

# 换弹状态（由 Player 每帧按 _is_reloading 同步）：换弹中封锁新射击/连发，
# 与第一人称视图模型 trigger_shoot 的 is_reload() 约束保持一致，避免 3P 影子在换弹中
# 因按住开火键自动连发而抖动（FP 枪不抖、3P 影子抖的脱节）。
func set_reloading(v: bool) -> void:
	_reloading = v

func is_reloading() -> bool:
	return _reloading

# 立即打断当前射击动作（奔跑进入瞬间调用）：停动作、停连发、熄灭火光。
# 不打断刺刀（刺刀不可被打断）。
func interrupt_shoot() -> void:
	if _active and _action == "shoot":
		_active = false
		_action = ""
		_t = 0.0
		_dur = 0.0
		_reset_arms()   # 奔跑打断射击：肩骨/手臂复位到 rest，避免卡在后坐残留位
		if muzzle_flash != null:
			muzzle_flash.visible = false
	_hold = false
	_hold_timer = 0.0

func setup(p_skel: Skeleton3D, p_rig: WeaponRig, p_gun: Node3D, p_flash: Node3D,
		   shoot_path: String, bayonet_path: String) -> void:
	skel = p_skel
	_bone_idx_cache.clear()   # 防御：骨架变更时索引缓存失效
	weapon_rig = p_rig
	gun_holder = p_gun
	muzzle_flash = p_flash
	_sfx_player = AudioStreamPlayer.new()
	add_child(_sfx_player)
	_sfx_player_bayonet = AudioStreamPlayer.new()
	add_child(_sfx_player_bayonet)
	_sfx_player_reload = AudioStreamPlayer.new()
	add_child(_sfx_player_reload)
	_sfx_shoot = _load_sfx_wav(shoot_path)
	_sfx_bayonet = _load_sfx_wav(bayonet_path)
	_sfx_reload = _load_sfx_wav(RELOAD_SFX_PATH)
	if _sfx_shoot == null:
		push_warning("FPRetarget: 射击音效缺失 %s" % shoot_path)
	if _sfx_bayonet == null:
		push_warning("FPRetarget: 刺刀音效缺失 %s" % bayonet_path)
	if _sfx_reload == null:
		push_warning("FPRetarget: 换弹音效缺失 %s" % RELOAD_SFX_PATH)

func set_hold(v: bool) -> void:
	_hold = v
	if v:
		_hold_timer = _fire_interval

## 【P3 多武器】切换武器时由 player 注入连发间隔（秒/发）；<=0 忽略（保留当前）。
func set_fire_interval(v: float) -> void:
	if v > 0.0:
		_fire_interval = v

## 【P3 静音开关】本武器无专属音效时置 true：3P 射击/换弹/刺刀全部不发声。
var _silent := false
func set_silent(v: bool) -> void:
	_silent = v

## 切换武器时由 player 注入新武器音效路径；空=保留当前。
func set_sfx_paths(shoot: String, bay: String) -> void:
	if shoot != "":
		var s := _load_sfx_wav(shoot)
		if s != null: _sfx_shoot = s
	if bay != "":
		var b := _load_sfx_wav(bay)
		if b != null: _sfx_bayonet = b

## 切换武器时由 player 注入新武器换弹音效路径；空=保留默认 RELOAD_SFX_PATH。
func set_reload_sfx(reload: String) -> void:
	if reload != "":
		var r := _load_sfx_wav(reload)
		if r != null: _sfx_reload = r

# ---------- 状态查询（供 player 输入规则判定）----------
func is_active() -> bool:
	return _active

func is_bayonet() -> bool:
	return _active and _action == "bayonet"

func is_shoot() -> bool:
	return _active and _action == "shoot"

# ---------- 触发 ----------
func trigger_bayonet() -> void:
	# 射击中直接触发刺刀：立即打断射击（火光熄灭、动作复位），保证刺刀立刻响应。
	# 不打断枪声音效（刺刀音效走独立播放器，枪声继续播完）。
	if _active and _action == "shoot":
		_active = false
		if muzzle_flash != null:
			muzzle_flash.visible = false
	_start("bayonet", DUR_BAYONET)
	if not _silent and _sfx_bayonet != null and _sfx_player_bayonet != null:
		_sfx_player_bayonet.stream = _sfx_bayonet
		_sfx_player_bayonet.play()

# 第一人称专用：仅启动刺刀动画（_active/_action），不播 3P 音效。
# FP 下 3P 角色为 SHADOW_ONLY，其手臂前刺会被投影到地面，使影子随刺刀动作抖动；
# 音效仍由第一人称视图模型(_fp_vm)负责，避免双音。与 trigger_shoot_shadow 同理。
func trigger_bayonet_shadow() -> void:
	if _active and _action == "shoot":
		_active = false
		if muzzle_flash != null:
			muzzle_flash.visible = false
	_start("bayonet", DUR_BAYONET)

func trigger_shoot() -> void:
	if _fire_blocked:
		return  # 地面奔跑中禁止射击（换弹中按射击=取消换弹并开火，由 player 统一处理；
				# 长按自动连发由 update() 的 not _reloading 守卫拦截，不在此挡，否则连"取消换弹"也被误杀）
	_start("shoot", DUR_SHOOT)
	if not _silent and _sfx_shoot != null and _sfx_player != null:
		_sfx_player.stream = _sfx_shoot
		_sfx_player.play()

# 第一人称专用：仅启动后坐动画（_active/_action），不播 3P 音效。
# FP 下 3P 角色为 SHADOW_ONLY，其手臂后坐会被投影到地面，使影子随射击抖动；
# 音效仍由第一人称视图模型(_fp_vm)负责，避免双音。
func trigger_shoot_shadow() -> void:
	if _fire_blocked:
		return
	_start("shoot", DUR_SHOOT)

# 换弹音效（与 FP 共用同一份 .dat）：独立播放器，不打断射击/刺刀音。
# target_dur：换弹动画时长（秒）。>0 时把声音 pitch_scale 拉伸到恰好铺满动画
# （时长跟随动画时长），默认 0=不拉伸。
func trigger_reload(target_dur: float = 0.0) -> void:
	if not _silent and _sfx_reload != null and _sfx_player_reload != null:
		_sfx_player_reload.stream = _sfx_reload
		if target_dur > 0.01:
			var _nat: float = _sfx_reload.get_length()
			_sfx_player_reload.pitch_scale = (_nat / target_dur) if _nat > 0.01 else 1.0
		else:
			_sfx_player_reload.pitch_scale = 1.0
		_sfx_player_reload.play()

# 立即停止换弹音效（切到第一人称、由 FP 视角模型接管换弹音时调用，避免双音叠加）
func stop_reload() -> void:
	if _sfx_player_reload != null:
		_sfx_player_reload.stop()

func _start(a: String, d: float) -> void:
	_action = a
	_dur = d
	_t = 0.0
	_active = true

# ---------- 每帧更新（Player._process 在 WeaponRig.update 之前调用）----------
func update(delta: float, char_basis: Basis, aim_forward: Vector3 = Vector3.ZERO) -> void:
	# 长按连发：每隔 AUTO_FIRE_INTERVAL 重启一次后坐包络。放在 `if not _active`
	# 之前，使连发不受 DUR_SHOOT(0.52s) 限制，可与第一人称同射速(~400发/分)连续触发。
	# 刺刀进行中不响应连发（刺刀不可被打断）；地面奔跑封锁时连发立即停止。
	if _hold and not is_bayonet() and not _fire_blocked and not _reloading:
		_hold_timer -= delta
		if _hold_timer <= 0.0:
			_hold_timer = _fire_interval
			trigger_shoot()
	if not _active:
		return
	# 【修复·刺刀俯仰】记录本帧瞄准前向（相机视线，含俯仰）；无效则保持零向量，
	# _translate_arms 会回退水平 char_basis.z，行为与旧版一致。
	if aim_forward.length_squared() > 1e-6:
		_aim_forward = aim_forward.normalized()
	_t += delta
	var p := clampf(_t / _dur, 0.0, 1.0)
	var thrust := 0.0
	if _action == "bayonet":
		thrust = BAYONET_THRUST * _shape_bayonet(p)      # 正=前刺(沿枪口前向，超过待机)
	else:  # shoot
		thrust = -SHOOT_KICK * _shape_shoot(p)            # 负=后坐(沿枪口反方向)
	# 绕肩膀关节旋转上臂骨前摆/后摆（thrust>0 前刺、<0 后坐）：手臂以肩为轴摆动，
	# 始终连在躯干上（不再平移肩骨把皮肤扯长）；世界枪经 WeaponRig 跟手同步前刺/后坐。
	_last_char_basis = char_basis
	_translate_arms(thrust, char_basis)
	# 枪口火光（仅射击，开火瞬间短暂）：核心球短暂可见 + 光源随整段射击包络发光并按 _shape_shoot 衰减，
	# 使亮芯峰值与余辉都可见（真正"会发光的火光"），射击结束(_finish/打断)时熄灭。
	if _action == "shoot":
		var _flash_on: bool = (p < 0.12)
		if muzzle_flash != null:
			muzzle_flash.visible = _flash_on
	if _t >= _dur:
		_finish()

# 第一人称专用：仅驱动 3P 角色(影子投射体)的射击/刺刀后坐动画，不触发任何音效。
# 与 update() 逻辑一致，但 auto-fire 调用 trigger_shoot_shadow()（无 3P 音效），
# 且射击时不显示 3P 火光球（避免 SHADOW_ONLY 的影子出现闪烁光斑）。
# 修复"第一人称射击时地面影子没有抖动效果"。
func update_shadow(delta: float, char_basis: Basis, aim_forward: Vector3 = Vector3.ZERO) -> void:
	if _hold and not is_bayonet() and not _fire_blocked and not _reloading:
		_hold_timer -= delta
		if _hold_timer <= 0.0:
			_hold_timer = _fire_interval
			trigger_shoot_shadow()
	if not _active:
		return
	# 【修复·刺刀俯仰】同 update()：记录本帧瞄准前向（影子也需跟随俯仰，否则 FP 下
	# 3P 影子前刺方向与可见视图模型脱节）。
	if aim_forward.length_squared() > 1e-6:
		_aim_forward = aim_forward.normalized()
	_t += delta
	var p := clampf(_t / _dur, 0.0, 1.0)
	var thrust := 0.0
	if _action == "bayonet":
		thrust = BAYONET_THRUST * _shape_bayonet(p)
	else:  # shoot
		thrust = -SHOOT_KICK * _shape_shoot(p)
	_last_char_basis = char_basis
	_translate_arms(thrust, char_basis)
	if _action == "shoot" and muzzle_flash != null:
		muzzle_flash.visible = false   # FP 下 3P 火光球不显示（影子不出现闪烁光斑）
	if _t >= _dur:
		_finish()

func _finish() -> void:
	_active = false
	_action = ""
	_reset_arms()   # 动作收尾：肩骨/手臂复位到 rest，避免拉长/后缩残留
	if muzzle_flash != null:
		muzzle_flash.visible = false

# ---------- 包络形状（归一 0..1）----------
# 刺刀：微微收一点蓄力 → 向前刺出(超过待机位) → 保持 → 收回到待机
# 正值=沿枪口前向(远离射手)，负值=反向(蓄力微收)。峰值 +1.0 即前刺超过待机位。
func _shape_bayonet(p: float) -> float:
	if p < 0.12:
		return -0.12 * (p / 0.12)                    # 蓄力：轻微后收(微微)
	if p < 0.40:
		return lerpf(-0.12, 1.0, (p - 0.12) / 0.28)   # 前刺：冲过待机位到 +1.0
	if p < 0.70:
		return 1.0                                    # 保持刺出
	return lerpf(1.0, 0.0, (p - 0.70) / 0.30)         # 收回到待机

# 射击：急踢→回稳
func _shape_shoot(p: float) -> float:
	if p < 0.12:
		return (p / 0.12)
	if p < 0.45:
		return lerpf(1.0, 0.0, (p - 0.12) / 0.33)
	return 0.0

# ---------- 手臂前刺/后坐：肩骨整条手臂链世界系平移（前刺/后坐） ----------
# 回退实现（用户 2026-08-15 要求恢复此前向平移观感）：平移肩骨(mixamorig_RightArm/LeftArm)，
# 整条手臂(前臂+手)随之世界系前移 => 手确实"向前刺出"(刺刀)/回收(后坐)；
# 代价：肩骨从躯干皮肤扯开=手臂皮肤被拉长（旧版"随机拉长手臂"现象，用户接受此前向观感故恢复）。
# 每帧在 AnimationPlayer 已重置的骨姿态上叠加一次性平移（不累积、无残留）。
func _translate_arms(thrust: float, char_basis: Basis) -> void:
	if skel == null:
		return
	# 前刺/后坐方向：默认水平 char_basis.z（本角色实际朝 +Z，非 Godot 默认 -Z）；
	# 若本帧传入了瞄准前向(相机视线，含俯仰)，则用它，使低头时前刺朝下、屏幕呈"向前"。
	var fwd := char_basis.z
	if _aim_forward.length_squared() > 1e-6:
		fwd = _aim_forward
	if fwd.length_squared() < 1e-6:
		fwd = Vector3(0, 0, -1)
	fwd = fwd.normalized()
	var trans := fwd * thrust   # thrust>0 肩前移(刺刀)；<0 后移(后坐)
	_last_trans = trans
						# 注：本角色实际朝 +Z，故前向取 +char_basis.z（非 Godot 默认 -Z）；
						# 翻错会导致刺刀峰值反成后缩、后坐反成前冲。
	for nm in ["mixamorig_RightArm", "mixamorig_LeftArm"]:
		_translate_bone(nm, trans)

# 把"世界平移"叠加到某骨本地位置：世界 offset 经父骨世界基变换回父本地坐标，
# 加到骨【rest 姿态】的本地位置上（非当前姿态！）。以 rest 为基准 => 每帧位移都是
# "rest + 本帧偏移"，thrust 回到 0 时肩骨必然回到 rest 位（不累积、无残留拉长）。
# 若以"当前姿态"为基准，则动画只驱动旋转轨、不动位置轨 => 偏移逐帧累加、动作结束后
# 肩骨永久停在错误位置（手臂被拉长且收不回，见 2026-08-15 贴墙刺刀后退手臂拉长的 bug）。
func _translate_bone(nm: String, world_offset: Vector3) -> void:
	var bi: int = -1
	if _bone_idx_cache.has(nm):
		bi = _bone_idx_cache[nm]
	else:
		bi = skel.find_bone(nm)
		_bone_idx_cache[nm] = bi
	if bi < 0:
		return
	var par := skel.get_bone_parent(bi)
	var par_basis := Basis.IDENTITY
	if par >= 0:
		par_basis = (skel.global_transform * skel.get_bone_global_pose(par)).basis
	else:
		par_basis = skel.global_transform.basis
	var local_off := par_basis.inverse() * world_offset
	var rest_pos := skel.get_bone_rest(bi).origin   # rest/bind 本地位置（关键：非 get_bone_pose_position）
	skel.set_bone_pose_position(bi, rest_pos + local_off)

# 把肩骨复位到 rest 姿态（thrust=0 时前刺/后坐偏移清零）。动作正常结束(_finish)或被
# 打断(interrupt_shoot)时调用，确保肩骨/手臂不会卡在"拉长"或"后缩"的残留姿态。
func _reset_arms() -> void:
	_translate_arms(0.0, _last_char_basis)

# ---------- 音效解析（.dat，绕开 BWF WAV 导入崩溃）----------
func _load_sfx_wav(res_path: String) -> AudioStreamWAV:
	return AudioWavLoader.load_wav(res_path)
