@tool
extends Node3D
## 第三人称相机控制器 - 悬浮跟随
## 挂载到 CameraPivot 节点（Player 的子节点）
## 摄像机始终悬浮在角色头顶后方，视角与角色朝向一致
## 鼠标水平：旋转角色+摄像机朝向（相对位置绑定）
## 鼠标垂直：俯仰角度
## 反引号键(`)长按：进入自由视角，鼠标只旋转相机不旋转角色，松开后丝滑恢复初始角度
## （注：头注释曾写 Alt，实现实际绑定反引号键，见 _unhandled_input）

class_name CameraController

@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D

# --- 相机参数（可在 Inspector 面板中直接调整）---
@export var camera_distance: float = 2.9       # 相机距离角色后背水平距离（m）
@export var camera_height: float = 2.85        # 站立时相机高度偏移（角色头部1.8m + 1.05m）
@export var look_height: float = 2.766          # 站立时观察目标高度（使初始视角水平偏下5°）
@export var camera_crouch_offset: float = 0.5  # 蹲下时相机下调高度（m）
@export_range(0.001, 0.01) var mouse_sensitivity: float = 0.0022  # 鼠标灵敏度
@export var min_pitch: float = -25.0           # 最低俯仰角（度）：仰头（向上）上限 25°
@export var max_pitch: float = 75.0            # 最高俯仰角（度）：放开限制，距正下方留 15°
@export var spring_margin: float = 0.05        # 弹簧臂碰撞检测边缘
@export_flags_3d_physics var spring_collision_mask: int = 1  # 弹簧臂碰撞层（默认层1；地图墙体在其他层时需同步修改，否则相机穿墙）
@export var free_look_lerp_speed: float = 8.0  # 自由视角恢复速度（越大恢复越快）
@export var vertical_smoothing: float = 6.0    # 垂直方向平滑速度（值越小，跳跃时相机延迟越明显；0=禁用平滑）

# --- 第一人称模式（V 键切换） ---
@export var fp_eye_height: float = 1.62        # FP 站立眼睛高度（米）
@export var fp_eye_height_crouch: float = 1.1 # FP 蹲下眼睛高度（米）——0.95 太低导致蹲下低头时长枪（AK/M82）穿地，抬到 1.1 缓解
@export var fp_fov: float = 70.0               # FP 视野
@export var fp_offset: Vector3 = Vector3.ZERO  # FP 相机相对视点的微调（前后/上下/左右），由编辑器预览写回，运行时生效
@export var editor_fp_preview: bool = false    # 编辑器内 FP 机位预览开关（仅 @tool 编辑器生效，运行时恒忽略）
## 编辑器内 3P 游戏机位预览（仅 @tool 编辑器生效）：每帧把相机摆到与游戏运行时
## 一致的位置（高度=camera_height、背后距离=camera_distance、视线看向 look_height）。
## 打开 player_preview.tscn 调相机参数所见即所得；想自由拖动观察时先关掉它。
@export var editor_3p_preview: bool = true
## 编辑器相机预览模式（仅 @tool 编辑器生效）：
##   0 = 3P 背后机位（复刻游戏 3P：高度 camera_height、距离 camera_distance、视线 look_height）
##   1 = FP 眼睛机位（角色眼睛高度 fp_eye_height，朝前；拖拽微调走 editor_fp_preview 勾选流程）
##   2 = 自由观察（不动相机）
## ⚠️ 不用 @export_tool_button（Callable 在编辑器加载时偶发解析为 Nil）；下拉枚举最稳。
@export_enum("3P 背后机位", "FP 眼睛机位", "自由观察") var editor_view_mode: int = 0

# 内部状态
var pitch: float = 0.0                    # 当前俯仰角（弧度）
var _current_look_height: float = 0.0    # 当前观察高度（tween 插值用）
var _crouch_tween: Tween = null          # 蹲下/起立的相机高度过渡 tween
var _base_cam_y: float = 0.0             # 基础相机高度（由蹲下系统控制，不含垂直平滑偏移）
var _smoothed_player_y: float = 0.0      # 平滑后的玩家Y坐标（用于跳跃时相机垂直方向延迟跟随）
var _y_lag: float = 0.0                  # 当前Y延迟量（正值=玩家在上方，相机滞后）
var _rotation_locked: bool = false       # 是否锁定角色旋转（死亡/倒地时防止鼠标水平移动转动角色）
var first_person: bool = false           # 是否第一人称模式（V 键切换）
var _is_crouching: bool = false          # 当前是否蹲伏（供切视角时取正确的蹲/站相机高度）
var _saved_fov: float = 75.0             # 进入 FP 前的相机 FOV（退出时恢复）

# 自由视角状态
var _is_free_looking: bool = false        # 是否正在自由视角模式（Alt长按中）
var _free_look_yaw: float = 0.0           # 自由视角的水平偏移角（弧度，相对角色朝向）
var _free_look_pitch: float = 0.0         # 自由视角的俯仰角偏移（弧度）
var _free_look_blend: float = 0.0         # 自由视角混合权重 0~1（用于丝滑过渡）
var _target_free_look_blend: float = 0.0  # 目标混合权重

func _ready():
	# 编辑器内（@tool）：跳过运行时初始化（尤其不要捕获编辑器鼠标），预览由 _process 的编辑器分支处理
	if Engine.is_editor_hint():
		return
	# 设置弹簧臂
	spring_arm.spring_length = camera_distance
	spring_arm.margin = spring_margin
	spring_arm.collision_mask = spring_collision_mask

	# 设置相机高度偏移（CameraPivot 相对于 Player 的位置）
	_base_cam_y = camera_height
	position.y = camera_height
	_current_look_height = look_height
	_smoothed_player_y = owner.global_position.y if owner else 0.0

	# 初始捕获鼠标（ESC 开关设置界面的鼠标管理见 scripts/settings_menu.gd）
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## 获取相机调试信息（供 player.gd 日志调用）
func get_debug_info() -> Dictionary:
	return {
		"pivot_y": position.y,
		"base_cam_y": _base_cam_y,
		"target_pivot_y": _base_cam_y,
		"y_lag": _y_lag,
		"smoothed_player_y": _smoothed_player_y,
		"look_h": _current_look_height,
		"target_look_h": _current_look_height,
		"cam_global_y": camera.global_position.y if camera else -999.0,
		"pitch_deg": rad_to_deg(pitch),
	}

func _input(event):
	# 编辑器内（@tool）：不处理输入事件，避免干扰编辑器
	if Engine.is_editor_hint():
		return
	# 注意：ESC（ui_cancel）的"打开/关闭设置界面 + 鼠标管理"已统一交给
	# scripts/settings_menu.gd，本文件不再处理 ui_cancel，避免双重切换。

	# `键长按：自由视角切换（使用直接按键检测，避免修饰键在input map中的问题）
	# 第一人称下禁用自由视角（` 键不生效）
	if event is InputEventKey and event.physical_keycode == KEY_QUOTELEFT:
		if first_person:
			return
		if event.pressed and not _is_free_looking:
			_is_free_looking = true
			_target_free_look_blend = 1.0
		elif not event.pressed and _is_free_looking:
			_is_free_looking = false
			_target_free_look_blend = 0.0

	# 鼠标移动 → 旋转视角
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if _is_free_looking:
			# 自由视角：鼠标水平只旋转相机偏航，不旋转角色
			_free_look_yaw -= event.relative.x * mouse_sensitivity
			_free_look_pitch += event.relative.y * mouse_sensitivity
			_free_look_pitch = deg_to_rad(clamp(rad_to_deg(_free_look_pitch), min_pitch, max_pitch))
		else:
			# 正常模式：水平旋转角色，垂直俯仰
			# 【修复】owner 可能为空（运行时动态 detached），与下方 L131 的
			# `owner.global_position.y if owner else 0.0` 守卫保持一致，避免空引用崩溃
			if owner != null and not _rotation_locked:
				owner.rotation.y -= event.relative.x * mouse_sensitivity
			pitch += event.relative.y * mouse_sensitivity
			pitch = deg_to_rad(clamp(rad_to_deg(pitch), min_pitch, max_pitch))

func _process(delta):
	# 编辑器内（@tool）：只跑机位预览分支，不执行运行时相机逻辑，避免污染编辑器视口。
	# FP 预览优先（勾 editor_fp_preview 时显示第一人称眼睛机位），
	# 否则若开启 editor_3p_preview 则复刻游戏 3P 机位（所见即所得）。
	if Engine.is_editor_hint():
		_editor_view_update()
		return
	# === 垂直方向平滑跟随 ===
	# CameraPivot 是 Player 的子节点，全局Y = Player.global_y + position.y
	# 通过平滑追踪玩家Y坐标，在 position.y 中减去延迟量，
	# 使相机全局Y = smoothed_player_y + _base_cam_y（跳跃时相机有轻微延迟，更自然）
	var player_y: float = owner.global_position.y if owner else 0.0
	if vertical_smoothing > 0.01:
		# clamp 权重：低帧率(delta 大)时 权重>1 会导致 lerp 反向过冲抖动
		_smoothed_player_y = lerpf(_smoothed_player_y, player_y, clampf(vertical_smoothing * delta, 0.0, 1.0))
	else:
		_smoothed_player_y = player_y
	_y_lag = player_y - _smoothed_player_y
	# position.y = 基础高度 - Y延迟（玩家跳跃上升时 y_lag>0，相机位置下调，产生延迟效果）
	position.y = _base_cam_y - _y_lag

	# 自由视角混合权重丝滑过渡（clamp 防低帧率过冲）
	_free_look_blend = lerpf(_free_look_blend, _target_free_look_blend, clampf(free_look_lerp_speed * delta, 0.0, 1.0))

	# 松开反引号键时，自由视角偏移逐渐回归0（丝滑恢复初始状态）
	if not _is_free_looking:
		_free_look_yaw = lerpf(_free_look_yaw, 0.0, clampf(free_look_lerp_speed * delta, 0.0, 1.0))
		_free_look_pitch = lerpf(_free_look_pitch, 0.0, clampf(free_look_lerp_speed * delta, 0.0, 1.0))

	# 计算最终相机旋转
	# CameraPivot的rotation.y控制相机水平偏航（叠加在角色朝向上）
	rotation.y = _free_look_yaw * _free_look_blend
	# 俯仰角 = 基础pitch + 自由视角偏移（按混合权重叠加）
	var blended_pitch = pitch * (1.0 - _free_look_blend) + _free_look_pitch * _free_look_blend
	rotation.x = blended_pitch

	if first_person:
		# 第一人称：相机已 reparent 到 CameraPivot 下（脱离 SpringArm 的 180° 缩放），
		# 固定在 pivot 原点、绕 Y 旋转 180° 后朝 +Z（角色正前方，与第三人称朝向一致）。
		# pivot.rotation.x=pitch 直接作为俯仰（pitch 正=低头，与第三人称一致），
		# 无需 look_at、也无需 -2*pitch 补偿。
		# 修复：原先相机朝 -Z（角色背后），切到 FP 后视角反向（朝西）、
		# 第三人称角色影子跑到视野前方的问题。
		camera.position = fp_offset
		camera.rotation = Vector3(0.0, PI, 0.0)
		return

	# 计算观察目标（使用平滑后的Y坐标 + 当前观察高度）
	# 平滑后的Y使 look_at 也有延迟效果，与相机位置同步
	var opx: float = owner.global_position.x if owner != null else 0.0
	var opz: float = owner.global_position.z if owner != null else 0.0
	var look_target = Vector3(opx, _smoothed_player_y + _current_look_height, opz)
	camera.look_at(look_target, Vector3.UP)

## 重置自由视角状态（切到第一人称时调用，避免上一视角残留的自由视角偏移/混合卡住）
func _reset_free_look() -> void:
	_is_free_looking = false
	_target_free_look_blend = 0.0
	_free_look_yaw = 0.0
	_free_look_pitch = 0.0
	_free_look_blend = 0.0

## 切换第一人称 / 第三人称（V 键，由 player.gd 调用）
## FP：相机从 SpringArm 摘到 CameraPivot 下（绕开 SpringArm 的 180° 缩放镜像），
##     pivot 高度=眼睛高度、相机在 pivot 原点朝 +Z（角色正前方，视线=角色朝向+俯仰），FOV=fp_fov；
##     枪的构图由 viewmodel 相对相机的局部变换保证（与 fp_gameplay 完美位置一致）。
## 3P：还原到 SpringArm 悬挂、原高度与 FOV。
## fp_fov_val 为第一人称 FOV（来自 fp_view_config.tres）。
func set_first_person(v: bool, fp_fov_val: float = 70.0) -> void:
	if first_person == v:
		return
	first_person = v
	# 关键修复：切视角前先杀掉可能仍在运行的蹲伏过渡 tween，
	# 否则它会随后把 _base_cam_y 覆写成旧目标高度（蹲着切视角时残留 tween 导致相机高度错乱/偏移）。
	if _crouch_tween and _crouch_tween.is_valid():
		_crouch_tween.kill()
	if v:
		_reset_free_look()   # 进入第一人称：清除残留自由视角（避免卡在偏移角度）
		_saved_fov = camera.fov
		camera.reparent(self, false)
		camera.position = fp_offset
		camera.rotation = Vector3.ZERO
		camera.fov = fp_fov_val
		# 切换机位后强制立即刷新相机世界变换：reparent 改了父节点，
		# Godot 的相机世界矩阵会滞后一帧才刷新，导致切人称时有一帧"上个人称残影"。
		camera.force_update_transform()
		spring_arm.spring_length = 0.0
		# 进入 FP：按当前是否蹲伏取对应眼睛高度（蹲着切 FP 不能给站立眼睛高度）
		_base_cam_y = fp_eye_height_crouch if _is_crouching else fp_eye_height
		_current_look_height = _base_cam_y
	else:
		camera.reparent(spring_arm, false)
		camera.position = Vector3.ZERO
		camera.rotation = Vector3.ZERO
		camera.fov = _saved_fov
		# 同 FP 分支：reparent 后强制刷新相机世界变换，消除切人称的一帧残影
		camera.force_update_transform()
		spring_arm.spring_length = camera_distance
		# 回到 3P：按当前是否蹲伏取对应相机/观察高度
		# （蹲着切回 3P 必须给蹲伏高度，否则相机偏高 camera_crouch_offset 米 → 位置偏移）
		_base_cam_y = (camera_height - camera_crouch_offset) if _is_crouching else camera_height
		_current_look_height = (look_height - camera_crouch_offset) if _is_crouching else look_height

## 编辑器机位统一状态机（@tool，仅编辑器 _process 调用）。
## 由 editor_view_mode 下拉驱动：0=3P / 1=FP / 2=自由观察。
## ⚠️ 不再做"拖拽自动写回"——那是污染 fp_eye_height/fp_offset 的源头
## （用户在 FP 模式拖相机到任意位置，退出时就被写回成参数，拖到 3P 位参数就毁了）。
## FP 模式改为【每帧摆位】=所见即所得：改 fp_eye_height/fp_offset 数值即时可见，
## 相机永远在眼睛位，不可能被拖走污染。
func _editor_view_update() -> void:
	# 旧 editor_fp_preview 兼容（勾着=FP）；下拉优先
	if editor_view_mode == 1 or editor_fp_preview:
		_editor_fp_preview_update()
	elif editor_view_mode == 0 and editor_3p_preview:
		_editor_3p_update()
	# 其他（mode 2 自由观察 / 3P 预览被关）：不动相机，自由拖拽观察

## 编辑器内 3P 游戏机位复刻（@tool，仅编辑器 _process 调用；运行时不走此分支）。
## 与运行时逐参数一致：pivot 高度=camera_height、相机世界位=SpringArm 局部 -Z×camera_distance
## （SpringArm 自带 180° 旋转，用 global_transform 直接算，不依赖编辑器是否推子节点）、
## 视线 look_at look_height（运行时同款）。改这三个参数即时可见。
var _3p_preview_logged := false   # 编辑器 3P 机位复刻的一次性诊断日志

func _editor_3p_update() -> void:
	if spring_arm == null or camera == null:
		return
	if not _3p_preview_logged:
		_3p_preview_logged = true
		print("[CAM3P] 编辑器 3P 机位复刻运行中: dist=%.2f height=%.2f look=%.2f" % [
			camera_distance, camera_height, look_height])
	position.y = camera_height      # CameraPivot 相对 Player 的高度（运行时 _base_cam_y）
	rotation.x = 0.0                # 编辑器无鼠标输入：初始零俯仰/零偏航
	rotation.y = 0.0
	spring_arm.spring_length = camera_distance   # 同步引擎参数
	var base: Vector3 = global_position
	if owner != null:
		base = owner.global_position
	# ⚠️ 运行时实测：3P 相机在 pivot 的 -Z（角色背后）camera_distance 处、高度 camera_height、
	# look_at 角色 look_height（对照探针 probe_cam_compare：运行时 pos=(x,2.85,z-2.9)）。
	# 不要用 spring_arm.global_transform 推算——SpringArm 自带 180° 旋转会把方向翻到前方。
	var cam_world: Vector3 = global_position + (-global_transform.basis.z) * camera_distance
	camera.look_at_from_position(cam_world, base + Vector3(0.0, look_height, 0.0), Vector3.UP)

## 编辑器内 FP 机位预览（@tool，仅编辑器 _process 调用；运行时不走此分支）。
## 每帧把相机摆到"游戏 FP 同款"位置：角色位置 + (fp_offset.x, fp_eye_height, fp_offset.z)，
## 朝向 +Z（角色正前方）。改 fp_eye_height / fp_offset 数值即时可见，所见即所得。
## ⚠️ 不支持拖拽（拖了会被拉回眼睛位）——调位置请改数值，这是防污染的设计。
func _editor_fp_preview_update() -> void:
	if camera == null:
		return
	var base: Vector3 = global_position
	if owner != null:
		base = owner.global_position
	# 与运行时 FP 完全一致：pivot 高度=眼睛高度、相机在 pivot 偏移 fp_offset、朝角色前方 +Z。
	# 用 look_at_from_position（与 3P 预览同机制）；不能直接赋 global_transform——
	# camera 是 SpringArm 子节点（自带 180° 旋转），global setter 反解 local 会叠加旋转，
	# 朝向错乱（实测前向变成 (-0.70, 0.16, -0.70)）。
	var cam_pos := Vector3(base.x + fp_offset.x, fp_eye_height + fp_offset.y, base.z + fp_offset.z)
	camera.look_at_from_position(cam_pos, cam_pos + Vector3(0.0, 0.0, 1.0), Vector3.UP)

## 设置蹲下状态（由 player.gd 调用）
## 蹲下时相机下调 camera_crouch_offset 米，过渡时长匹配蹲下动画
## 注意：_base_cam_y 是基础高度，position.y 由 _process() 每帧根据垂直平滑重新计算
func set_crouch(crouching: bool, duration: float = 0.8):
	# 终止已有过渡
	if _crouch_tween and _crouch_tween.is_valid():
		_crouch_tween.kill()
	_is_crouching = crouching

	var target_cam_y: float = camera_height
	var target_look_y: float = look_height
	if first_person:
		target_cam_y = fp_eye_height_crouch if crouching else fp_eye_height
		target_look_y = target_cam_y
	elif crouching:
		target_cam_y = camera_height - camera_crouch_offset
		target_look_y = look_height - camera_crouch_offset

	# 用 tween 精确控制过渡时长，匹配蹲下动画
	# tween _base_cam_y（通过方法回调），position.y 由 _process() 自动应用
	_crouch_tween = create_tween()
	_crouch_tween.tween_method(_set_base_cam_y, _base_cam_y, target_cam_y, duration)
	_crouch_tween.parallel().tween_method(_set_look_height, _current_look_height, target_look_y, duration)

## tween 回调：更新基础相机高度
func _set_base_cam_y(val: float):
	_base_cam_y = val

## tween 回调：更新观察高度
func _set_look_height(val: float):
	_current_look_height = val

## 获取当前水平视角方向（用于移动输入计算）
## 自由视角模式下叠加自由视角偏航，否则使用角色朝向
## 第一人称与第三人称一致：相机在角色正前方看向 +basis.z，前进方向=+basis.z
## （修复前 FP 相机朝 -Z，此处曾返回 -basis.z，导致切到 FP 后视角/移动反向）。
func get_forward_direction() -> Vector3:
	# 移动方向始终相对【角色自身朝向】（W=角色前方），完全不受自由视角影响：
	# 自由视角（` 键）只改变观察方向，不改变移动方向——转到角色正面观察时按 W，
	# 角色仍朝自己脸朝的方向走（否则会变成"角色向相机所对方向/身后移动"）。
	if owner == null:
		return Vector3.ZERO
	var forward = owner.global_transform.basis.z
	forward.y = 0
	return forward.normalized()

## 获取当前水平右方向
## 第一人称与第三人称一致：右方向=-basis.x（前进 +basis.z × 上 +basis.y = -basis.x）。
func get_right_direction() -> Vector3:
	# 同 get_forward_direction：移动右方向始终相对角色自身，不受自由视角影响。
	# 【修复 M2】owner 为 null（重挂/切换瞬间）时直接解引用崩溃，对称于 get_forward_direction 的守卫。
	if owner == null:
		return Vector3.ZERO
	var right = -owner.global_transform.basis.x
	right.y = 0
	return right.normalized()

## 获取移动方向向量（基于相机朝向）
func get_movement_direction(input_dir: Vector2) -> Vector3:
	var forward = get_forward_direction()
	var right = get_right_direction()
	return (forward * input_dir.y + right * input_dir.x).normalized()

## 锁定/解锁角色旋转（死亡/倒地时调用，防止鼠标水平移动转动角色）
## 锁定后鼠标水平移动只影响俯仰角（上下视角），不改变角色朝向
func set_rotation_locked(locked: bool):
	_rotation_locked = locked
