class_name FPViewmodelPlayer
extends Node
const AudioWavLoader = preload("res://scripts/audio_wav_loader.gd")
# ============================================================================
# FPViewmodelPlayer — 第一人称视图模型子系统（V 键切换集成用）
# ----------------------------------------------------------------------------
# 职责：把 ak47_viewmodel.gltf（枪+双臂，55 关节，7 套动画）挂到【传入的相机】下，
# 由 player.gd 驱动触发动作（不响应独立输入，与第三人称共用同一套输入规则）。
#
# 动画分配（与 fp_gameplay.gd 一致）：
#   draw   -> 切入第一人称时播放（出枪）
#   idle   -> 平时循环（呼吸叠加）
#   shoot2 -> 射击（后坐，硬切重播，支持连发）
#   cidao1 -> 刺刀（前刺）
#   reload -> 换弹
# 音效（.dat 运行时 RIFF 解析，绕开 BWF 导入崩溃）：shoot/reload/bayonet/draw。
#
# 关键设计（与第三人称逻辑匹配）：
#   * 不创建自己的 Camera3D —— 挂到 player 的现有相机下，模型随相机移动/旋转；
#   * 触发接口 trigger_*/set_hold/update 由 player 每帧驱动，奔跑禁射(interrupt_shoot)
#     等规则在 player 层统一判定后调用；
#   * 动作播完自动回 idle（非循环动作一次即回），连发=硬切重播（stop+play）。
# ============================================================================

const VM_PATH := "res://fp_viewmodel/ak47_viewmodel.gltf"
## 实际使用的视图模型场景路径（默认共享 VM_PATH；角色专属 FP 手臂时由 player 注入）
var vm_scene_path: String = VM_PATH
# 【P3 多武器】以下为每武器可在运行期覆盖的项（由 player._apply_weapon_to_subsystems 注入）；
# 默认值=原硬编码常量，单武器(AK47)时不注入 → 行为完全不变。
var _fire_interval: float = AUTO_FIRE_INTERVAL   # 连发间隔（player 从 WeaponDef.fire_rate
var _fire_mode: String = "auto"                  # 射击模式（auto/single，player 从 WeaponDef.fire_mode 注入） 注入）
var _cfg_path: String = CFG_PATH                 # 摆放配置（player 从 WeaponDef.fp_viewmodel_cfg 注入）
var _reload_path: String = ""                    # 换弹动画（player 从 WeaponDef.fp_reload_anim 注入）；
												 # 空 = 用模型自带 reload 动画（M82 骨骼名与 AK47 不同，
												 # 默认 reload_fixed.tres 是 AK47 烘焙版，直接套会导致
												 # 轨道匹配不上 → 只有声音没有动画）
# 烘焙好的 reload 修改版（tools/bake_reload_fixed.gd 生成）：装回段平滑回位到 idle，
# 消除"弹匣掉下去又上来"。编辑器预览与实机共用，可在编辑器 F6 fp_reload.tscn 预览。
const RELOAD_FIXED_PATH := "res://fp_viewmodel/reload_fixed.tres"

# 动画名（与 fp_gameplay.gd 一致）
const ANIM_IDLE := "idle"
const ANIM_DRAW := "draw"
const ANIM_RELOAD := "reload"
const ANIM_SHOOT := "shoot2"
const ANIM_BAYONET := "cidao1"
# 【手雷】高爆手雷专用动画（v_gaobao_viewmodel.gltf 的 clip 名）
const ANIM_PULL := "plugin"   # 拉环
const ANIM_THROW := "Throw"   # 投掷
const BLEND_TIME := 0.05
const AUTO_FIRE_INTERVAL := 0.15   # 连发间隔（≈400发/分，与第一人称一致）
const RECOVERY_DUR := 0.18
const RECOVERY_ANIMS := ["shoot2"]

# 音效
const SFX_PATH_SHOOT := "res://audio/ak47hql_shoot2.dat"
const SFX_PATH_RELOAD := "res://audio/AK47-HQL_RELOAD.dat"
const SFX_PATH_BAYONET := "res://audio/AK47-HQL_KNIFE-ATTACK.dat"
const SFX_PATH_DRAW := "res://audio/AK47-HQL_BLOWBACK.dat"

# 镜像：源动画是左手持枪，运行时镜像成右手（与 fp_action_preview 一致）
const MIRROR_SCALE := Vector3(1.0, 1.0, -1.0)

# 相机/模型摆放配置（fp_view_config.tres，编辑器调好的"完美位置"）
const CFG_PATH := "res://fp_viewmodel/fp_view_config.tres"
# 默认值（config 缺失时兜底，与 FPViewConfig 默认一致）
const DEF_FP_GUN_POS := Vector3(0.10, -0.20, -0.70)
const DEF_FP_GUN_ROT := Vector3(0.0, 1.5708, 0.04)
const DEF_FP_CAM_POS := Vector3(0.0, 0.0, 0.0)
const DEF_FP_CAM_ROT := Vector3(0.0, 0.0, 0.0)
const DEF_FP_FOV := 70.0

var _cfg: Resource = null
var _fp_gun_pos := DEF_FP_GUN_POS
var _fp_gun_rot := DEF_FP_GUN_ROT
var _fp_cam_pos := DEF_FP_CAM_POS
var _fp_cam_rot := DEF_FP_CAM_ROT
var _fp_fov := DEF_FP_FOV
var _model_center_local := Vector3.ZERO  # 模型几何中心（相对模型原点，摆放修正用）
# 【P3 修复】center 只在模型刚加载(rest pose)时计算一次并缓存。
# 原因：_compute_model_center 遍历 skinned mesh 的 world AABB，其数值依赖骨骼姿势；
# 切枪/切视角后模型在播 draw/reload 动画，骨骼形变 → AABB 变化 → center 漂移 →
# 每次 _apply_pose 都重算会让模型摆放位置随动画浮动（M82 模型大、漂移更明显）。
var _center_dirty: bool = true
## 【手雷】摆放几何中心覆盖（fp_view_config 的 fp_center_override 注入）：
## 非零 = 强制用该值（预览场景量的静止姿势中心），不再调用 _compute_model_center，
## 避免 bind pose 顶点分散 23m 的手雷模型被骨架姿势污染 center。
var _center_override := Vector3.ZERO

var _model: Node3D = null
var _ap: AnimationPlayer = null
var _camera: Camera3D = null
var _sfx: AudioStreamPlayer = null            # 通用（出枪/换弹）
var _sfx_shoot_p: AudioStreamPlayer = null    # 射击音效独立播放器
var _sfx_bayonet_p: AudioStreamPlayer = null  # 刺刀音效独立播放器（打断射击时不切断枪声）
var _sfx_shoot: AudioStreamWAV = null
var _sfx_reload: AudioStreamWAV = null
var _sfx_bayonet: AudioStreamWAV = null
var _sfx_draw: AudioStreamWAV = null
var _fire_hold := false
var _fire_timer := 0.0
var _fire_blocked := false

# 【手雷】投掷手势状态（由 player 在武器==gaobao 时驱动）：
#   trigger_pull() 按下左键=拉环；拉环播完且仍按住 → _grenade_holding=true 停末帧；
#   release_pull(holding) 松开：holding=true → 投掷；false → 等拉环播完直接投掷（点按=4→1）。
# 点按（不蓄力）拉环播完也投掷：4→1→3；长按=拉环末帧保持，松开才投掷。
var _grenade_held := false
var _grenade_holding := false
## 投掷动作开始信号（player 连接后同步 3P Toss Grenade 投掷动画）
signal throw_started

## 【P3 多武器动画名映射】系统动作名 → 本武器实际动画名（WeaponDef.fp_anim_map 注入）。
## 空 = 全部用默认名（AK47 零变化）。缺省按"系统名原样"处理。
var _anim_map: Dictionary = {}

## 【P3 近战交替】射击动作的交替动画名（WeaponDef.fp_alt_shoot_anim 注入）。
## 每次触发射击在 shoot2 映射动画 与 本动画 间来回切换（单击=第1个，连点/长按=交替）。
var _alt_shoot_anim: String = ""
var _shoot_alt_toggle := false
var _shoot_alt_last_ms: int = 0           # 上次挥砍触发时刻（连击窗口判定用）
const SHOOT_ALT_COMBO_WINDOW_MS := 600    # 连击窗口：超过则单击回到第1段

## 【P3 静音开关】本武器无专属音效时置 true：所有 SFX 静默（不套用其它武器音效）。
var _silent := false

## 【P3 镜像开关】是否左右镜像（左手动画→右手）。默认 true；个别源就右手的置 false。
var _mirror := true

## 切换武器时由 player 注入静音开关（WeaponDef.silent）。
func set_silent(v: bool) -> void:
	_silent = v

## 切换武器时由 player 注入镜像开关（WeaponDef.fp_mirror）。
## 改镜像必须重测几何中心（scale 变了 center 就变）→ _center_dirty + _apply_pose。
func set_mirror(v: bool) -> void:
	if _mirror == v:
		return
	_mirror = v
	_center_dirty = true
	_apply_pose()

## 解析系统动作名到本武器实际动画名：优先映射表，无则原样。
func _resolve_anim(n: String) -> String:
	if _anim_map.has(n):
		return String(_anim_map[n])
	return n

func is_fire_blocked() -> bool:
	return _fire_blocked

func set_fire_blocked(v: bool) -> void:
	_fire_blocked = v

# 供 player/相机控制器读取第一人称相机参数（来自 fp_view_config.tres）
func get_cam_pos() -> Vector3:
	return _fp_cam_pos

func get_cam_rot() -> Vector3:
	return _fp_cam_rot

func get_fov() -> float:
	return _fp_fov

## 【封装】公共访问器（替代 player 侧字符串反射 get("_model")/_model 直取：
## 私有成员改名后 get() 静默返回 null 而非报错）
func get_model() -> Node3D:
	return _model

## 【封装】射击长枪声专用播放器（切枪时 player 把它摘走续播，见 _rebuild_fp_viewmodel）
func get_shoot_sfx_player() -> AudioStreamPlayer:
	return _sfx_shoot_p

## 【封装】释放视图模型资源（挂在相机下的 _model）。
## 【崩溃修复】本方法【不能 free 自身】：对象正在执行自己的方法时处于锁定状态
## （"Attempted to free a locked object (calling or emitting)"）——切尼泊尔等
## 带专属 FP 模型的武器会走 _rebuild_fp_viewmodel → dispose()，在 dispose 内
## free(self) 必崩。自身由调用方（player._rebuild_fp_viewmodel）在本方法返回、
## 调用栈脱离本对象后再 free。
func dispose() -> void:
	if _model != null and is_instance_valid(_model):
		if _model.get_parent() != null:
			_model.get_parent().remove_child(_model)
		_model.free()
		_model = null

# 立即打断射击动作（奔跑进入瞬间）：停动作、停连发。不打断刺刀。
# 【修复】判定复用 is_shoot()：原先只匹配 shoot2_preview，漏掉交替动作
# shoot2_alt_preview（尼泊尔 midslash2 挥砍瞬间进奔跑 → 1P 动作残留，
# 与 3P 影子/移动状态脱节）。
func interrupt_shoot() -> void:
	_fire_hold = false
	_fire_timer = 0.0
	if is_shoot():
		_play_named(ANIM_IDLE)

func setup(p_camera: Camera3D) -> void:
	_camera = p_camera
	_load_config()
	# 【P3 换皮】视图模型场景可注入：默认共享 ak47_viewmodel.gltf；角色资产配了
	# fp_viewmodel_scene（如戴手套的专属手臂）时由 player 在 setup 前覆盖本字段。
	var ps: PackedScene = load(vm_scene_path)
	if ps == null:
		push_warning("FPViewmodel: 无法加载 " + vm_scene_path)
		return
	_model = ps.instantiate() as Node3D
	_model.name = "FPViewModel"
	# 第一人称视图模型不向世界投射阴影：否则 FP 下会多出一个"第一人称枪影"，
	# 且该模型带镜像缩放(scale.z=-1)，其影子左右相反，会干扰/误认成 3P 角色本影。
	# FP 下仅保留 3P 角色(SHADOWS_ONLY)的影子作为地面投影即可。
	for _mi in _model.find_children("*", "GeometryInstance3D", true, false):
		var _m := _mi as GeometryInstance3D
		if _m != null:
			_m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 枪口火光贴图设为无光照： shoot 动画里的火光不受全局光照/阴影影响，始终满亮。
	_force_muzzle_flash_unshaded(_model)
	# 直接挂到传入的主相机下，完全跟随相机（含俯仰）。
	# （曾尝试"始终可见"方案：no_depth_test 材质破坏手/枪透视、SubViewport 掉帧、
	#   锚点方案不跟俯仰改变构图——均被用户否决，穿地问题接受现状）
	p_camera.add_child(_model)
	_ap = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _ap == null:
		push_warning("FPViewmodel: 未找到 AnimationPlayer")
		return
	if not _ap.animation_finished.is_connected(_on_anim_finished):
		_ap.animation_finished.connect(_on_anim_finished)
	_sfx = AudioStreamPlayer.new()
	add_child(_sfx)
	_sfx_shoot_p = AudioStreamPlayer.new()
	add_child(_sfx_shoot_p)
	_sfx_bayonet_p = AudioStreamPlayer.new()
	add_child(_sfx_bayonet_p)
	_sfx_shoot = _load_sfx_wav(SFX_PATH_SHOOT)
	_sfx_reload = _load_sfx_wav(SFX_PATH_RELOAD)
	_sfx_bayonet = _load_sfx_wav(SFX_PATH_BAYONET)
	_sfx_draw = _load_sfx_wav(SFX_PATH_DRAW)
	# 按当前配置摆放模型（先镜像 scale → 算几何中心 → 相机逆*模型根）
	_apply_pose()
	_model.visible = false  # 默认隐藏，V 键切换后才显示
	# 初始播放 idle（不显示，但动画就绪，切入时无延迟）
	_play_named(ANIM_IDLE)
	# 预创建全部动作 preview（draw/reload/shoot2/cidao1/plugin/Throw）：首次触发即 hard 立即播放，
	# 避免"第一枪"走 _make_dup_and_play 的 BLEND_TIME 淡入插入导致动画异常。
	for _a in ["draw", "reload", "shoot2", "cidao1", "plugin", "Throw"]:
		_ensure_preview(_a)

## 强制 FP 视图模型中的枪口火光材质不受全局光照影响（Unshaded）。
## 通过材质名或 albedo 贴图路径识别"独立枪火(s_qianguho)"对应的子网格表面，
## 让 shoot 动画里的火光始终按贴图原色满亮显示，不被场景灯光/阴影/环境光压暗。
## （第三人称角色模型 character.tscn 里火光标记材质本就设为 shading_mode=0 无光照，
##   这里与之一致：枪口火光本来就该是"自发光/不受光"的贴图。）
func _force_muzzle_flash_unshaded(model_root: Node3D) -> void:
	if model_root == null:
		return
	for _mi in model_root.find_children("*", "MeshInstance3D", true, false):
		var mesh := _mi as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			continue
		var surf_count: int = mesh.mesh.get_surface_count()
		for i in range(surf_count):
			var mat: Material = mesh.get_active_material(i)
			if mat == null or not (mat is StandardMaterial3D):
				continue
			var sm := mat as StandardMaterial3D
			# 已经无光照则跳过
			if sm.shading_mode == StandardMaterial3D.SHADING_MODE_UNSHADED:
				continue
			var rn: String = sm.resource_name if sm.resource_name != null else ""
			var tex_path: String = ""
			if sm.albedo_texture != null:
				tex_path = sm.albedo_texture.resource_path if sm.albedo_texture.resource_path != null else ""
			# "qianguho" 是"独立枪火"（枪口火光）在 GLTF 里乱码化的材质/贴图名
			if "qianguho" in rn.to_lower() or "qianguho" in tex_path.to_lower():
				var new_mat: StandardMaterial3D = sm.duplicate()
				# 仅关掉受光：unshaded 后只按 albedo 贴图原色显示，
				# 不再被灯光/阴影/环境光调制（不再叠自发光，避免把火光洗成纯白块）。
				new_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
				mesh.set_surface_override_material(i, new_mat)

## 注：曾经的"低头穿地"尝试均已废弃（用户否决）：
## - 逐表面材质 no_depth_test/transparent → 破坏手/枪深度透视；
## - SubViewport 深度隔离 → 每帧全屏额外渲染掉帧；
## - 锚点方案（跟位置+偏航不跟俯仰）→ 改变构图。
## 现保持原始方案：viewmodel 直接挂主相机下完全跟随（含俯仰），穿地问题接受现状。

func _load_config() -> void:
	var res: Resource = load(_cfg_path)
	if res == null:
		return
	_cfg = res
	var gp: Variant = _cfg.get("fp_gun_pos")
	if gp is Vector3:
		_fp_gun_pos = gp
	var gr: Variant = _cfg.get("fp_gun_rot")
	if gr is Vector3:
		_fp_gun_rot = gr
	var cp: Variant = _cfg.get("fp_cam_pos")
	if cp is Vector3:
		_fp_cam_pos = cp
	var cr: Variant = _cfg.get("fp_cam_rot")
	if cr is Vector3:
		_fp_cam_rot = cr
	var fv: Variant = _cfg.get("fp_fov")
	if fv is float:
		_fp_fov = fv
	var co: Variant = _cfg.get("fp_center_override")
	if co is Vector3:
		_center_override = co

# 按当前 _fp_gun_pos/rot + _fp_cam_pos/rot 摆放模型（先镜像 scale 再算几何中心）。
# setup() 与 set_config_paths() 共用：换武器配置后必须重摆，否则留在上一把枪的位置。
# 数学：模型相对根 = T(fp_gun_pos-center) * R(fp_gun_rot)；相机相对根 = T(fp_cam_pos) * R(fp_cam_rot)；
# 模型挂相机下 => 局部变换 = 相机逆 * 模型根，构图与调好的"完美位置"一致。
func _apply_pose() -> void:
	if _model == null:
		return
	# 镜像开关：默认 (1,1,-1) 左右镜像成右手；fp_mirror=false 的武器保持源朝向（尼泊尔等）
	_model.scale = MIRROR_SCALE if _mirror else Vector3.ONE
	if _center_dirty:
		# 有覆盖值直接用（手雷等 bind pose 分散模型），否则自动计算
		_model_center_local = _center_override if _center_override != Vector3.ZERO else _compute_model_center()
		_center_dirty = false
	var ref_cam := Transform3D(Basis.from_euler(_fp_cam_rot), _fp_cam_pos)
	var model_root := Transform3D(Basis.from_euler(_fp_gun_rot), _fp_gun_pos - _model_center_local)
	var rel: Transform3D = ref_cam.affine_inverse() * model_root
	_model.position = rel.origin
	_model.rotation = rel.basis.get_euler()

# 单网格的世界空间 AABB（用 8 个角点经 global_transform 变换后 expand 得到，同 fp_action_preview）
func _mesh_world_aabb(m: MeshInstance3D) -> AABB:
	var la := m.get_aabb()
	var gt: Transform3D = m.global_transform
	var box := AABB()
	var have := false
	for xi in [0, 1]:
		for yi in [0, 1]:
			for zi in [0, 1]:
				var wp := gt * (la.position + Vector3(la.size.x * xi, la.size.y * yi, la.size.z * zi))
				if not have:
					box.position = wp
					box.size = Vector3.ZERO
					have = true
				else:
					box = box.expand(wp)
	return box

# 模型几何中心（相对模型自身原点）。
# 【P3 修复】改在【模型本地空间】计算（各网格 local AABB 合并），不再用世界 AABB。
# 原因：世界 AABB 是轴对齐包围盒，当模型带旋转(0,1.57,0.04)+镜像(1,1,-1)时，
# 旋转后 expand 得到的 AABB 中心 ≠ 几何真实中心（探针挂 identity 相机时碰巧相等，
# 游戏里相机带旋转/位移 → center 偏移 → 枪摆放错位、切枪后漂移）。
# 本地空间计算只依赖网格几何与骨骼 rest pose，与相机变换/模型 rotation 完全无关，稳定。
func _compute_model_center() -> Vector3:
	if _model == null:
		return Vector3.ZERO
	var model_inv := _model.global_transform.affine_inverse()
	var comb := AABB()
	var have := false
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var la := m.get_aabb()
		# 网格相对模型的本地变换（消掉相机/模型自身变换）
		var local_xf: Transform3D = model_inv * m.global_transform
		var b := AABB()
		var bh := false
		for xi in [0, 1]:
			for yi in [0, 1]:
				for zi in [0, 1]:
					var lp := la.position + Vector3(la.size.x * xi, la.size.y * yi, la.size.z * zi)
					var wp := local_xf * lp
					if not bh:
						b.position = wp
						b.size = Vector3.ZERO
						bh = true
					else:
						b = b.expand(wp)
		if not have:
			comb = b
			have = true
		else:
			comb = comb.merge(b)
	if not have:
		return Vector3.ZERO
	return comb.get_center()

func set_visible(v: bool) -> void:
	if _model != null:
		_model.visible = v

func _play_named(n: String, hard: bool = false) -> void:
	if _ap == null:
		return
	var local_name := n + "_preview"
	if _ap.has_animation(local_name):
		var anim: Animation = _ap.get_animation(local_name)
		anim.loop_mode = 1 if n == ANIM_IDLE else 0
		# 动作统一原速播放：先重置 speed_scale（防 reload 专用路径设置的放慢/加速残留，
		# 导致后续 draw/shoot/刺刀 带错误速度播放）；trigger_reload_duration 会随后覆盖。
		_ap.speed_scale = 1.0
		if hard:
			_ap.stop()
			_ap.play(local_name, 0.0)
		else:
			_ap.play(local_name, BLEND_TIME)
	else:
		# 首次：创建 dup（含呼吸/回位尾巴）并播放
		# 【修复·第一枪】hard 语义穿透：触发方要求立即播放（射击/切枪）时，
		# 即使 preview 缺失走首次创建路径，也不得用 BLEND_TIME 淡入。
		_make_dup_and_play(n, hard)

# 创建 dup 动画（呼吸叠加 + 动作回位尾巴），与 fp_action_preview/fp_gameplay 一致
func _make_dup_and_play(n: String, hard: bool = false) -> void:
	_ensure_preview(n)
	if _ap != null and _ap.has_animation(n + "_preview"):
		_ap.speed_scale = 1.0
		_ap.play(n + "_preview", BLEND_TIME if (not hard and n != ANIM_IDLE) else 0.0)

# 确保动作 preview 动画已创建（幂等）：只创建不播放。供 setup 预建全部动作，
# 使运行时首触发走 hard 立即播放（无淡入插入的首次创建延迟）。
func _ensure_preview(n: String) -> void:
	if _ap == null or _ap.has_animation(n + "_preview"):
		return
	# 【P3 动画名映射】源动画用实际名（v_deagle: idle→idle1；尼泊尔: shoot2→midslash1）；
	# preview 名仍用系统动作名（n+"_preview"），下游 is_*()/ends_with 判断不变。
	var real: String = _resolve_anim(n)
	if not _ap.has_animation(real):
		return
	var src: Animation = _ap.get_animation(real)
	var dup: Animation = src.duplicate()
	if n == ANIM_IDLE:
		_apply_breath(dup)
	elif n == ANIM_RELOAD:
		# 用烘焙好的修改版 reload（装回段平滑回位到 idle，消除"弹匣掉下去又上来"）。
		# 总长不变 1.684，实机 speed_scale 同步逻辑不受影响；末帧=idle 切 idle 无缝。
		# 注意：_reload_path 为空（M82 等无烘焙版）→ 用模型自带 reload 动画，
		# 否则 AK47 烘焙版轨道（Bone01 等）匹配不上 M82 骨骼（L_Hand 等）→ 只有声音没动画。
		if _reload_path != "" and ResourceLoader.exists(_reload_path):
			var fixed: Animation = load(_reload_path)
			if fixed != null:
				dup = fixed.duplicate()
	_on_action_duplicated(dup, n)
	dup.loop_mode = 1 if n == ANIM_IDLE else 0
	var local_name := n + "_preview"
	var libs: PackedStringArray = _ap.get_animation_library_list()
	var lib: AnimationLibrary
	if libs.size() > 0:
		lib = _ap.get_animation_library(libs[0])
	else:
		lib = AnimationLibrary.new()
		_ap.add_animation_library("", lib)
	if lib.has_animation(local_name):
		lib.remove_animation(local_name)
	lib.add_animation(local_name, dup)

# 动作末帧回位尾巴：把动作 dup 末尾接到 idle 首帧姿态，消除切换跳变（与 fp_gameplay 一致）
func _on_action_duplicated(anim: Animation, n: String) -> void:
	if not n in RECOVERY_ANIMS:
		return
	if _ap == null or not _ap.has_animation(_resolve_anim(ANIM_IDLE)):
		return
	var idle: Animation = _ap.get_animation("idle_preview") if _ap.has_animation("idle_preview") else _ap.get_animation(_resolve_anim(ANIM_IDLE))
	var body_end: float = anim.length
	var tail_time := body_end + RECOVERY_DUR
	for t in anim.get_track_count():
		var sp := str(anim.track_get_path(t))
		var kc: int = anim.track_get_key_count(t)
		if kc == 0:
			continue
		var target: Variant
		var idle_t := -1
		for it in idle.get_track_count():
			if str(idle.track_get_path(it)) == sp and idle.track_get_type(it) == anim.track_get_type(t):
				idle_t = it
				break
		if idle_t >= 0:
			target = idle.track_get_key_value(idle_t, 0)
		else:
			continue
		var last_time: float = anim.track_get_key_time(t, kc - 1)
		if last_time < body_end - 0.001:
			anim.track_set_key_time(t, kc - 1, body_end)
		anim.track_insert_key(t, tail_time, target)
		anim.track_set_interpolation_type(t, Animation.INTERPOLATION_LINEAR)
	anim.length = tail_time

# 呼吸叠加（idle）：复用角色呼吸波形（与 fp_action_preview 一致，简化版）
func _apply_breath(anim: Animation) -> void:
	var breath: Dictionary = _load_breath()
	if breath.is_empty() or not breath.has("times"):
		return
	var skel := _model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null:
		return
	var root_bi := -1
	for i in skel.get_bone_count():
		if skel.get_bone_parent(i) < 0:
			root_bi = i
			break
	if root_bi < 0:
		return
	var bone_name: String = skel.get_bone_name(root_bi)
	var pos_track := -1
	var rot_track := -1
	for t in anim.get_track_count():
		var sp := str(anim.track_get_path(t))
		if sp.ends_with(":" + bone_name):
			if anim.track_get_type(t) == Animation.TYPE_POSITION_3D:
				pos_track = t
			elif anim.track_get_type(t) == Animation.TYPE_ROTATION_3D:
				rot_track = t
	if pos_track < 0 and rot_track < 0:
		return
	var base_pos := Vector3.ZERO
	var base_rot := Quaternion.IDENTITY
	if pos_track >= 0 and anim.track_get_key_count(pos_track) > 0:
		base_pos = anim.track_get_key_value(pos_track, 0)
	if rot_track >= 0 and anim.track_get_key_count(rot_track) > 0:
		base_rot = anim.track_get_key_value(rot_track, 0)
	var times: Array = breath["times"]
	var yw: Array = breath["hips_y_wave"]
	var rw: Array = breath["spine_rotx_wave"]
	var rot_amp: float = deg_to_rad(0.6)
	var nk := mini(times.size(), mini(yw.size(), rw.size()))
	for i in nk:
		var t: float = times[i]
		var y: float = yw[i] * 0.012 * 2.0
		if pos_track >= 0:
			anim.track_insert_key(pos_track, t, base_pos + Vector3(0.0, y, 0.0))
		if rot_track >= 0:
			var wob: Quaternion = Quaternion.from_euler(Vector3(rw[i] * rot_amp * 2.0, 0.0, 0.0))
			anim.track_insert_key(rot_track, t, base_rot * wob)
	if pos_track >= 0:
		anim.track_set_interpolation_type(pos_track, Animation.INTERPOLATION_LINEAR)
	if rot_track >= 0:
		anim.track_set_interpolation_type(rot_track, Animation.INTERPOLATION_LINEAR)

var _breath_cache: Dictionary = {}
func _load_breath() -> Dictionary:
	if not _breath_cache.is_empty():
		return _breath_cache
	var f := FileAccess.open("res://fp_viewmodel/breath_idle.json", FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		_breath_cache = parsed
	return _breath_cache

func _play_sfx(stream: AudioStream, p: AudioStreamPlayer = null, pitch: float = 1.0) -> void:
	if _silent:
		return  # 【P3 静音】本武器无专属音效：不播任何声音（不套用其它武器音效）
	if p == null:
		p = _sfx
	if p == null or stream == null:
		return
	p.stream = stream
	p.pitch_scale = pitch
	p.play()

func _on_anim_finished(anim_name: StringName) -> void:
	var nm := String(anim_name)
	if nm.ends_with("_preview"):
		nm = nm.trim_suffix("_preview")
	if nm == ANIM_PULL:
		# 拉环播完：按住 → 停末帧 holding（松开才投掷）；已松开（点按）→ 直接投掷（4→1→3）
		if _grenade_held:
			_grenade_holding = true
			if _ap != null:
				_ap.pause()
		else:
			_play_named(ANIM_THROW, true)
			throw_started.emit()
	elif nm == ANIM_THROW:
		# 投掷播完回待机
		_grenade_holding = false
		_play_named(ANIM_IDLE, true)
	elif nm == ANIM_DRAW or nm == ANIM_RELOAD or nm == ANIM_SHOOT or nm == ANIM_SHOOT + "_alt" or nm == ANIM_BAYONET:
		_play_named(ANIM_IDLE)

# ---------- 触发接口（由 player 输入规则驱动） ----------
func trigger_draw() -> void:
	_play_named(ANIM_DRAW, true)
	_play_sfx(_sfx_draw)

# ---------- 手雷投掷手势（由 player 在武器==gaobao 时驱动） ----------
## 左键按下：拉环（plugin）。若正在播其它动作先复位。
func trigger_pull() -> void:
	_grenade_held = true
	_grenade_holding = false
	if _ap != null and _ap.is_playing():
		_ap.pause()
	_play_named(ANIM_PULL, true)

## 左键松开。holding=true（长按到拉环末帧）→ 投掷；false（点按）→ 拉环播完自动投掷。
func release_pull(holding: bool) -> void:
	_grenade_held = false
	if holding:
		_grenade_holding = false
		_play_named(ANIM_THROW, true)
		throw_started.emit()

## 是否处于"长按拉环末帧"状态（player 松手时据此决定投掷）。
func is_grenade_holding() -> bool:
	return _grenade_holding

func trigger_shoot() -> void:
	if _fire_blocked:
		return  # 地面奔跑中禁止射击（换弹中按射击=取消换弹并开火，由 player 统一处理；
				# 长按自动连发由 update() 的 not is_reload() 守卫拦截，不在此挡，否则连"取消换弹"也被误杀）
	# 【P3 近战交替】有交替动画：每次触发在 shoot2 映射 与 交替动画 间切换
	# （单击=第1个 midslash1；连点/长按=交替 midslash1/midslash2，复用连发机制）。
	if _alt_shoot_anim != "":
		# 【修复】单击=第1段：距上次挥砍超过连击窗口时回到第1段。
		# 原先 toggle 永不超时复位 → 隔很久的两次单击也会 1→2 交替。
		var _now_ms := Time.get_ticks_msec()
		if _shoot_alt_last_ms == 0 or _now_ms - _shoot_alt_last_ms > SHOOT_ALT_COMBO_WINDOW_MS:
			_shoot_alt_toggle = false
		_shoot_alt_last_ms = _now_ms
		_shoot_alt_toggle = not _shoot_alt_toggle
		if _shoot_alt_toggle:
			_play_named(ANIM_SHOOT, true)
		else:
			_play_alt_shoot(true)
	else:
		_play_named(ANIM_SHOOT, true)
	# 【射速语义·中断式】单发枪械连续射击 = 新射击硬中断上一发动画（本函数的
	# stop+play 即中断），节奏由 fire_rate 决定——不做动画加速（用户明确要求）。
	# 锁的提前释放见 is_shoot_locked()（player 射击锁用）。
	_play_sfx(_sfx_shoot, _sfx_shoot_p)

# 播放交替射击动画（近战挥砍第2段）：直接播真实动画名（不进 anim_map 的 shoot2 键）。
func _play_alt_shoot(hard: bool) -> void:
	if _ap == null:
		return
	var real: String = _alt_shoot_anim
	if not _ap.has_animation(real):
		_play_named(ANIM_SHOOT, true)  # 交替动画缺失 → 退化到主动画
		return
	# 复用 preview 机制：确保存在 "shoot2_alt_preview" 并播放
	var local_name := ANIM_SHOOT + "_alt_preview"
	if not _ap.has_animation(local_name):
		if not _ap.has_animation(real):
			_play_named(ANIM_SHOOT, true)
			return
		var src: Animation = _ap.get_animation(real)
		var dup: Animation = src.duplicate()
		_on_action_duplicated(dup, ANIM_SHOOT)
		dup.loop_mode = 0
		var libs: PackedStringArray = _ap.get_animation_library_list()
		var lib: AnimationLibrary = _ap.get_animation_library(libs[0]) if libs.size() > 0 else null
		if lib == null:
			lib = AnimationLibrary.new()
			_ap.add_animation_library("", lib)
		lib.add_animation(local_name, dup)
	_ap.speed_scale = 1.0
	if hard:
		_ap.stop()
		_ap.play(local_name, 0.0)
	else:
		_ap.play(local_name, BLEND_TIME)

func trigger_bayonet() -> void:
	if _fire_blocked:
		return
	_play_named(ANIM_BAYONET, true)
	_play_sfx(_sfx_bayonet, _sfx_bayonet_p)  # 独立播放器：刺刀打断射击时枪声继续播完

func trigger_reload() -> void:
	_play_named(ANIM_RELOAD, true)
	_play_sfx(_sfx_reload)

# 立即停掉换弹音效（仅当通用 _sfx 播放器当前正在播换弹音时）。
# 换弹被打断（射击等）/ 切视角 / 死亡复活时：3P 由 player 调 _fp_action.stop_reload()，
# FP 需同步停自身通用 _sfx 播放器的换弹声，避免"动作已收尾但换弹声还在响"。
# 必须判 _sfx.stream == _sfx_reload：通用 _sfx 也用于出枪(draw)音，
# 不能一刀切把出枪声也停了（否则切角色后出枪声被误杀）。
func stop_reload_sound() -> void:
	if _sfx != null and _sfx.playing and _sfx.stream == _sfx_reload:
		_sfx.stop()

# 第一人称 reload 动画原始时长（秒）——换弹时长的基准（3P 换弹总时长对齐此值）。
# 取不到返回 -1，调用方按原逻辑兜底。
func get_reload_anim_duration() -> float:
	if _ap != null and _ap.has_animation(_resolve_anim(ANIM_RELOAD)):
		return _ap.get_animation(_resolve_anim(ANIM_RELOAD)).length
	return -1.0

# 换弹（带速度匹配）：speed = 动画原始时长 / 目标时长。
# FP 模式下由 player 传 _reload_duration，使 viewmodel reload 与 3P 换弹固定时长
# 完全同步（结束瞬间动画恰好播完回 idle，换弹完成/被打断节奏一致）。
# 换弹（带速度匹配 + 续播）：speed = 动画原始时长 / 目标时长。
# target_dur：本段要铺满的时长（秒）。start_progress：从归一化进度[0,1]续播
# （切第一人称中途换弹时传入当前进度，使 FP 与 3P 同一相位，不再从 0 重播）。
# play_sfx：是否播放换弹音效。中途续播（切视角）传 false，避免与已停的 3P 换弹声叠加/重播。
func trigger_reload_duration(target_dur: float, start_progress: float = 0.0, play_sfx: bool = true) -> void:
	if _ap == null:
		return
	_play_named(ANIM_RELOAD, true)
	if _ap.is_playing():
		# 用实际播放的 reload_preview 长度算 speed（reload_fixed 可能比源动画长，
		# 例如分段式装回：装匣+回正+放下 总长 2.0；必须按它对齐 target_dur）
		var src: Animation = null
		if _ap.has_animation(ANIM_RELOAD + "_preview"):
			src = _ap.get_animation(ANIM_RELOAD + "_preview")
		else:
			src = _ap.get_animation(_resolve_anim(ANIM_RELOAD))
		if src != null and src.length > 0.01 and target_dur > 0.01:
			_ap.speed_scale = src.length / target_dur
			# 续播：seek 到归一化进度对应的动画秒，使 FP 从与 3P 相同的相位继续，
			# 而非从 0 重播——切视角中途换弹时两端姿势不再错开。
			var p := clampf(start_progress, 0.0, 0.999)
			_ap.seek(p * src.length, true)
	if play_sfx:
		# 【换弹声时长跟随动画】新换弹音效时长可能与 target_dur(换弹动画时长) 不一致，
		# 用 pitch_scale 把声音拉伸/压缩到恰好铺满 target_dur，使声音与换弹动画同时结束
		# （声音短则放慢、长则加快，避免提前静音或拖尾）。target_dur<=0 时不拉伸。
		var _nat: float = _sfx_reload.get_length() if _sfx_reload != null else 0.0
		var _pitch: float = 1.0
		if _nat > 0.01 and target_dur > 0.01:
			_pitch = _nat / target_dur
		_play_sfx(_sfx_reload, null, _pitch)

func set_hold(v: bool) -> void:
	_fire_hold = v
	if v:
		_fire_timer = _fire_interval

## 立即回 idle（角色切换/复活等强制复位用）：清掉残留的换弹/出枪动画，
## 避免切换角色后 FP viewmodel 还在播旧角色的动作。
func reset_to_idle() -> void:
	if _ap == null:
		return
	_play_named(ANIM_IDLE, true)
	_ap.speed_scale = 1.0

## 【P3 多武器】切换武器时由 player 注入连发间隔（秒/发）；<=0 忽略（保留当前）。
func set_fire_interval(v: float) -> void:
	if v > 0.0:
		_fire_interval = v

## 【射速同步】切换武器时由 player 注入射击模式（auto/single）。
## 单发武器的射击动画会压缩到 _fire_interval 节奏（见 trigger_shoot）。
func set_fire_mode(m: String) -> void:
	_fire_mode = m

## 切换武器时由 player 注入新武器音效路径；空字符串=保留当前，不重载。
func set_sfx_paths(shoot: String, bay: String, reload: String) -> void:
	if shoot != "":
		var s := _load_sfx_wav(shoot)
		if s != null: _sfx_shoot = s
	if bay != "":
		var b := _load_sfx_wav(bay)
		if b != null: _sfx_bayonet = b
	if reload != "":
		var r := _load_sfx_wav(reload)
		if r != null: _sfx_reload = r

## 切换武器时由 player 注入新武器摆放配置/换弹动画路径。
## cfg 为空 = 回退默认共享配置（AK47）；reload_anim 为空 = 用模型自带 reload。
## 【P3 修复】之前 cfg 为空时直接跳过，导致切回 AK47（fp_viewmodel_cfg 为空）后
## 仍沿用上一把武器(M82)的 _cfg_path → 模型位置错乱。必须每次切枪都重载配置+重摆。
func set_config_paths(cfg: String, reload_anim: String) -> void:
	_center_dirty = true   # 【F-05】换武器配置后必须重测几何中心，避免复用同 VM 场景但网格不同时沿用上一把枪的旧中心
	_cfg_path = cfg if cfg != "" else CFG_PATH
	_load_config()
	_apply_pose()   # 换配置后必须重摆模型，否则枪留在上一把的位置
	if reload_anim != "":
		_reload_path = reload_anim
	else:
		_reload_path = ""   # 空 → 用模型自带 reload（M82 骨骼与 AK47 烘焙版不匹配）

## 【P3 多武器动画名映射】注入系统动作名→本武器实际动画名（WeaponDef.fp_anim_map）。
## 空字典 = 零变化（AK47）。必须在 setup() 之后注入并【重建已创建的 preview 动画】：
## 切换武器后旧 preview（如 idle_preview 源自 AK47 idle）仍存在，直接复用会播放旧骨骼轨道。
## 处理：清掉全部 *_preview 动画（下个动作触发时 _ensure_preview 按新映射重建）。
func set_anim_map(map: Dictionary) -> void:
	_anim_map = map
	if _ap == null:
		return
	# 清掉旧 preview（含 idle_preview），确保新映射生效时全部按新武器动画重建
	var libs: PackedStringArray = _ap.get_animation_library_list()
	for lname in libs:
		var lib := _ap.get_animation_library(lname)
		if lib == null:
			continue
		for an in lib.get_animation_list():
			if String(an).ends_with("_preview"):
				lib.remove_animation(an)
	# 立即回 idle（新武器动画），避免切枪后 FP 停在旧武器姿态
	_play_named(ANIM_IDLE, true)
	# 【修复·第一枪异常】上面的清理把 setup 预建的全部动作 preview 一并清掉了
	# （只重建了 idle），武器应用后的第一枪因此走 _make_dup_and_play 的
	# BLEND_TIME 淡入 → 首枪动画/枪口火焰从 idle 姿态渐入，表现异常。
	# 这里按 setup 的同一清单重新预建，保证任何时刻动作 preview 都已就绪。
	for _a in ["draw", "reload", "shoot2", "cidao1", "plugin", "Throw"]:
		_ensure_preview(_a)

## 【P3 近战交替】注入射击交替动画名（WeaponDef.fp_alt_shoot_anim）；空=不交替。
## 必须在 set_anim_map 之后调用（内部会重建 preview 动画并回 idle）。
func set_alt_shoot_anim(name: String) -> void:
	_alt_shoot_anim = name
	_shoot_alt_toggle = false
	_shoot_alt_last_ms = 0
	if _ap == null:
		return
	# 清掉旧的 shoot2_alt_preview（切武器时交替动画变了）
	var libs: PackedStringArray = _ap.get_animation_library_list()
	for lname in libs:
		var lib := _ap.get_animation_library(lname)
		if lib == null:
			continue
		if lib.has_animation(ANIM_SHOOT + "_alt_preview"):
			lib.remove_animation(ANIM_SHOOT + "_alt_preview")

# 状态查询（供 player 输入规则判定，与 FPActionRetarget 对齐）
func is_active() -> bool:
	return _ap != null and _ap.is_playing() and not _ap.current_animation.ends_with(ANIM_IDLE + "_preview")

func is_bayonet() -> bool:
	return _ap != null and _ap.is_playing() and _ap.current_animation.ends_with(ANIM_BAYONET + "_preview")

func is_shoot() -> bool:
	return _ap != null and _ap.is_playing() and (_ap.current_animation.ends_with(ANIM_SHOOT + "_preview") or _ap.current_animation.ends_with(ANIM_SHOOT + "_alt_preview"))

## 【射速语义·中断式】单发武器射击锁：射击动画播放中【且进度未达 fire_rate 间隔】。
## 进度超过间隔后锁提前释放（此时动画可能仍在播回稳段），玩家再次点击 =
## trigger_shoot 的 stop+play 硬中断上一发动画、从起手帧重播——即"连续射击用
## 中断动画，而不是加速动画"。动画比间隔短时自然退化为"动画播完才能再射"。
func is_shoot_locked() -> bool:
	if not is_shoot() or _fire_interval <= 0.0:
		return false
	return _ap.current_animation_position < _fire_interval

func is_draw() -> bool:
	return _ap != null and _ap.is_playing() and _ap.current_animation.ends_with(ANIM_DRAW + "_preview")

func is_reload() -> bool:
	return _ap != null and _ap.is_playing() and _ap.current_animation.ends_with(ANIM_RELOAD + "_preview")

# 每帧驱动：连发（与 FP 射速一致）
func update(delta: float) -> void:
	if _fire_hold and not _fire_blocked and not is_reload():
		_fire_timer -= delta
		if _fire_timer <= 0.0:
			_fire_timer = _fire_interval
			trigger_shoot()

# ---------- 音效解析（.dat，绕开 BWF WAV 导入崩溃） ----------
func _load_sfx_wav(res_path: String) -> AudioStreamWAV:
	return AudioWavLoader.load_wav(res_path)
