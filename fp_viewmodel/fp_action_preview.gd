@tool
extends Node3D
# ============================================================================
# fp_action_preview.gd — 第一人称动作预览（统一脚本，供各拆分场景共用）
# ----------------------------------------------------------------------------
# 用法：每个动画一个场景文件(.tscn)，只改本脚本的 `action` 导出值即可预览对应动作。
#
# 相机配置集中在共享资源 fp_view_config.tres（FPViewConfig）：
#   打开任一个 fp_*.tscn，选中根节点，在检视面板找到 "Config" 属性并展开，
#   即可改 fp_gun_pos / fp_gun_rot / fp_fov / fp_cam_pos / fp_cam_rot（第一人称）
#   或 tt_fov 等（转盘）。改一处、存盘，7 个场景全部生效（它们都引用同一个 .tres）。
#
# 编辑器内：直接呈现“第一人称”视图；相机由共享 fp_cam_pos/fp_cam_rot 驱动，
#           在视口里拖动相机即写回配置 => 其他 6 个场景 + 运行时(F6) 全同步。
#           也可以不改拖动，直接在检视面板改 Config 的 fp_cam_pos / fp_cam_rot。
# 运行时(F6)：转盘(turntable) 绕模型转查建模；按 F 切第一人称贴相机；ESC 释放鼠标。
#
# 已知修复：SCALE=1.0（Godot 已应用 Armature 0.0254）；动画用 AnimationLibrary
#           add/remove（Godot4 不在 AnimationPlayer 上）；loop 由 loop_action/编辑器决定；
#           几何中心用 model.to_local() 计算，与父节点/初始位置无关 => 存盘重载不漂移。
# ============================================================================

const SCALE := 1.0

# 默认相机配置（当场景未指定 config 时使用）
const DEF_TT_FOV := 50.0
const DEF_FP_FOV := 70.0
const DEF_TT_DIST := 2.4
const DEF_TT_PITCH := 0.18
const DEF_FP_GUN_POS := Vector3(0.10, -0.20, -0.70)
const DEF_FP_GUN_ROT := Vector3(0.0, 1.5708, 0.04)
# 第一人称"眼睛"相机：所有场景 + 运行时(F6) 都从这儿读 => 一处拖/改、处处同步
const DEF_FP_CAM_POS := Vector3(0.0, 0.0, 0.0)
const DEF_FP_CAM_ROT := Vector3(0.0, 0.0, 0.0)
# 相机到模型世界 AABB 的“保持距离”余量(米)：相机只要进入“某网格包围盒+余量”
# 就被推回最近盒面外，绝不会插进实体里导致编辑器/GPU 崩溃。
# 关键：余量必须 > 相机 near 裁剪距离(默认 0.10) 才能彻底杜绝崩溃——
# 只要相机在“包围盒+余量”之外，近裁剪面就必定在实体之外(网格⊆包围盒)。
# 崩溃只要求“余量 > 相机 near 裁剪距离”。本场景 Camera3D.near=0.01，故只要
# 余量 > 0.01 就不崩。之前取 0.15 太保守——把相机挡在包围盒外 0.15m，导致第一
# 人称“只有手臂”的模型一拉远就看到肘部断口。现收至 0.03：可贴着枪身表面任意
# 方向凑近构图(让断臂出画)，仍满足 0.03 > 0.01 => 近裁剪面不切进实心网格 => 不崩。
# 若确需更贴(怼到金属)，可降到 0.012(仍>0.01)，但不要再低，否则边缘有嵌进风险。
const FP_CAM_KEEP_OUT := 0.03

# 第一人称动画镜像：源动画是“左手持枪”，但角色模型是“右手持枪”，
# 故对 model 节点施加“屏幕左右(世界 X)”的镜像 => 视觉上变成右手持枪。
# 因 FP_GUN_ROT 把模型局部 Z 轴旋到了世界 +X（见 Basis.from_euler 的列向量
# (1.0,0,-0.000004)），所以这里对【局部 Z】取负缩放即可实现干净的左右镜像：
#   枪仍朝前(世界 -Z 不变)、不产生剪切、蒙皮不变形(反射是等距变换，
#   det<0 由 Godot 自动翻面处理)。其它轴取负会翻深度(枪口朝向相机)或翻上下，均不可用。
# 关闭全部镜像把 MIRROR_ANIM 改成 false（编辑器与运行时都是左手原版）。
const MIRROR_ANIM := true
const MIRROR_SCALE := Vector3(1.0, 1.0, -1.0)
# 编辑器预览是否也做镜像(显示右手持枪)。默认 false：编辑器里用左手原版(正缩放 det>0)，
# 以绕开 Intel Iris Xe / Vulkan 对“负 determinant 蒙皮网格”渲染/释放时的硬崩(无日志、headless 不可复现)。
# 运行时(F6)始终镜像(右手)，因为游戏是整进程退出、不触发“场景切换释放”那一帧 => 风险低。
# 若你坚持在编辑器里也看右手，把本开关改成 true —— 但 Intel 驱动下有再崩的风险。
const MIRROR_EDITOR := false

# ============================================================================
# 呼吸叠加（仅 idle）：复用角色模型 actor/Rifle Aiming Idle.glb 的呼吸波形，
# 让 viewmodel 的待机动画也有自然的呼吸起伏。
#   breath_idle.json 由 tools/extract_breath.py 从角色动画提取（79 帧 / 2.08s 周期，
#   Hips Y 上下波形 + Spine 绕 X 俯仰波形，均已归一化到 [-0.5, +0.5]）。
# 应用方式：播放 idle 时，把呼吸波形写入 root 骨骼的 position.Y 与 rotation(X 俯仰)，
# 叠加在 idle 原静止 root 值上。编辑器/运行时(F6)都生效（同一 dup 动画）。
# 幅度为 viewmodel 米单位的峰值：BREATH_AMP_Y_M=0.012 => root 上下 ±1.2cm；
# BREATH_AMP_ROT_DEG=0.6 => 枪口俯仰 ±0.6°。可按观感调整。
const BREATH_PATH := "res://fp_viewmodel/breath_idle.json"
const BREATH_ONLY_IDLE := true   # 只对 idle 生效；false 则所有动画都叠加
const BREATH_AMP_Y_M := 0.012
const BREATH_AMP_ROT_DEG := 0.6
var _breath: Dictionary = {}
# ============================================================================

# 相机位【持久化】存放：独立 ConfigFile（user://），与共享 .tres 彻底解耦。
# 关键根因修复：之前用 ResourceSaver.save(config) 直接写共享 .tres，而编辑器在
# Ctrl+S / 关闭场景时也会去保存同一个 .tres（config 是被本脚本改动过的 @export 资源），
# 两路对同一个文件并发写 => 文件损坏 / 保存路径崩溃（仅时序重叠时炸 => “偶发”：
# 有时关 draw 崩、有时不崩、再开 idle 又崩）。改写 user:// 下独立的 .cfg：编辑器
# 完全不管理该文件，无并发写 => 关/开场景不再崩。
# 载入优先级：.cfg 优先；.cfg 不存在则回退到 .tres 种子值（即你 Ctrl+S 落盘调好的位）。
const CAM_PREFS_PATH := "user://fp_cam_prefs.cfg"
var _prefs_pos := Vector3.ZERO
var _prefs_rot := Vector3.ZERO

@export var config: Resource = null

@export var action: String = "idle"
@export var loop_action: bool = true
@export var action_label: String = ""

@onready var camera: Camera3D = $Camera3D
@onready var model: Node3D = $ViewModel

# 实际使用的相机参数（来自 config 或默认常量），由 _gather_config() 填充
var TT_FOV: float = DEF_TT_FOV
var FP_FOV: float = DEF_FP_FOV
var TT_DIST: float = DEF_TT_DIST
var TT_PITCH: float = DEF_TT_PITCH
var FP_GUN_POS: Vector3 = DEF_FP_GUN_POS
var FP_GUN_ROT: Vector3 = DEF_FP_GUN_ROT
var FP_CAM_POS: Vector3 = DEF_FP_CAM_POS
var FP_CAM_ROT: Vector3 = DEF_FP_CAM_ROT

# 运行时(F6)默认第一人称视图，与编辑器一致（需求⑤：打开即第一人称）。
# 按 F 切到“转盘”模式绕模型转、查各角度建模。这样在编辑器里拖好的相机
# 位（写入共享 fp_cam_pos），F6 一进去就直接呈现，不会“看起来没同步”。
var turntable := false
var orbit_yaw := 0.0
var orbit_pitch := TT_PITCH
var view_dist := TT_DIST
var model_center_local := Vector3.ZERO
var _suppress_cam_cb := false
var _save_pending := false
# 退出标志：_exit_tree 置 true，避免延迟的 _flush_config_save 在场景已销毁后
# 仍去碰 config/资源（关闭/切换场景时的并发安全）。
var _exiting := false
# 编辑器内用 _process 轮询检测相机拖拽；记录上一帧相机变换以判断是否有变化
var _last_cam_pos := Vector3.ZERO
var _last_cam_rot := Vector3.ZERO

func _gather_config() -> void:
	TT_FOV = DEF_TT_FOV
	FP_FOV = DEF_FP_FOV
	TT_DIST = DEF_TT_DIST
	TT_PITCH = DEF_TT_PITCH
	FP_GUN_POS = DEF_FP_GUN_POS
	FP_GUN_ROT = DEF_FP_GUN_ROT
	if config != null:
		TT_FOV = config.get("tt_fov")
		FP_FOV = config.get("fp_fov")
		TT_DIST = config.get("tt_dist")
		TT_PITCH = config.get("tt_pitch")
		FP_GUN_POS = config.get("fp_gun_pos")
		FP_GUN_ROT = config.get("fp_gun_rot")
		FP_CAM_POS = config.get("fp_cam_pos")
		FP_CAM_ROT = config.get("fp_cam_rot")
	orbit_pitch = TT_PITCH

# 单网格的世界空间 AABB（用 8 个角点经 global_transform 变换后 expand 得到）
func _mesh_world_aabb(m: MeshInstance3D) -> AABB:
	var la := m.get_aabb()
	var gt: Transform3D = m.global_transform
	var box := AABB()
	var have := false
	for xi in [0,1]:
		for yi in [0,1]:
			for zi in [0,1]:
				var wp := gt * (la.position + Vector3(la.size.x*xi, la.size.y*yi, la.size.z*zi))
				if not have:
					box.position = wp
					box.size = Vector3.ZERO
					have = true
				else:
					box = box.expand(wp)
	return box

func _world_aabb() -> AABB:
	var comb := AABB()
	var have := false
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var b := _mesh_world_aabb(mi as MeshInstance3D)
		if not have:
			comb = b
			have = true
		else:
			comb = comb.merge(b)
	return comb

# 相机位置钳制（崩溃防护核心）：把相机钳到【每个真实网格的世界 AABB + FP_CAM_KEEP_OUT】之外。
# 为何从“组合包围盒”改为“逐网格盒”：组合盒把整把枪+双臂的凸包当成一个大盒子，而枪体缩在
# 盒内很深(实测默认相机离最近网格顶点 0.27m、recess_gap 为负)，导致相机贴到盒外 3cm 时离真实
# 枪身还有 27cm —— 用户要“贴手构图藏断臂”根本凑不近。逐网格盒允许相机进入网格“之间的空隙”，
# 因此能贴到枪/手本身的表面(各网格表面外仅 0.03m)，既满足“贴近”又不崩。
#   * 收敛性：之前逐网格盒“不收敛”是在 keep-out=0.15(盒子巨大、互相深叠)时；现 keep-out=0.03
#     盒子很小、几乎不重叠，且用“贪心先推出穿透最浅的盒”+ 每轮推出到盒面外 +0.01 余量，必收敛。
#   * 安全性：mesh ⊆ 其 AABB，相机在“每个 AABB+0.03”之外 => 必在每片实体表面之外 => 近裁剪面
#     (near=0.01) 必在实体之外 => 编辑器/GPU 永不崩溃。注意相机可处于“网格之间的空隙”(在组合盒
#     内部但不在任何实体里)，那本就是安全的空心区。
# 该函数同时用于：载入(_ready)、实时拖拽(_process)、运行时切第一人称(_apply_view)、
# 存盘净化(_flush_config_save)，所以无论坏值从哪来(磁盘/拖拽/其它场景广播)都会被钳成安全位。
func _clamp_out_of_model(pos: Vector3) -> Vector3:
	var out := pos
	for _pass in range(24):
		var moved := false
		# 贪心：先推出“穿透最浅”的网格盒，利于在重叠几何下收敛
		var best_push := Vector3.ZERO
		var best_depth := INF
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			var box := _mesh_world_aabb(m).grow(FP_CAM_KEEP_OUT)
			if box.has_point(out):
				var push := _exit_push(box, out)
				var depth := push.length()
				if depth < best_depth:
					best_depth = depth
					best_push = push
		if best_depth < INF:
			out += best_push
			moved = true
		if not moved:
			break
	return out

# 把 box 内部点 p 推到【最近盒面外 +0.01】的位移(最小平移量)。+0.01 保证严格在盒外，
# 下一轮 has_point 为 false，不会反复推同一面；最终离实体表面间隙 = FP_CAM_KEEP_OUT + 0.01。
func _exit_push(box: AABB, p: Vector3) -> Vector3:
	var lo := box.position
	var hi := box.end
	var eps := 0.01
	var dxl := p.x - lo.x
	var dxh := hi.x - p.x
	var dyl := p.y - lo.y
	var dyh := hi.y - p.y
	var dzl := p.z - lo.z
	var dzh := hi.z - p.z
	var mn: float = minf(dxl, minf(dxh, minf(dyl, minf(dyh, minf(dzl, dzh)))))
	if mn == dxl: return Vector3(-dxl - eps, 0, 0)
	if mn == dxh: return Vector3(dxh + eps, 0, 0)
	if mn == dyl: return Vector3(0, -dyl - eps, 0)
	if mn == dyh: return Vector3(0, dyh + eps, 0)
	if mn == dzl: return Vector3(0, 0, -dzl - eps)
	return Vector3(0, 0, dzh + eps)

func _want_mirror() -> bool:
	# 编辑器默认不镜像(显示左手原版, det>0)以绕开 Intel 驱动对负行列式蒙皮网格的硬崩；
	# 运行时(F6)始终镜像(右手)，因为游戏退出是整进程退出、不触发“场景切换释放”那一帧。
	if not MIRROR_ANIM:
		return false
	if Engine.is_editor_hint():
		return MIRROR_EDITOR
	return true

func _mirror_scale() -> Vector3:
	var s := Vector3.ONE * SCALE
	if _want_mirror():
		s *= MIRROR_SCALE
	return s

# ----- 相机位持久化（独立 .cfg，与 .tres 解耦，避免编辑器保存冲突崩溃）-----
func _load_cam_prefs() -> bool:
	# 读 user:// 下的相机预设；返回是否成功读取。失败(文件不存在/缺字段)则回退 .tres 种子值。
	var cf := ConfigFile.new()
	if cf.load(CAM_PREFS_PATH) != OK:
		return false
	if not cf.has_section_key("camera", "pos") or not cf.has_section_key("camera", "rot"):
		return false
	_prefs_pos = cf.get_value("camera", "pos")
	_prefs_rot = cf.get_value("camera", "rot")
	return true

func _save_cam_prefs(pos: Vector3, rot: Vector3) -> void:
	# 把相机位写到独立 .cfg。编辑器完全不管理这个文件 => 关/开场景不再与之并发写 => 不崩。
	if _exiting:
		return
	var cf := ConfigFile.new()
	cf.set_value("camera", "pos", pos)
	cf.set_value("camera", "rot", rot)
	var err := cf.save(CAM_PREFS_PATH)
	if err != OK:
		push_error("保存相机预设失败: %d" % err)

func _ready() -> void:
	_gather_config()
	# 载入持久化相机位（独立 .cfg 优先于 .tres 种子值）；编辑器与运行时(F6)都生效
	if _load_cam_prefs():
		if config != null:
			config.set("fp_cam_pos", _prefs_pos)
			config.set("fp_cam_rot", _prefs_rot)
		FP_CAM_POS = _prefs_pos
		FP_CAM_ROT = _prefs_rot
	model.scale = _mirror_scale()
	_play_action()
	# 几何中心(相对模型自身原点, 与父节点/初始位置无关) => 居中可重复、存盘重载不漂移
	model_center_local = model.to_local(_world_aabb().get_center())
	if Engine.is_editor_hint():
		# 编辑器内：相机由共享配置驱动；并监听拖拽把相机写回配置 =>
		# 在任一场景拖动相机，其他 6 个场景 + 运行时(F6) 全部同步。
		#
		# 关键修复（之前编辑器闪退 / 朝向错乱的根因）：
		#   * 早期代码用 camera.transform_changed.is_connected(...) 直接访问信号属性，
		#     在 Godot 4.7 的 Camera3D 上会抛
		#     "Invalid access to property or key 'transform_changed'"，导致 _ready 中断，
		#     模型停留在原点(0,0,0)、相机却已移到 FP_CAM_POS => 相机插进模型里 => 闪退；
		#     同时 _suppress_cam_cb 卡在 true、模型摆放代码被跳过 => 朝向错乱。
		#   * 现改为：先用字符串形式连接信号（is_connected/connect 的 StringName 重载，
		#     对所有 Godot 4 构建都安全），并且【先摆好相机和模型、最后才连信号】，
		#     这样即便连接失败也不会留下“相机插在模型里”的半成品状态。
		# 先摆好模型(供 _clamp_out_of_model 用正确的世界 AABB 钳制相机)，再放相机。
		model.position = FP_GUN_POS - model_center_local
		model.rotation = FP_GUN_ROT
		# 载入即钳制：即便 .tres 落盘了坏值(深陷实体)，这里也会先钳成安全位再显示 =>
		# 重开/重启都不会崩；若确实钳过，则把安全值回写磁盘(自愈)。
		var safe_cp := _clamp_out_of_model(FP_CAM_POS)
		camera.position = safe_cp
		camera.rotation = FP_CAM_ROT
		camera.fov = FP_FOV
		if config != null and not safe_cp.is_equal_approx(FP_CAM_POS):
			config.set("fp_cam_pos", safe_cp)
			_flush_config_save()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		# 监听共享配置广播 => 其它场景拖拽相机时，本场景实时跟随
		if config != null and not config.is_connected("camera_changed", _on_config_camera_changed):
			config.connect("camera_changed", _on_config_camera_changed)
		# 用 _process 轮询检测本场景相机被拖动（Godot 4.7 的 Camera3D 无 transform_changed 信号）
		_last_cam_pos = camera.position
		_last_cam_rot = camera.rotation
		set_process(true)
		return
	await get_tree().process_frame
	_apply_mode()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if action_label != "":
		print("FP_PREVIEW action=%s label=%s" % [action, action_label])

func _exit_tree() -> void:
	# 关键修复：关闭/切换场景时清理，避免编辑器 GPU 崩溃（Intel Iris Xe / Vulkan 硬崩，无日志）。
	# 触发链路：开着 fp_idle + fp_cidao1 两个 first-person 场景（各自的 Camera3D 都
	# current=true），关掉 active 的 idle => 编辑器把 cidao1 切成 active 渲染的那一帧，
	# 视口仍持有“刚被释放的 idle 相机”做渲染 => 悬空相机引用 => 驱动崩溃。
	# 修复：退出前 clear_current()，让视口回落到编辑器自有相机(永不被释放) => 不再崩；
	# 同时停掉轮询、断开跨场景信号、置 _exiting(让任何延迟的 _save_cam_prefs 跳过落盘)，
	# 杜绝任何悬空/越界访问。
	_exiting = true
	set_process(false)
	if config != null and config.is_connected("camera_changed", _on_config_camera_changed):
		config.disconnect("camera_changed", _on_config_camera_changed)
	if is_instance_valid(model):
		# 释放前把模型缩放回正值：带负 determinant(MIRROR_ANIM)的蒙皮网格在 Intel 驱动下
		# 释放时偶发崩溃，正缩放网格释放更稳 => 廉价保险。
		model.scale = Vector3.ONE
	if is_instance_valid(camera) and camera.current:
		camera.clear_current()

func _load_breath() -> void:
	if not _breath.is_empty():
		return
	var f := FileAccess.open(BREATH_PATH, FileAccess.READ)
	if f == null:
		push_warning("breath data missing: " + BREATH_PATH)
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		_breath = parsed

func _clear_track_keys(anim: Animation, t: int) -> void:
	var kc: int = anim.track_get_key_count(t)
	for k in range(kc - 1, -1, -1):
		anim.track_remove_key(t, k)

# 子类钩子：_play_action 在 dup 动画上可做附加处理（默认无操作）。
func _on_action_duplicated(_anim: Animation, _name: String) -> void:
	pass

func _apply_breath(anim: Animation) -> void:
	# 把角色呼吸波形写入 root 骨骼轨道：position.Y 上下起伏 + rotation 绕 X 俯仰。
	# 不重建动画长度：时间轴用 JSON 的 0..2.08s，若源动画更短会自动延长（循环下首尾衔接）。
	_load_breath()
	if _breath.is_empty() or not _breath.has("times"):
		return
	var skel := model.find_child("Skeleton3D", true, false) as Skeleton3D
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
		_clear_track_keys(anim, pos_track)
	if rot_track >= 0 and anim.track_get_key_count(rot_track) > 0:
		base_rot = anim.track_get_key_value(rot_track, 0)
		_clear_track_keys(anim, rot_track)
	var times: Array = _breath["times"]
	var yw: Array = _breath["hips_y_wave"]
	var rw: Array = _breath["spine_rotx_wave"]
	var rot_amp: float = deg_to_rad(BREATH_AMP_ROT_DEG)
	var nk := mini(times.size(), mini(yw.size(), rw.size()))
	for i in nk:
		var t: float = times[i]
		var y: float = yw[i] * BREATH_AMP_Y_M * 2.0
		if pos_track >= 0:
			anim.track_insert_key(pos_track, t, base_pos + Vector3(0.0, y, 0.0))
		if rot_track >= 0:
			var wob: Quaternion = Quaternion.from_euler(Vector3(rw[i] * rot_amp * 2.0, 0.0, 0.0))
			anim.track_insert_key(rot_track, t, base_rot * wob)
	if pos_track >= 0:
		anim.track_set_interpolation_type(pos_track, Animation.INTERPOLATION_LINEAR)
	if rot_track >= 0:
		anim.track_set_interpolation_type(rot_track, Animation.INTERPOLATION_LINEAR)

func _play_action() -> void:
	var ap := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap == null:
		return
	var name_to_play: String = action
	if not ap.has_animation(name_to_play):
		var libs: PackedStringArray = ap.get_animation_library_list()
		if libs.size() > 0:
			var fb_lib: AnimationLibrary = ap.get_animation_library(libs[0])
			var fb_list: PackedStringArray = fb_lib.get_animation_list()
			if fb_list.size() > 0:
				name_to_play = String(fb_list[0])
		if not ap.has_animation(name_to_play):
			return
	var src: Animation = ap.get_animation(name_to_play)
	# reload 用烘焙好的修改版（tools/bake_reload_fixed.gd）：装回段平滑回位到 idle，
	# 消除"弹匣掉下去又上来"。编辑器 F6 预览即可看到效果（与实机共用同一资源）。
	if name_to_play == "reload":
		var _fixed: Animation = load("res://fp_viewmodel/reload_fixed.tres") if ResourceLoader.exists("res://fp_viewmodel/reload_fixed.tres") else null
		if _fixed != null:
			src = _fixed
	var dup: Animation = src.duplicate()
	# 呼吸叠加（仅 idle）：复用角色呼吸波形，写入 root 轨道（Y 起伏 + X 俯仰）
	if (not BREATH_ONLY_IDLE or name_to_play == "idle") and not turntable:
		_apply_breath(dup)
	# 子类钩子：在 dup 上做附加轨道处理（如动作末帧回位到 idle 首帧，消除切换跳变）
	_on_action_duplicated(dup, name_to_play)
	# 编辑器内统一循环播放, 方便反复观看; 运行时按 loop_action 决定
	dup.loop_mode = 1 if (loop_action or Engine.is_editor_hint()) else 0
	var local_name: String = name_to_play + "_preview"
	var libs: PackedStringArray = ap.get_animation_library_list()
	var lib: AnimationLibrary
	if libs.size() > 0:
		lib = ap.get_animation_library(libs[0])
	else:
		lib = AnimationLibrary.new()
		ap.add_animation_library("", lib)
	if lib.has_animation(local_name):
		lib.remove_animation(local_name)
	lib.add_animation(local_name, dup)
	ap.play(local_name)

func _apply_mode() -> void:
	if turntable:
		if model.get_parent() != self:
			model.reparent(self, false)
		model.scale = _mirror_scale()
		model.rotation = Vector3.ZERO
		model.position = -model_center_local
		var w := _world_aabb()
		var radius := w.size.length() * 0.5
		var fov_rad := deg_to_rad(TT_FOV)
		# 让包围球刚好落入竖直 FOV 并留 15% 余量 => 整把枪都在画面内
		view_dist = clamp(radius / tan(fov_rad * 0.5) * 1.15, 1.5, 12.0)
		camera.fov = TT_FOV
	else:
		# 第一人称：model 留在根节点下，与编辑器共用同一套世界变换，仅缩放镜像 => 视觉即编辑器画面的左右镜像版。
		# 原先 model.reparent(camera) 后却仍用“相对根”的位置 FP_GUN_POS - model_center_local，
		# 当作“相对相机”的局部位置，导致 model 整体少减了相机位置 C(约 0.2~0.5m)，
		# 运行时(F6)画面里枪/手偏离正前方、构图与编辑器不再对称（即“相机位置不完美”）。
		# 现在 model 与相机都是根的直接子节点，世界位置与编辑器完全一致(仅 model.scale.z 取负)，
		# FP_CAM_POS 直接复用 => 运行时构图与编辑器对称完美，且相机不承受负缩放 => 画面不翻转/不崩。
		if model.get_parent() != self:
			model.reparent(self, false)
		model.scale = _mirror_scale()
		model.rotation = FP_GUN_ROT
		model.position = FP_GUN_POS - model_center_local
		camera.fov = FP_FOV
	_apply_view()

func _apply_view() -> void:
	var dir := Vector3(
		cos(orbit_pitch) * sin(orbit_yaw),
		sin(orbit_pitch),
		cos(orbit_pitch) * cos(orbit_yaw)
	)
	if turntable:
		camera.position = dir * view_dist
		camera.look_at(Vector3.ZERO, Vector3.UP)
	else:
		# 第一人称：相机位置/旋转来自共享配置（与编辑器预览一致）；
		# 位置经钳制，确保即使配置是坏值也不会把相机放进实体里崩溃。
		camera.position = _clamp_out_of_model(FP_CAM_POS)
		camera.rotation = FP_CAM_ROT

func _process(_delta: float) -> void:
	# 编辑器内：轮询相机变换，检测用户在视口里拖动相机，并写回共享配置。
	# 守卫：场景正在销毁(_exiting)或节点已被释放时立即返回，杜绝悬空访问。
	if _exiting or not is_instance_valid(camera) or not is_instance_valid(config):
		return
	# 用轮询而非 transform_changed 信号 —— 该信号在 Godot 4.7 的 Camera3D 上
	# 并不存在（"Nonexistent signal: 'transform_changed'"），早期代码因此抛错并
	# 中断 _ready，留下“相机插在模型里”的半成品状态 => 编辑器闪退/朝向错乱。
	if not Engine.is_editor_hint():
		return
	if _suppress_cam_cb or config == null:
		return
	if camera.position.is_equal_approx(_last_cam_pos) and camera.rotation.is_equal_approx(_last_cam_rot):
		return
	# 实时“防穿透”钳制：用户想拖到哪都行，但只要相机原点会落进实体(组合盒+余量内)，
	# 就推回最近盒面外 => 直播也不崩。实体之外的自由拖动完全不受影响(可绕到任意角度)。
	var safe := _clamp_out_of_model(camera.position)
	if not safe.is_equal_approx(camera.position):
		_suppress_cam_cb = true
		camera.position = safe
		_suppress_cam_cb = false
	_last_cam_pos = camera.position
	_last_cam_rot = camera.rotation
	config.set("fp_cam_pos", camera.position)
	config.set("fp_cam_rot", camera.rotation)
	# 广播 => 其它已打开场景的相机实时跟随（纯内存，不写盘）
	config.emit_signal("camera_changed")
	if not _save_pending:
		_save_pending = true
		call_deferred("_flush_config_save")

func _flush_config_save() -> void:
	# 空闲时单次持久化：把相机位写到独立 .cfg（不再用 ResourceSaver.save 写共享 .tres，
	# 避免与编辑器保存 .tres 并发写 => 关/开场景崩溃）。存档前“净化”：坏值(深陷实体)
	# 推回表面再存；表面/空腔位原样保留(它们不会崩) => 实时拖拽零限制，坏值也写不进盘。
	_save_pending = false
	if _exiting or not is_instance_valid(config):
		return
	var cp: Vector3 = config.get("fp_cam_pos")
	var cr: Vector3 = config.get("fp_cam_rot")
	var safe := _clamp_out_of_model(cp)
	if not safe.is_equal_approx(cp):
		config.set("fp_cam_pos", safe)
		cp = safe
	_save_cam_prefs(cp, cr)

func _on_config_camera_changed() -> void:
	# 其它场景拖拽相机广播过来 => 本场景相机实时跟随（源场景因已相等会提前返回）
	if _exiting or not is_instance_valid(camera) or not is_instance_valid(config):
		return
	if _suppress_cam_cb:
		return
	var cp: Vector3 = _clamp_out_of_model(config.get("fp_cam_pos"))
	var cr: Vector3 = config.get("fp_cam_rot")
	if cp.is_equal_approx(camera.position) and cr.is_equal_approx(camera.rotation):
		return
	_suppress_cam_cb = true
	camera.position = cp
	camera.rotation = cr
	_last_cam_pos = cp
	_last_cam_rot = cr
	_suppress_cam_cb = false

func _unhandled_input(event) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif event.keycode == KEY_F:
			turntable = !turntable
			_apply_mode()
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		orbit_yaw -= event.relative.x * 0.005
		orbit_pitch = clamp(orbit_pitch - event.relative.y * 0.005, -1.4, 1.4)
		_apply_view()

	if event is InputEventMouseButton and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			view_dist = max(0.4, view_dist - 0.15)
			_apply_view()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			view_dist = min(12.0, view_dist + 0.15)
			_apply_view()
