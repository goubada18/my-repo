extends CharacterBody3D
## 主角色控制器
## 挂载到 Player (CharacterBody3D) 节点
## 完整动画状态机 + 物理移动 + 输入控制

class_name Player

## 武器槽位键位映射（数字键 → 武器 id）。
## 1=AK47 / 2=手枪(v_deagle) / 3=尼泊尔(nepal_kukri) / 4=手雷(后期开放，留空) / 5=狙击(m82a1)。
## 原 X 键(循环下一把)已取消；Q 键改为「切换上一把武器」。
const WEAPON_SLOT_IDS := {
	1: "ak47",
	2: "v_deagle",
	3: "nepal_kukri",
	4: "gaobao",
	5: "m82a1",
}

# P0-1/P0-2：显式 preload 武器握持子系统与其标定资源，
# 确保无头（headless）模式下 class_name 全局类可被解析（编辑器外无全局类缓存）。
const WeaponRig = preload("res://scripts/weapon_rig.gd")
const WeaponRigConfig = preload("res://scripts/weapon_rig_config.gd")
const FPActionRetarget = preload("res://scripts/fp_action_retarget.gd")
const FPViewmodelPlayer = preload("res://scripts/fp_viewmodel_player.gd")


# ============================================================
# 调试模式（设为false关闭所有调试日志，提升性能）
# ============================================================
# =====================================================================
# 【版本标记 v21】2026-08-25 14:25 外部修改（切回步枪立即回持枪位：挥刀状态残留修复 + 短混合）。
# 若编辑器里看不到这行 → 请【关闭 player.gd 标签页重新打开】或【重启 Godot】；
# 并【不要按 Ctrl+S 保存 player.gd】（旧缓冲会覆盖磁盘上的修复）。
# =====================================================================
const DEBUG_MODE: bool = false
# 【临时排查开关】尼泊尔挥刀兼容性日志：挥刀起手/下半身跟随/落地/恢复关键路径输出。
# 用户复现"挥刀与动作兼容"问题后发回控制台日志，定位完成后改回 false。
const NEPAL_LOG: bool = false

# 每帧驱动时序优先级（见 _ready 中的硬依赖注释）：必须晚于 AnimationPlayer(pri 0)
# 推进骨骼之后，否则握持/俯仰读到上一帧骨骼 → 脱手。集中为常量，避免被误改。
const PROCESS_PRIORITY: int = 10

# ============================================================
# 动画状态枚举
# ============================================================
enum AnimState {
	IDLE_AIM,           # Rifle Aiming Idle.fbx       持枪瞄准待机（默认）
	CROUCH_IDLE_AIM,    # Idle Crouching Aiming.fbx   蹲姿瞄准待机
	WALK_FORWARD,       # Walking.fbx                 向前行走
	WALK_BACKWARD,      # Walking Backwards.fbx        向后行走
	STRAFE_LEFT,        # Strafe Left.fbx             站姿左横移
	STRAFE_RIGHT,       # Strafe Right.fbx            站姿右横移
	CROUCH_WALK_FORWARD,   # Walk Crouching Forward.fbx   蹲姿向前走
	CROUCH_WALK_BACKWARD,  # Walk Crouching Backward.fbx  蹲姿向后走
	CROUCH_STRAFE_LEFT,    # Crouch Walk Strafe Left.fbx  蹲姿左横移
	CROUCH_STRAFE_RIGHT,   # Crouch Walk Strafe Right.fbx 蹲姿右横移
	JUMP_UP,            # Jump Up.fbx                 起跳（升空）
	JUMP_DOWN,          # Jump Down.fbx               下落
	JUMP_FORWARD,       # Jump Forward.fbx            向前跳跃
	STAND_TO_CROUCH,    # Rifle Stand To Kneel.fbx    站姿→蹲姿过渡
	CROUCH_TO_STAND,    # Rifle Kneel To Stand.fbx    蹲姿→站姿过渡
	HIT_REACTION,       # Hit Reaction.fbx            受击反应
	TOSS_GRENADE,       # Toss Grenade.fbx            投掷手雷
	DEATH,              # Death.fbx                   死亡
	RUN,                # Rifle Run.fbx            持枪奔跑
	CROUCH_HIT_BACK,    # Rifle Kneel Hit To Back.fbx 蹲姿受击向后倒地
	RELOADING,          # Reloading.fbx            换弹装填
	RELOAD_WALK_FORWARD,
	RELOAD_WALK_BACKWARD,
	RELOAD_STRAFE_LEFT,
	RELOAD_STRAFE_RIGHT,
	RELOAD_CROUCH_WALK_FORWARD,
	RELOAD_CROUCH_WALK_BACKWARD,
	RELOAD_CROUCH_STRAFE_LEFT,
	RELOAD_CROUCH_STRAFE_RIGHT,
	RELOAD_CROUCH_IDLE,        # 蹲姿待机换弹（Crouch Idle Aim下半身 + Reloading上半身）
	RELOAD_STAND_TO_CROUCH,    # 换弹时站立→蹲下过渡（合成动画：Reloading上半身 + Stand To Kneel下半身）
	RELOAD_CROUCH_TO_STAND,    # 换弹时蹲下→站立过渡（合成动画：Reloading上半身 + Kneel To Stand下半身）
	NEPAL_ATTACK_LIGHT,        # 尼泊尔轻击（3P 合成：手臂=轻击挥砍，身体=挥刀那一刻的移动状态）
	NEPAL_ATTACK_HEAVY,        # 尼泊尔重击（3P 合成：手臂=重击挥砍，身体=挥刀那一刻的移动状态）
}

# ============================================================
# 动画名称映射（精确匹配 FBX 导入后的动画名）
# ============================================================
# 【性能】热路径状态集合提为常量：数组字面量每次求值都会新建 Array，
# 这些判断位于每物理帧/每渲染帧路径（含 _is_jump_state 等被子系统每帧调用）。
const _AIR_STATES := [AnimState.JUMP_UP, AnimState.JUMP_DOWN, AnimState.JUMP_FORWARD]
const _TRANSITION_STATES := [AnimState.STAND_TO_CROUCH, AnimState.CROUCH_TO_STAND]
const _NEPAL_ATTACK_STATES := [AnimState.NEPAL_ATTACK_LIGHT, AnimState.NEPAL_ATTACK_HEAVY]
const _RELOAD_BLOCK_STATES := [AnimState.JUMP_UP, AnimState.JUMP_DOWN, AnimState.JUMP_FORWARD, AnimState.CROUCH_HIT_BACK]
const _LOOP_NONE_STATES := [AnimState.STAND_TO_CROUCH, AnimState.CROUCH_TO_STAND,
		AnimState.JUMP_UP, AnimState.JUMP_DOWN, AnimState.JUMP_FORWARD]

const ANIM_NAMES: Dictionary = {
	AnimState.IDLE_AIM: "Rifle Aiming Idle",
	AnimState.CROUCH_IDLE_AIM: "Idle Crouching Aiming",
	AnimState.WALK_FORWARD: "Walking",
	AnimState.WALK_BACKWARD: "Walking Backwards",
	AnimState.STRAFE_LEFT: "Strafe Left",
	AnimState.STRAFE_RIGHT: "Strafe Right",
	AnimState.CROUCH_WALK_FORWARD: "Walk Crouching Forward",
	AnimState.CROUCH_WALK_BACKWARD: "Walk Crouching Backward",
	AnimState.CROUCH_STRAFE_LEFT: "Crouch Walk Strafe Left",
	AnimState.CROUCH_STRAFE_RIGHT: "Crouch Walk Strafe Right",
	AnimState.JUMP_UP: "Jump Up",            # 名称与动画内容已一致（源在 actor/ 处修正）
	AnimState.JUMP_DOWN: "Jump Down",        # 名称与动画内容已一致（源在 actor/ 处修正）
	AnimState.JUMP_FORWARD: "Jump Forward",
	AnimState.STAND_TO_CROUCH: "Rifle Stand To Kneel",
	AnimState.CROUCH_TO_STAND: "Rifle Kneel To Stand",
	AnimState.HIT_REACTION: "Hit Reaction",
	AnimState.TOSS_GRENADE: "Toss Grenade",
	AnimState.DEATH: "Death",
	AnimState.RUN: "Rifle Run",
	AnimState.CROUCH_HIT_BACK: "Rifle Kneel Hit To Back",
	AnimState.RELOADING: "Reloading",
	AnimState.RELOAD_WALK_FORWARD: "Reloading Walk",
	AnimState.RELOAD_WALK_BACKWARD: "Reloading Walk Backward",
	AnimState.RELOAD_STRAFE_LEFT: "Reloading Strafe Left",
	AnimState.RELOAD_STRAFE_RIGHT: "Reloading Strafe Right",
	AnimState.RELOAD_CROUCH_WALK_FORWARD: "Reloading Crouch Walk Forward",
	AnimState.RELOAD_CROUCH_WALK_BACKWARD: "Reloading Crouch Walk Backward",
	AnimState.RELOAD_CROUCH_STRAFE_LEFT: "Reloading Crouch Strafe Left",
	AnimState.RELOAD_CROUCH_STRAFE_RIGHT: "Reloading Crouch Strafe Right",
	AnimState.RELOAD_CROUCH_IDLE: "Reloading Crouch Idle",
	AnimState.RELOAD_STAND_TO_CROUCH: "Reloading Stand To Crouch",
	AnimState.RELOAD_CROUCH_TO_STAND: "Reloading Crouch To Stand",
	AnimState.NEPAL_ATTACK_LIGHT: "Nepal Attack Light",
	AnimState.NEPAL_ATTACK_HEAVY: "Nepal Attack Heavy",
}

# 一次性动画集合（不循环）
const ONE_SHOT_STATES: Array = [
	AnimState.JUMP_UP, AnimState.JUMP_DOWN, AnimState.JUMP_FORWARD,
	AnimState.STAND_TO_CROUCH, AnimState.CROUCH_TO_STAND,
	AnimState.HIT_REACTION, AnimState.TOSS_GRENADE,
	AnimState.DEATH,
	AnimState.CROUCH_HIT_BACK, AnimState.RELOADING,
	AnimState.RELOAD_WALK_FORWARD, AnimState.RELOAD_WALK_BACKWARD,
	AnimState.RELOAD_STRAFE_LEFT, AnimState.RELOAD_STRAFE_RIGHT,
	AnimState.RELOAD_CROUCH_WALK_FORWARD, AnimState.RELOAD_CROUCH_WALK_BACKWARD,
	AnimState.RELOAD_CROUCH_STRAFE_LEFT, AnimState.RELOAD_CROUCH_STRAFE_RIGHT,
	AnimState.RELOAD_CROUCH_IDLE,
	AnimState.RELOAD_STAND_TO_CROUCH, AnimState.RELOAD_CROUCH_TO_STAND,
	AnimState.NEPAL_ATTACK_LIGHT, AnimState.NEPAL_ATTACK_HEAVY,
]

# ============================================================
# 物理参数
# ============================================================
const STANDING_HEIGHT: float = 1.8
const CROUCHING_HEIGHT: float = 1.1
const COLLISION_RADIUS: float = 0.45

## 【100%换皮】物理参数按当前角色资产读取（无资产/未配置时回退默认常量）。
## 使身高/碰撞体等角色差异进入数据（CharacterAsset.standing_height 等），
## 新角色只需在资产里配数值，代码零改动。
func _standing_height() -> float:
	if char_manager != null and char_manager.get_active_asset() != null:
		var h: float = char_manager.get_active_asset().standing_height
		if h > 0.1:
			return h
	return STANDING_HEIGHT

func _crouching_height() -> float:
	if char_manager != null and char_manager.get_active_asset() != null:
		var h: float = char_manager.get_active_asset().crouching_height
		if h > 0.1:
			return h
	return CROUCHING_HEIGHT

func _collision_radius() -> float:
	if char_manager != null and char_manager.get_active_asset() != null:
		var r: float = char_manager.get_active_asset().capsule_radius
		if r > 0.05:
			return r
	return COLLISION_RADIUS
const MAX_WALK_SPEED: float = 7.5             # 站姿移动速度（原5.0提升0.5倍），动画通过DESIGN_WALK_SPEED自动同步1.5倍播放
const MAX_CROUCH_SPEED: float = 2.2
const JUMP_VELOCITY: float = 4.2
const JUMP_DELAY: float = 0.05             # 跳跃延迟（秒），让动画提前播放，减少延迟感
const GRAVITY: float = -9.8
const ACCELERATION: float = 35.0           # 高加速度消除起步粘滞感（0.14s达到满速）
const DECELERATION: float = 30.0           # 中等减速，停车自然但不拖沓（从15.0提升，消除滑行）
const RUN_DECELERATION: float = 50.0       # 奔跑时减速度，高减速让奔跑松键后快速停下
const START_BOOST_RATIO: float = 0.3       # 起步瞬间速度提升比例（直接给到30%满速，消除0→加速的延迟感）
const AIR_CONTROL_FACTOR: float = 0.3
const DESIGN_WALK_SPEED: float = 5.0       # 动画倍率基准速度
const REFERENCE_WALK_ANIM_LEN: float = 0.967  # 参考动画长度（Walking动画），用于标准化各方向动画播放速度
const REFERENCE_CROUCH_ANIM_LEN: float = 1.033  # 参考蹲姿动画长度
const MAX_RUN_SPEED: float = 15.0           # 奔跑最大速度（m/s）= walk速度(7.5)的2倍
const DESIGN_RUN_SPEED: float = 10.0        # 奔跑动画倍率基准速度（动画倍速=实际速度/10.0）
											# Rifle Run: 0.7s/周期, 2步/周期 → 1x时步频=2.857Hz
											# DESIGN=10.0时步长=10.0/2.857=3.5m；15m/s时1.5x播放，步频4.29Hz，步长3.5m(无滑步)
const REFERENCE_RUN_ANIM_LEN: float = 0.7  # 参考奔跑动画长度

# 换弹固定时长（秒）：以 Reloading 动画长度为准，时长一到即结束并灵活切换动画
const RELOAD_DEFAULT_DURATION: float = 2.2
# 死亡后自动复活延迟（秒）：死亡动画播完后停留片刻再起身
const DEATH_REVIVE_DELAY: float = 1.0

# ============================================================
# 动画参数
# ============================================================
const ANIM_FADE_TIME: float = 0.15          # 动画淡入淡出过渡时间（秒）
# 丝滑度保障：自适应混合时长（按切换对的姿态差异/历史跳变量动态决定 blend）
const ANIM_FADE_TIME_BIG: float = 0.35      # 大姿态差异切换（换弹/受击/跳跃/死亡等）用更长混合，插帧更充分、动作更丝滑
const ANIM_FADE_TIME_MAX: float = 0.5       # 自适应混合时长上限（运行时按跳变量自动上调）
# 空间跳变检测阈值（检验实时空间坐标变换）
const SWITCH_HAND_JUMP_THRESHOLD: float = 0.2   # 切换混合窗内手部骨骼世界位移超 20cm 视为姿态跳变
const SWITCH_ROT_JUMP_THRESHOLD_DEG: float = 25.0 # 切换混合窗内视觉根旋转超 25° 视为跳变
const SWITCH_VERTICAL_SNAP_THRESHOLD: float = 0.12  # 切换混合窗内视觉模型Y每帧瞬时下沉超 12cm 视为瞬移（蹲下/起立跳变）
const CROUCH_BLEND_TIME: float = 0.35    # 离开蹲/起过渡切到稳定姿态的交叉淡入时长(吸收过渡末帧→目标首帧姿态差异,消除瞬移)
const CROUCH_ENTER_BLEND: float = 0.1    # 进入蹲/起过渡时的短交叉淡入:平滑"待机任意相位→过渡首帧"的snap(远小于当年0.3s,不会拖影)

const LANDING_COOLDOWN: float = 0.12        # 落地检测防抖时间（秒）
const CROUCH_CLICK_THRESHOLD: float = 0.2   # 蹲下点击/长按判断阈值（秒）
const CROUCH_TRANSITION_DURATION: float = 0.5  # 蹲下/起立过渡时长（秒），动画播放速度和相机tween同步此值
const VISUAL_CROUCH_OFFSET: float = -1.0   # 蹲下待机时视觉模型Y偏移（Hips rest pose 1.794m → 蹲姿目标 0.794m）
											# 蹲姿待机：feet at y≈0.14（正确贴地）
const VISUAL_CROUCH_WALK_OFFSET: float = -0.45  # 蹲下移动时视觉模型Y偏移
											# 蹲姿移动动画的腿部旋转伸展更远，需要更高的偏移防止脚尖陷地

## 【100%换皮】蹲伏视觉偏移按当前角色资产读取（无资产/未配置回退默认）。
## 蹲姿高度 = 视觉模型下压 offset + 蹲姿动画腿弯曲，offset 是角色特有标定
## （取决于 rest 骨架身高/腿长比例），必须进数据（CharacterAsset.crouch_visual_offset）。
func _crouch_visual_offset() -> float:
	if char_manager != null and char_manager.get_active_asset() != null:
		var v: float = char_manager.get_active_asset().crouch_visual_offset
		if v < 0.0:
			return v
	return VISUAL_CROUCH_OFFSET

func _crouch_walk_visual_offset() -> float:
	if char_manager != null and char_manager.get_active_asset() != null:
		var v: float = char_manager.get_active_asset().crouch_walk_visual_offset
		if v < 0.0:
			return v
	return VISUAL_CROUCH_WALK_OFFSET
											# 蹲姿移动：feet at y≈0.1+（脚尖不穿地）
const VISUAL_LERP_SPEED: float = 12.0      # 视觉模型Y偏移插值速度

# 上下半身骨骼分类（用于换弹+行走动画混合）
const UPPER_BODY_BONES: Array = [
	"Spine", "Spine1", "Spine2", "Neck", "Head",
	"LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
	"RightShoulder", "RightArm", "RightForeArm", "RightHand",
]
# 【手枪姿态】用户用 swat 在 Mixamo 导出的"手枪待机"动画（已烘焙为 Animation 资源，
# 轨道路径 Armature/Skeleton3D:mixamorig_*，与 swat 骨架一致）。
# 持手枪(v_deagle)时：3P 上半身(UPPER_BODY_BONES)用手枪待机姿态，下半身沿用原动画。
const PISTOL_IDLE_ANIM_PATH := "res://resources/animations/pistol_idle_swat.tres"
## 【手枪持枪方案·最终】只裁剪双手：双臂（肩/臂/前臂/手）用手枪待机的局部旋转，
## 脊柱/头/腿全部沿用步枪待机（swat Rifle Aiming Idle）——身体不扭转、持枪手臂自然朝前
## （步枪与手枪 Spine 差异仅 ~6.7°，双臂局部直接搬运即可；实测前臂方向 92.5°≈前向 90°）。
## 合成长度 = 步枪待机整周期(2.633s) → 上下半身都循环无缝，消除 1s 接缝抖动。
const ARMS_BONES: Array = [
	"LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
	"RightShoulder", "RightArm", "RightForeArm", "RightHand",
]
# 【手枪与步枪同高度】手臂抬升角（度）：由当前武器 rig 配置 arm_lift_deg 注入
#（v_deagle=18）。合成时 Shoulder rotation 左乘绕 rest x 轴抬臂（肩骨位置不动=不耸肩）。
const PISTOL_ARM_LIFT_DEG_DEFAULT := 18.0
# 运行时当前武器的抬臂角（_apply_pistol_stance 时从 def.weapon_rig_config.arm_lift_deg 读取）
var _pistol_arm_lift_deg: float = 0.0
## 持手枪时替换为"手枪待机上半身 + 原动画下半身"的常驻状态集
const PISTOL_STANCE_STATES: Array = [
	AnimState.IDLE_AIM, AnimState.WALK_FORWARD, AnimState.WALK_BACKWARD,
	AnimState.STRAFE_LEFT, AnimState.STRAFE_RIGHT, AnimState.RUN,
	AnimState.CROUCH_IDLE_AIM,
	# 站蹲过渡/蹲走同上半身合成（否则过渡过程与蹲走仍是持枪动作）
	AnimState.STAND_TO_CROUCH, AnimState.CROUCH_TO_STAND,
	AnimState.CROUCH_WALK_FORWARD, AnimState.CROUCH_WALK_BACKWARD,
	AnimState.CROUCH_STRAFE_LEFT, AnimState.CROUCH_STRAFE_RIGHT,
	# 跳跃同上半身合成（否则跳跃动画仍是持枪动作）
	AnimState.JUMP_UP, AnimState.JUMP_DOWN, AnimState.JUMP_FORWARD,
]

## 持尼泊尔刀时替换为"持刀手臂 + 原动画身体"的状态集（比手枪多站蹲过渡/蹲走，
## 否则站立↔蹲下过程与蹲走仍是持枪动作）。过渡/蹲走/跳跃均为一次性或循环，同样合成。
const NEPAL_STANCE_STATES: Array = [
	AnimState.IDLE_AIM, AnimState.WALK_FORWARD, AnimState.WALK_BACKWARD,
	AnimState.STRAFE_LEFT, AnimState.STRAFE_RIGHT, AnimState.RUN,
	AnimState.CROUCH_IDLE_AIM,
	AnimState.STAND_TO_CROUCH, AnimState.CROUCH_TO_STAND,
	AnimState.CROUCH_WALK_FORWARD, AnimState.CROUCH_WALK_BACKWARD,
	AnimState.CROUCH_STRAFE_LEFT, AnimState.CROUCH_STRAFE_RIGHT,
	AnimState.JUMP_UP, AnimState.JUMP_DOWN, AnimState.JUMP_FORWARD,
]
var _pistol_upper: Animation = null       # 手枪待机动画（上半身来源）
var _pistol_saved: Dictionary = {}        # state -> 原动画备份（恢复用）
var _pistol_applied: Array = []           # 已应用合成的 state 列表
# 仅"持枪手臂"骨骼（用于蹲站过渡合成）：只替换手臂为站姿待机的持枪姿势，
# 保留 Spine/Neck/Head 原动画——Mixamo 蹲站动画的脊柱/头自带平衡补偿
# （蹲下时反向旋转保持上身直立），若整个上半身都被替换会丢失补偿导致"歪"。
const GRIP_BONES: Array = [
	"LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
	"RightShoulder", "RightArm", "RightForeArm", "RightHand",
]
# ============================================================
# 【尼泊尔 3P·刀挂点】刀以 BoneAttachment3D 挂右手骨骼（mixamorig_RightHand），
# 刀位 = 每角色标定资源（见 _get_nepal_knife_local；标定场景 scenes/nepal_knife_calib.tscn）。
# BoneAttachment3D 铁律：挂点 transform 每帧被引擎覆盖为骨骼姿态，偏移/旋转必须
# 写在【刀节点本身】，写在挂点上全部失效。
# ------------------------------------------------------------
# 挂载方案沿革（改刀位前必读，避免改错层）：
#   第一代：全局局部常量 NEPAL_KNIFE_LOCAL_*（飞虎 A 空间）+ 运行时 k=0.00026/角色
#           骨架缩放换算 —— k 假设两骨架纯缩放，实测 SWAT 骨骼姿态有旋转差 → 偏移。
#   第二代：WYSIWYG 世界变换（下方 WORLD_TRANSFORM/HANDLE_LOCAL，仅存档）——运行时
#           采样骨骼实时姿态算 L，因"移动中切刀采样时刻不同 → 刀位漂移"废弃；
#           运行时加载预览场景亦曾引发 SIGSEGV（预览内嵌 character.tscn 与游戏侧
#           实例冲突），故运行时永不加载预览场景。
#   第三代（现行）：每角色标定 tres（标定场景拖拽直存），运行时固定 L，无换算。
# ------------------------------------------------------------
const NEPAL_KNIFE_BONE := "mixamorig_RightHand"
# 【第二代已废弃·仅存档】WYSIWYG 世界变换与刀柄标记点（运行时不引用）
const NEPAL_KNIFE_WORLD_TRANSFORM := Transform3D(
	Basis(Vector3(4.2397957, -1.4442694, -0.43383864), Vector3(1.473275, 4.2432985, 0.2718068), Vector3(0.3218544, -0.3981264, 4.4707847)),
	Vector3(-0.78704, 2.6070855, 0.62807226))
const NEPAL_KNIFE_HANDLE_LOCAL := Vector3(0.06743136, -0.08033663, 0.006910801)
# 【第一代·现为回退兜底】旧全局局部常量（飞虎 A 空间）：仅当角色缺标定 tres 时
# 由 _get_nepal_knife_local ×k 使用（标定 tres 播种值即由它推导，行为等价）
const NEPAL_KNIFE_LOCAL_POS := Vector3(1285.234375, -185.922363, -1347.628662)
const NEPAL_KNIFE_LOCAL_ROT := Quaternion(-0.301986, -0.627026, -0.380828, 0.608780)
const NEPAL_KNIFE_LOCAL_SCALE := Vector3(17307.695313, 17307.693359, 17307.695313)
# 旧预览场景（"打印常量→手工抄写"流程已废弃）；现行标定场景见 scenes/nepal_knife_calib.tscn
const NEPAL_PREVIEW_SCENE := "res://scenes/nepal_knife_preview.tscn"
# 【尼泊尔 3P】手臂抬升角（度）：用户反馈"重击末帧持刀姿态偏低"，在 _nepal_combine 时对
# Shoulder 骨左乘绕 rest x 轴抬臂（sign 统一 -1，与手枪一致）。如需再调，编辑此值即可。
const NEPAL_ARM_LIFT_DEG := 22.0
# 【尼泊尔 3P 接入】用户自制挥砍动画（桌面"新导出"轻击.fbx/重击.fbx，骨架名已改回 Armature）。
# 只替换手臂 8 骨（Shoulder/Arm/ForeArm/Hand），其余身体沿用步枪动画（呼吸/移动）。
# 铁律：仅 rotation 轨迹；动画库写操作前 stop；骨架名必须 Armature（轨迹前缀已对齐）。
const NEPAL_IDLE_ARMS_PATH := "res://resources/animations/nepal3p/nepal_idle_arms.tres"
const NEPAL_LIGHT_ARMS_PATH := "res://resources/animations/nepal3p/nepal_light_arms.tres"
const NEPAL_HEAVY_ARMS_PATH := "res://resources/animations/nepal3p/nepal_heavy_arms.tres"
var _nepal_idle_arms: Animation = null     # 待机持刀手臂（重击末帧静态姿态）
var _nepal_light_arms: Animation = null    # 轻击挥砍手臂
var _nepal_heavy_arms: Animation = null    # 重击挥砍手臂
var _nepal_saved: Dictionary = {}          # state -> 原动画备份（恢复用）
var _nepal_applied: Array = []             # 已应用待机合成的 state 列表
var _nepal_atk_lower: AnimState = AnimState.IDLE_AIM  # 当前攻击合成动画用的下半身状态（动态跟随比对）
var _nepal_atk_start_ms: int = 0          # 挥刀起手时刻（Time.get_ticks_msec），用于起手保护
var _nepal_last_follow_ms: int = -1       # 上次下半身跟随重合成时刻，用于限频（防频繁 stop/play 卡顿）
# 【方案C·挥砍分层叠加】挥砍不再烤合成动画进独占状态，改为：状态机照常驱动下半身
# （蹲起/走跑跳过渡天然生效），手臂 8 骨每帧用挥砍资源采样直驱覆盖（与 _apply_torso_pitch_overlay
# 同机制）。这三个字段记录直驱会话，挥砍结束/被打断/切角色时清除。
var _nepal_attacking: bool = false        # 挥砍直驱会话进行中
var _nepal_atk_elapsed: float = 0.0       # 挥砍时间轴（秒），驱动手臂采样
var _nepal_atk_arms: Animation = null     # 当前挥砍的手臂资源（轻击/重击）
var _nepal_atk_track_bones: Dictionary = {}  # 【性能】挥砍会话内 轨道→骨骼索引 缓存
const NEPAL_FOLLOW_START_GUARD_MS: int = 120   # 挥刀起手保护期：起手 0.12s 内不重合成（挡"挥刀瞬间按蹲/移动"的立即打断）
const NEPAL_FOLLOW_MIN_INTERVAL_MS: int = 80   # 两次重合成最小间隔 0.08s（挡蹲/方向快速变化的频繁 stop/play）

# ================= 手雷 3P 手臂（Toss Grenade 裁剪版，2026-09-01） =================
# 方案：原版 "Toss Grenade" 全身动画裁剪（拉环 5-37 帧 / 抛出 38-48 帧，30fps），
# 只取上半身 13 骨旋转（8 臂骨 + 5 躯干骨），加速匹配 FP 时长（plugin 0.6444s /
# Throw 0.2250s），衔接过渡（待机→拉环 0.12s slerp、抛出→待机 0.12s slerp，烘焙在
# tres 里），待机复用尼泊尔手臂姿势（nepal3p/nepal_idle_arms.tres）。
# 手势对齐 FPViewmodelPlayer：按下=拉环 → 播完按住=持环等待(停拉环末帧) → 松开=投掷；
# 点按=拉环播完自动投掷。弃用 TOSS_GRENADE 全身动画方案。
const GRENADE_HOLD_ARMS_PATH := "res://resources/animations/grenade3p/grenade_hold_arms.tres"
const GRENADE_PULL_ARMS_PATH := "res://resources/animations/grenade3p/grenade_pull_arms.tres"
const GRENADE_THROW_ARMS_PATH := "res://resources/animations/grenade3p/grenade_throw_arms.tres"
# FP 统一时钟映射常量（与 grenade_toss_kit.gd 一致）：拉环动画 = 0.12s 过渡 + 0.6444s 动作
const GRENADE_BLEND_LEAD := 0.12
const GRENADE_FP_PULL_DUR := 0.6444
const GRENADE_FP_THROW_DUR := 0.2250
const GRENADE_THROW_LEAD := 0.08   # 投掷前过渡（拉环末帧→抛出首帧，消除瞬间跳变）
const GRENADE_STANCE_STATES: Array = NEPAL_STANCE_STATES
var _grenade_hold_arms: Animation = null    # 待机（尼泊尔手臂姿态）
var _grenade_pull_arms: Animation = null    # 拉环（过渡+动作）
var _grenade_throw_arms: Animation = null   # 投掷（动作+过渡）
var _grenade_saved: Dictionary = {}         # state -> 原动画备份（恢复用，同 _nepal_saved 纪律）
var _grenade_applied: Array = []            # 已应用待机合成的 state 列表
var _grenade_held: bool = false             # 左键按住（拉环中/持环等待）
var _grenade_holding: bool = false          # 拉环播完仍按住 → 持环等待（停拉环末帧）
var _grenade_pulling: bool = false          # 拉环直驱会话进行中
var _grenade_throwing: bool = false         # 投掷直驱会话进行中
var _grenade_arms: Animation = null         # 当前直驱资源（pull/throw）
var _grenade_elapsed: float = 0.0           # 3P 本地时间轴（秒）
var _grenade_track_bones: Dictionary = {}   # 【性能】会话内 轨道→骨骼索引 缓存
var _grenade_track_res: Animation = null    # 轨道映射缓存所属资源（换资源自动重建）
# 【投掷尾过渡】FP 模式下投掷跟随 FP 时钟只播动作段（0.08+0.225），FP Throw 播完
# 影子若立即清会从甩出姿态跳回持雷（僵直/磕头观感）→ 继续播 tres 烘焙的 0.12s 尾过渡
# 平滑回持雷再清。
var _grenade_tail_t: float = 0.0
# 【头部锁定】蹲左走动画的 Neck 摆动 5°（其他方向 0-3°，日志实测）→ 拉环态蹲左走
# 每步头部磕头（1s 一下=步伐周期）。拉环/投掷/持环期间锁 Neck/Head 姿态（记录开始值
# 每帧写回）：头部不随蹲走摆动；低头（pitch 旋转 Spine）仍带动头部（局部锁不阻父链）。
var _grenade_neck_idx: int = -1
var _grenade_head_idx: int = -1
var _grenade_neck_lock: Quaternion = Quaternion.IDENTITY   # Neck 自己的锁定姿态
var _grenade_head_lock: Quaternion = Quaternion.IDENTITY   # Head 自己的锁定姿态
var _grenade_head_locked: bool = false
# 【调试日志】骨骼世界坐标采样（定位"抛完后左走僵直/磕头"用）。开游戏复现场景跑
# 几秒，日志写 grenade_debug.log，关游戏后贴结果。
const GRENADE_DEBUG_LOG := false
const GRENADE_LOG_PATH := "C:/Users/93343/Desktop/demo/grenade_debug.log"
var _grenade_log_frame: int = 0
# ===== 动画操作追踪（超级日志 v3：定位"谁在动动画"，蹲左走 1s 一次磕头）=====
var _anim_op_tag := ""            # 最近一次 play/seek/stop/install 操作标识
var _anim_op_frame := -1          # 该操作发生的引擎总处理帧号（Engine.get_process_frames）
var _stance_install_seq := 0      # stance 重合成（AnimationCombiner.install）总次数
var _prev_log_pos := -1.0         # 日志用：上一帧动画 pos（算 dpos 增量）
var _prev_log_anim := ""          # 日志用：上一帧动画名（动画切换时 dpos 重置）

## 动画操作打点：记录"谁动了动画"。超级日志每帧打印最近一次操作 + 距今帧数，
## 跳变帧若 op 距 0 帧 → 该调用点就是元凶；若 install 计数变化 → stance 重合成干的。
func _anim_op(tag: String) -> void:
	_anim_op_tag = tag
	_anim_op_frame = Engine.get_process_frames()

var _nepal_knife: Node3D = null             # 3P 刀实例（BoneAttachment 挂右手）
var _nepal_knife_attach: Node3D = null      # BoneAttachment3D（右手骨骼挂点）
# 【崩溃修复】尼泊尔刀异步挂载协程的代际标记：每次启动新协程时递增。
# 协程在每个 await 恢复后检查代际，若已变化（期间又切了刀/枪）则立即放弃，
# 防止两个协程并发 load/实例化 nepal_knife_preview.tscn（@tool 场景的动画合成
# 会与游戏侧持刀合成在共享 AnimationPlayer 上竞争）→ 第二次切尼泊尔刀 SIGSEGV。
var _nepal_mount_generation: int = 0
# 【崩溃修复·治本】不再加载预览场景（nepal_knife_preview.tscn 内嵌 character.tscn 2.1MB，
# 运行时加载在用户实机崩溃）。标定常量已写死，运行时直接用 nepal_knife.glb + 常量挂载。
# 挂载状态机: [step:int, gen:int, skel:Skeleton3D, ba:Node3D, def:WeaponDef, preview:Node, wait:int]
# （preview/def 已不使用，保留占位保持索引稳定）
var _nepal_mount_pending: Array = []

# ===== 手雷 3P 模型绑定（BoneAttachment 挂右手骨骼，仿尼泊尔刀流程）=====
# 模型：resources/models/grenade/grenade_world.glb（用户从 FP 提取的纯手雷，无手无骨骼）
# 标定：每角色一份 calib tres（复用 NepalKnifeCalib 数据类，duck-type 访问），
#       内容 = 手雷相对右手骨骼局部系的 transform（编辑器标定场景可调）。
const GRENADE_MODEL_PATH := "res://resources/models/grenade/grenade_world.glb"
const GRENADE_MODEL_BONE := "mixamorig_RightHand"
const GRENADE_CALIB_PATHS := {
	"feihu": "res://resources/characters/grenade_calib_feihu.tres",
	"swat": "res://resources/characters/grenade_calib_swat.tres",
}
var _grenade_model: Node3D = null           # 3P 手雷实例
var _grenade_attach: Node3D = null          # BoneAttachment3D（右手骨骼挂点）
var _grenade_calib_cache: Dictionary = {}   # (已弃用) 标定每次强制读盘，不再缓存——缓存会命中旧值导致"改了没生效"
var _grenade_mount_generation: int = 0
# 挂载状态机: [step:int, gen:int, skel:Skeleton3D, ba:Node3D, wait:int]
var _grenade_mount_pending: Array = []

# 应彻底移除 3D 位置轨道的动画状态集合（与 _remove_position_tracks_from_looping_anims
# 的 target_states 一致）。_verify_animation_tracks() 用它校验"位置轨道确实已删除"。
# 例外：Death 故意保留位置轨道以播放完整倒地位移，故不在此列。
const POSITION_TRACK_STRIP_STATES: Array = [
	AnimState.IDLE_AIM,
	AnimState.WALK_FORWARD,
	AnimState.WALK_BACKWARD,
	AnimState.STRAFE_LEFT,
	AnimState.STRAFE_RIGHT,
	AnimState.CROUCH_IDLE_AIM,
	AnimState.CROUCH_WALK_FORWARD,
	AnimState.CROUCH_WALK_BACKWARD,
	AnimState.CROUCH_STRAFE_LEFT,
	AnimState.CROUCH_STRAFE_RIGHT,
	AnimState.STAND_TO_CROUCH,
	AnimState.CROUCH_TO_STAND,
	AnimState.HIT_REACTION,
	AnimState.TOSS_GRENADE,
	AnimState.RUN,
	AnimState.CROUCH_HIT_BACK,
	AnimState.RELOADING,
	AnimState.RELOAD_WALK_FORWARD,
	AnimState.RELOAD_WALK_BACKWARD,
	AnimState.RELOAD_STRAFE_LEFT,
	AnimState.RELOAD_STRAFE_RIGHT,
	AnimState.RELOAD_CROUCH_WALK_FORWARD,
	AnimState.RELOAD_CROUCH_WALK_BACKWARD,
	AnimState.RELOAD_CROUCH_STRAFE_LEFT,
	AnimState.RELOAD_CROUCH_STRAFE_RIGHT,
	AnimState.RELOAD_CROUCH_IDLE,
	AnimState.RELOAD_STAND_TO_CROUCH,
	AnimState.RELOAD_CROUCH_TO_STAND,
	AnimState.JUMP_UP,
	AnimState.JUMP_DOWN,
	AnimState.JUMP_FORWARD,
]

# ============================================================
# 节点引用
# ============================================================
# 【P2 修订】anim_player / character_visual 在融合场景下由 CharacterManager
# 挂载后解析（挂载点在 _ready 前是空节点），故不用 @onready 直接求值（会 Node not found），
# 改为普通变量 + _ready 里统一解析：旧模式（player.tscn 内嵌角色）解析 $Character/AnimationPlayer；
# 融合模式（player_multichar.tscn 空挂载点）解析挂载的 ActiveCharacter。
var anim_player: AnimationPlayer = null
var _connected_anim_player: AnimationPlayer = null  # 已连接信号的播放器（角色切换后 anim_player 变化需重连）
var _weapon_system: WeaponSystem = null              # 【P3】武器系统（当前武器数据/握持配置/音效）
var _applied_weapon_id: String = ""                  # 【P3】已应用到子系统的武器 id（同武器切换不重复刷新）
var _prev_weapon_id: String = ""                     # 【Q键】上一把实际持有的武器（空=开局/复活后未换过枪）
# 【P3】能力系统（Ability 框架）：新动作逻辑 = 独立 Ability 子类注册进来
var _abilities: Array = []                            # 已注册能力实例列表
var _active_ability: Ability = null                   # 当前激活中的能力
var _ability_speed_mult: float = 1.0                  # 能力移动速度倍率（SprintBurst 等写入）
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera_controller: CameraController = $CameraPivot
var character_visual: Node3D = null         # 视觉模型节点（用于过渡动画期间上下移动）

# ============================================================
# 【P3 多武器】开镜状态：M82 专属（右键按住 = 4 倍放大 + 瞄准镜 PNG 前景覆盖）。
# 开镜时隐藏 FP viewmodel/3P 角色/枪口火光/阴影——PNG 自带瞄准镜框，画面不再区分人称。
# ============================================================
const SCOPE_ZOOM_FACTOR: float = 4.0          # 4 倍放大（FOV / 4）
# 【数据驱动】可开镜武器改由 WeaponDef.scopable 字段判定（原 SCOPE_WEAPON_ID="m82a1" 常量已删除）
var _scope_overlay: CanvasLayer = null        # ScopeOverlay 实例（运行时从 ui/scope_overlay.tscn 加载）
var _scoping: bool = false                     # 是否正在开镜
var _scope_saved_fov: float = 70.0            # 开镜前的 FOV（exit 时恢复）
var _scope_shot_pending: bool = false          # 【P3】开镜中射击：等待射击动画结束后自动重开镜
var _scope_shot_cancel: bool = false           # 【P3】重开镜取消标志（切枪/换弹/手动干预中断）
var _scope_saved_fp_visible: bool = false      # 开镜前的 FP viewmodel visible（exit 时恢复）
var _scope_saved_holder_visible: bool = true   # 开镜前的 3P 世界枪 visible（exit 时恢复）
var _scope_saved_dyn_visible: bool = true      # 开镜前的动态 world_model visible（exit 时恢复）

# ============================================================
# 角色系统（P2 解耦）：CharacterManager 未挂载时自动回退到 ANIM_NAMES 默认表
# ============================================================
var char_manager: CharacterManager = null   # 由 Main 注入（可空=旧模式单角色）
var anim_director: AnimationDirector = null # 动画名查询走当前角色资产（可空=回退）

# 逻辑状态 → 动画名：优先查当前角色资产.anim_map，缺失回退默认表 ANIM_NAMES。
# 这是动画名查询的唯一入口（替代散落的 ANIM_NAMES.get），P2 逐点替换。
func _anim_name_for(state: AnimState) -> String:
	if anim_director != null:
		var n: String = anim_director.anim_name(_anim_state_str(state))
		if n != "":
			return n
	return ANIM_NAMES.get(state, "")

# AnimState 枚举 → 字符串键（与 anim_map 的键一致：如 IDLE_AIM）
func _anim_state_str(state: AnimState) -> String:
	return AnimState.keys()[state]

# ============================================================
# 动画缓存（预加载，避免运行时重复查找）
# ============================================================
var _anim_cache: Dictionary = {}  # 缓存 Animation 对象引用

# ============================================================
# 调试输出（仅在 DEBUG_MODE=true 时输出）
# ============================================================
func debug_print(msg: String):
	if DEBUG_MODE:
		print(msg)

# ============================================================
# 统一空间坐标日志（蹲姿待机 vs 蹲姿移动 对比用）
# 记录：视觉模型Y、碰撞体高度/位置、Armature全局Y、Hips全局Y、相机信息、Player全局Y
# ============================================================
func _log_spatial_info(context: String):
	if not DEBUG_MODE:
		return
	AnimationDiagnostics.log_spatial_info(context, self, camera_controller)

## 【性能】CharacterHUD 引用缓存：原先 6 处调用点每次都从 root 全树递归
## find_child（含 2MB 角色骨架子树），开镜/切枪/输入路径高频触发。HUD 为
## 稳定单例，首次查找后缓存，被释放时自动重查。
var _hud_node: Node = null
func _get_hud() -> Node:
	if _hud_node == null or not is_instance_valid(_hud_node):
		_hud_node = get_tree().root.find_child("CharacterHUD", true, false)
	return _hud_node

# 把状态枚举数组翻译成动画名数组（供诊断器使用）
func _anim_names_for(states: Array) -> Array:
	var names: Array = []
	for state in states:
		var n: String = _anim_name_for(state)
		if not n.is_empty():
			names.append(n)
	return names

# ============================================================
# 状态变量
# ============================================================
var current_state: AnimState = AnimState.IDLE_AIM
var previous_state: AnimState = AnimState.IDLE_AIM
var is_crouching: bool = false
var is_dead: bool = false
var is_transitioning: bool = false       # 过渡动画锁：过渡期间屏蔽蹲伏输入
var transition_timer: float = 0.0        # 过渡超时计时器
var was_in_air: bool = false
var landing_cooldown_timer: float = 0.0  # 落地防抖计时器
var input_dir: Vector2 = Vector2.ZERO    # 当前帧输入方向
var _startup_frames: int = 0             # 启动帧计数，用于地面检测稳定后允许蹲下
var _crouch_hold: bool = false           # 是否正在按住蹲下键
var _crouch_press_time: float = 0.0      # 蹲下键按下持续时间
var _k_was_pressed: bool = false          # 上一帧 K 键状态（用于死亡复活检测，防止同一帧按下触发死亡和复活）
var _last_played_state: AnimState = AnimState.DEATH  # 初始化为非默认状态，确保首次播放
var _jump_delay_timer: float = 0.0       # 跳跃延迟计时器，等待动画蓄力帧播放后再施加物理跳跃
var _target_visual_y: float = 0.0        # 目标视觉模型Y偏移（蹲姿待机/移动使用不同值，平滑插值过渡）
var is_running: bool = false                # 是否处于奔跑状态
var _is_in_crouch_hit_back: bool = false    # 是否正在播放蹲姿受击倒地动画
var _jump_from_run: bool = false            # 奔跑跳跃标志：跳跃期间维持奔跑速度，落地后清除
var _running_exit_timer: float = 0.0  # 奔跑退出延迟计时器，防止视角转动时input_dir短暂波动导致频繁退出
var _reload_duration: float = 0.0          # 换弹固定时长（运行时取 Reloading 动画长度）
var _reload_anim_len: float = 0.0          # 3P Reloading 动画实际长度（含回位尾巴，取中间值时用）
var _is_reloading: bool = false            # 是否正在换弹（固定时长计时中）
var _reload_elapsed: float = 0.0          # 换弹已进行时长方（统一时间轴，与展示变体无关）
const RELOAD_INPUT_BUFFER: float = 0.5    # 换弹输入缓冲时长（秒）：与蹲/刺刀同帧或蹲过渡/刺刀防护期
										   # 按下 R 时 just_pressed 当帧被吞，缓冲若干帧重试，避免"换弹被吃掉→没声音"
var _reload_input_buffer: float = 0.0      # 换弹输入缓冲剩余时间（>0 表示应尝试触发换弹）
var _death_await_revive: bool = false      # 死亡动画结束后是否等待自动复活
var _death_revive_timer: float = 0.0       # 死亡后自动复活倒计时
var _spawn_point: Vector3 = Vector3.ZERO   # 出生点（_ready 记录；复活用，勿硬编码原点）

# 受击/投掷状态
var _is_in_one_shot_override: bool = false  # 是否正在播放可覆盖的一次性动画（受击/投掷）
var _state_before_one_shot: AnimState = AnimState.IDLE_AIM  # 记录进入一次性动画前的状态

# 调试变量
var _debug_counter: int = 0
var _anim_log_counter: int = 0           # 动画播放完整日志计数器
var _prev_anim_position: float = -1.0    # 上一帧的动画播放位置（用于检测跳变）
var _anim_position_jumps: int = 0
# ---- 丝滑度保障：空间跳变检测 + 自适应混合 ----
var _hand_bone: Node3D = null               # 采样用骨骼（右手/左手），_ready 中解析
var _switch_active: bool = false           # 是否处于切换混合窗采样中
var _switch_from_state: AnimState = AnimState.IDLE_AIM   # 切换前状态
var _switch_to_state: AnimState = AnimState.IDLE_AIM     # 切换后状态
var _switch_from_hand_pos: Vector3 = Vector3.ZERO        # 切换前手部骨骼世界坐标（基准）
var _switch_from_visual_quat: Quaternion = Quaternion.IDENTITY  # 切换前视觉根旋转（基准）
var _switch_max_hand_delta: float = 0.0    # 混合窗内手部最大位移
var _switch_max_rot_deg: float = 0.0       # 混合窗内根旋转最大角度
# ---- 武器握持（P0-1 / P0-2）----
# 握持数学（双手皮肤点连线定位 + 枪身轴线对齐 + 跳跃/换弹分支）已抽离到 WeaponRig 节点；
# 标定常量来自 resources/weapon_rig_config.tres（WeaponRigConfig）。
# 本类仅保留上半身俯仰所需缓存：_weapon_skel / _weapon_bone_idx / _lhand_bone_idx。
var _weapon_rig: WeaponRig = null         # 武器握持子系统（_ready 中 new + setup）
var _fp_action: FPActionRetarget = null    # 第三人称刺刀/射击动作叠加系统
var _fp_vm: FPViewmodelPlayer = null       # 第一人称视图模型子系统（V 键切换）
var _fp_mode := false                      # 是否第一人称模式（false=第三人称）
var _fp_hold := false                      # 左键按住连发标志
var _weapon_skel: Skeleton3D = null       # 骨架缓存（上半身俯仰 + WeaponRig 共享）
var _weapon_bone_idx: int = -1            # RightHand 骨骼索引缓存（上半身俯仰用）
var _lhand_bone_idx: int = -1             # LeftHand 骨骼索引缓存（上半身俯仰用）
var _weapon_holder: Node3D = null         # 3P 世界枪节点（内嵌 Weapon_AK47；FP 下隐藏，避免抬头看到 3P 枪）
var _dynamic_world_model: Node3D = null    # 【P3 二期】由 WeaponDef.world_model 动态实例化的 3P 枪（角色未内嵌时）；可释放
# 上半身俯仰（相机俯仰驱动）
var _torso_bone_idx: int = -1                 # 腰部骨索引（上半身枢轴）
var _torso_parent_idx: int = -1               # 腰部骨父索引缓存（避免每帧 get_bone_parent）
var _skel_global: Transform3D = Transform3D.IDENTITY  # 每帧缓存的骨架全局变换（torso 块与 _bone_world 复用）
var _torso_pitch_smooth: float = 0.0          # 上半身俯仰平滑值（当前）
var _camera_ctrl: CameraController = null     # 相机控制器（读取 pitch 俯仰）
# 上半身随相机俯仰抬起/低下（仅动画层附加旋转，不影响逻辑/握持/斜率差）
# 枢轴=腰部骨(mixamorig_Spine)，旋转它=整条上半身链(脊/头/双臂)随之俯仰。
const TORSO_BONE := "mixamorig_Spine"       # 腰部节点（上半身划分枢轴）
const TORSO_PITCH_MAX := deg_to_rad(50.0)   # 上半身俯仰极限（±50°，站/蹲待机与移动时跟随相机；范围已扩大）
const TORSO_PITCH_FOLLOW := 1.0             # 跟随相机俯仰比例（1.0=等比跟随并夹紧到±极限）
const TORSO_PITCH_SPEED := 12.0             # 上半身俯仰平滑速度（1/s）
const TORSO_PITCH_SIGN := -1.0              # 俯仰方向符号（相机pitch为正时上半身抬起方向；若仍反向改回 1.0）
# 仅以下状态叠加上半身俯仰（站姿待机/行走/横移、蹲姿待机/移动）；
# 奔跑(RUN)、跳跃/换弹/受击/投掷/死亡/蹲倒/站蹲过渡等其它状态不叠加（奔跑用独立持枪姿态，不受相机俯仰干扰）。
const TORSO_PITCH_STATES: Array = [
	AnimState.IDLE_AIM,
	AnimState.WALK_FORWARD, AnimState.WALK_BACKWARD, AnimState.STRAFE_LEFT, AnimState.STRAFE_RIGHT,
	AnimState.CROUCH_IDLE_AIM,
	AnimState.CROUCH_WALK_FORWARD, AnimState.CROUCH_WALK_BACKWARD, AnimState.CROUCH_STRAFE_LEFT, AnimState.CROUCH_STRAFE_RIGHT,
	# 站蹲过渡也保持俯仰：低头/抬头时蹲下/起立不应先回正再跟随（用户反馈）
	AnimState.STAND_TO_CROUCH, AnimState.CROUCH_TO_STAND,
	# 尼泊尔挥刀也保留俯仰：挥刀瞬间头部不应强制回正（用户反馈）
	AnimState.NEPAL_ATTACK_LIGHT, AnimState.NEPAL_ATTACK_HEAVY,
]
var _switch_timer: float = 0.0             # 混合窗剩余时长
var _pending_switch_def: WeaponDef = null  # 蹲/站过渡中切武器 → 挂起等过渡播完（不跳过过渡动画）
var _switch_restore_pos: float = -1.0      # 切武器换装前记录的动画播放位置（重播后 seek 恢复，腿相位连续）
var _spatial_jumps: int = 0                # 空间跳变计数
var _spatial_jump_events: Array = []      # 跳变事件明细（仅 DEBUG_MODE 记录，限量 100 条）
var _auto_blend_boost: Dictionary = {}      # "from->to" -> 混合时长（运行时按跳变量自动上调）
var _switch_from_visual_y: float = 0.0     # 切换前视觉模型Y偏移（本地 position.y 基准，对准蹲下下沉信号）
var _prev_visual_y: float = 0.0            # 上一帧视觉模型Y（用于逐帧瞬时 delta）
var _prev_hand_pos: Vector3 = Vector3.ZERO  # 上一帧手部骨骼世界坐标（逐帧瞬时 delta）
var _switch_max_visual_y_delta: float = 0.0 # 混合窗内视觉Y每帧最大瞬时下沉量（蹲下跳变指标）

# ============================================================
# _ready()
# ============================================================
func _ready():
	# 【修复】记录出生点：复活时回到出生点，而非硬编码世界原点(0,0,0)
	# （多地图下出生点各不相同，硬编码原点会把玩家复活到悬空/卡地形）
	_spawn_point = global_position
	# 【P2 角色系统】自动发现 CharacterManager 并注入：
	# 有管理器 → 动画名走当前角色资产（anim_director）；无 → 回退 ANIM_NAMES 默认表（旧模式）。
	# 注意：_ready 阶段 get_tree().current_scene 可能为 null（场景未完全装载），
	# 因此从 root 递归查找 CharacterManager（挂在 Main 下）。
	var main_node: Node = get_tree().current_scene
	if main_node != null:
		char_manager = main_node.get_node_or_null("CharacterManager") as CharacterManager
	if char_manager == null:
		char_manager = get_tree().root.find_child("CharacterManager", true, false) as CharacterManager
	# 【P2 自愈】player_multichar.tscn 单独运行（无 main_multichar 的 CharacterManager 节点）时，
	# 自动创建一个挂到当前场景根，保证 Character 空挂载点能挂上角色 —— 否则 _ready 里
	# ActiveCharacter 缺失 → 回退 $Character/AnimationPlayer（空挂载点没有）→ 崩。
	if char_manager == null and main_node != null:
		var _auto_cm := CharacterManager.new()
		_auto_cm.name = "CharacterManager"
		main_node.add_child(_auto_cm)
		char_manager = _auto_cm
	if char_manager != null:
		anim_director = AnimationDirector.new()
		anim_director.bind(char_manager)
		# 【P3】武器系统：当前武器数据（WeaponDef）/握持配置/音效
		_weapon_system = WeaponSystem.new()
		add_child(_weapon_system)
		_weapon_system.bind(char_manager)
		# 【P2 修订】融合场景（player_multichar.tscn）下 Character 是空挂载点：
		# 确保 manager 已初始化（_ready 顺序不保证），再挂载当前角色视觉，
		# 并从挂载点重新解析 anim_player 引用。
		char_manager.ensure_ready()
		# 【P3】ensure_ready 后才激活首个角色 → 武器系统重新拉取当前武器
		if _weapon_system != null:
			_weapon_system.refresh()
		char_manager.mount_active_to(self)
		var active := $Character.get_node_or_null("ActiveCharacter")
		if active != null:
			character_visual = active as Node3D
			anim_player = active.find_child("AnimationPlayer", true, false) as AnimationPlayer
	# 【P2 修订】旧模式（无 CharacterManager）：player.tscn 内嵌角色，直接解析
	if anim_player == null:
		anim_player = $Character/AnimationPlayer
	if character_visual == null:
		character_visual = $Character
	# 初始化碰撞体
	var capsule = CapsuleShape3D.new()
	capsule.radius = _collision_radius()
	capsule.height = _standing_height()
	collision_shape.shape = capsule
	collision_shape.position.y = _standing_height() / 2.0
	
	# 连接 AnimationPlayer 的动画完成信号
	# 一次性动画播放完毕后触发状态切换
	# 【P2 修复】角色切换后 anim_player 会换成新角色的播放器，必须重连信号，
	# 否则新角色的动画播完无人监听（状态机卡死在过渡态）。
	_connect_anim_signals()
	# 【P4】AnimClip 扩展库挂载（融合模式初始挂载；切换时在 on_character_switched 重挂）
	if char_manager != null and char_manager.get_active_asset() != null and anim_player != null:
		var cur_asset: CharacterAsset = char_manager.get_active_asset()
		if cur_asset.extra_anim_lib != null:
			if anim_player.has_animation_library("clips"):
				anim_player.remove_animation_library("clips")
			anim_player.add_animation_library("clips", cur_asset.extra_anim_lib)
	
	# 预缓存动画 + 移除位置轨道 + 换弹回位尾巴 + 合成变体
	# 【P2 抽取】角色切换换库后必须重做（见 on_character_switched）
	_post_process_anim_library()
	# 【P3】能力注册（Ability 框架：示例 = 冲刺爆发 G 键）
	_register_abilities()
	
	# 启动默认待机动画
	_change_state(AnimState.IDLE_AIM)
	_play_animation(AnimState.IDLE_AIM, true, 1.0)

	_setup_weapon_and_fp()
	# 【硬依赖·时序】Player 必须在 AnimationPlayer(pri 0) 推进骨骼之后才驱动握持/俯仰，
	# 否则读到上一帧骨骼 → 枪/上半身滞后或脱手。请勿把本值调到 <=0 或把
	# AnimationPlayer/CameraController 的 process_priority 调到 >10。
	process_priority = PROCESS_PRIORITY
	# 【O1 时序保护·DEBUG 告警】若 AnimationPlayer 优先级 >= Player，骨骼会在本节点之前推进
	# → 握持/俯仰读到上一帧（脱手/滞后）。仅 DEBUG 下提醒，不影响发布构建。
	if DEBUG_MODE and anim_player != null and anim_player.process_priority >= PROCESS_PRIORITY:
		push_warning("时序硬依赖告警：AnimationPlayer.process_priority(%d) >= Player(%d)，请保持 AnimationPlayer 优先级更低" % [anim_player.process_priority, PROCESS_PRIORITY])

# ============================================================
# 【P2 角色热切换】由 CharacterSwitchController 调用。
# 切换后：更换 AnimationPlayer 的动画库（当前角色资产.anim_lib）、清空动画缓存、
# 重新进入待机。武器/FP 的重绑定为 P3 范围（WeaponSystem 搬移时一并做），
# 当前仅保证动画层跟随角色切换、且不崩溃（武器仍绑定原骨架，待 P3 完善）。
# ============================================================

## 【P3 换皮】重建第一人称视图模型：释放旧模型/播放器，按角色资产（或共享默认）
## 重新加载视图模型场景挂到相机下。切换角色且新旧 FP 场景不同时由
## on_character_switched 调用；两角色均未配专属场景（共享默认）时不会走到这里。
func _rebuild_fp_viewmodel(fp_scene: PackedScene) -> void:
	if _fp_vm != null:
		# 【P3 修复·切枪不打断枪声】正在播的射击音效播放器从旧 viewmodel 摘出，
		# 挂到 player 下继续播完（否则销毁 viewmodel 时播放器一起销毁 → 切枪瞬间
		# 枪声被掐断，M82 4.79s 长枪声尤其明显）。
		var _linger := _fp_vm.get_shoot_sfx_player()
		if _linger != null and _linger.playing:
			if _linger.get_parent() != null:
				_fp_vm.remove_child(_linger)
			_linger.name = "lingering_shoot_sfx"   # 便于定位/调试
			add_child(_linger)
			if not _linger.finished.is_connected(_linger.queue_free):
				_linger.finished.connect(_linger.queue_free)
		# 【P3 修复·两把 AK】立即释放（free 而非 queue_free）：queue_free 延迟一帧，
		# V/X 快速连续切换时旧 viewmodel 及其 _model（挂在相机下）尚未释放就重建新的
		# → 相机下堆积多个枪模型（画面出现两把 AK）。先摘父节点再 free，杜绝残留。
		# 【崩溃修复】free 必须在 player 的调用栈发起：dispose() 只清理模型资源，
		# 若在 dispose()（即 _fp_vm 自己的方法）内部 free 自身，对象处于锁定状态
		# → "Attempted to free a locked object (calling or emitting)" 崩溃
		# （切尼泊尔等带专属 FP 场景的武器必现）。
		_fp_vm.dispose()
		_fp_vm.free()
		_fp_vm = null
	_fp_vm = FPViewmodelPlayer.new()
	add_child(_fp_vm)
	if fp_scene != null and fp_scene.resource_path != "":
		_fp_vm.vm_scene_path = fp_scene.resource_path
	if _camera_ctrl != null and _camera_ctrl.camera != null:
		_fp_vm.setup(_camera_ctrl.camera)
	# 【手雷】FP 投掷开始 → 同步 3P 投掷动画（Toss Grenade；FP 下 3P 角色 SHADOWS_ONLY，影子投掷）
	if not _fp_vm.throw_started.is_connected(_on_fp_throw_started):
		_fp_vm.throw_started.connect(_on_fp_throw_started)
	# 重建后同步当前视角模式的显隐（FP 下可见 / 3P 下隐藏；FPViewmodelPlayer 用 set_visible 控制 _model）
	_fp_vm.set_visible(_fp_mode)
	debug_print("FP 视图模型已重建（场景=%s）" % _fp_vm.vm_scene_path)

## 【P3 多武器】把当前 WeaponDef 的行为数据应用到各武器子系统：
## 连发间隔(fire_rate) + 3P/FP 音效路径 + 可选 FP 视图模型场景/配置/换弹动画。
## 单武器(AK47)时各字段为空/默认 → 全部回退原硬编码常量，行为零变化；
## 加新武器只需填 WeaponDef 字段，无需改此处逻辑（数据驱动）。
func _apply_weapon_to_subsystems(def: WeaponDef) -> void:
	if def == null:
		return
	# 【切武器·保下半身相位】姿态换装（下方 _apply_*_stance）用 install 替换动画槽会
	# stop 正在播放的动画，_restart_stance_animation 重播会从头 → 走路/蹲走时腿相位
	# 跳变"卡一下"（用户实测：切武器瞬间打断下半身走路）。先记录播放位置，重播后 seek。
	if anim_player != null and anim_player.is_playing() and current_state != AnimState.IDLE_AIM:
		_switch_restore_pos = anim_player.current_animation_position
	else:
		_switch_restore_pos = -1.0
	# 直接读传入 WeaponDef 的字段（不依赖 _weapon_system.current_def，避免直接调用/守卫场景下读错武器）
	var fi: float = def.fire_rate if (def.fire_rate > 0.0) else 0.15
	var silent: bool = def.silent
	var fp_mirror: bool = def.fp_mirror
	# 【P3 静音】无专属音效的武器：传给子系统的音效路径清空（不加载/不借用其它武器音效），
	# 由 set_silent 兜底静音。AK47 音效已显式写入 ak47.tres；空路径 + 非 silent = 静音
	# （"宁可无声也不借用"，不再回退 AK47 路径）。
	var fire: String = "" if silent else def.fire_sfx
	var bay: String = "" if silent else def.bayonet_sfx
	var reload: String = "" if silent else def.reload_sfx
	var fp_scene: String = def.fp_viewmodel_scene if (def.fp_viewmodel_scene != "") else ""
	var fp_cfg: String = def.fp_viewmodel_cfg if (def.fp_viewmodel_cfg != "") else ""
	var fp_reload: String = def.fp_reload_anim if (def.fp_reload_anim != "") else ""
	var fp_anim_map: Dictionary = def.fp_anim_map if (def.fp_anim_map != null) else {}
	var fp_alt_shoot: String = def.fp_alt_shoot_anim
	if _fp_vm != null:
		if fp_scene != "":
			# 武器自带 FP 视图模型场景：与当前不同时才重建（避免重复实例化）
			if fp_scene != _fp_vm.vm_scene_path:
				var ps := load(fp_scene) as PackedScene
				if ps != null:
					_rebuild_fp_viewmodel(ps)
		else:
			# fp_viewmodel_scene 为空 = 回退默认 FP 视图模型（角色默认 ak47_viewmodel.gltf）。
			# 【P3 修复】此前空字段 = "不重建"，会导致切回 AK47（空字段）时停留在上一把武器的
			# 视图模型（如 M82A1）。现改为显式回退默认，使多武器循环切换两端都正确。
			# 单武器(AK47)时 _apply 仅在真实切换时调用（_wd.id != _applied_weapon_id），
			# 且无切换则不触发，行为零变化。
			if _fp_vm.vm_scene_path != FPViewmodelPlayer.VM_PATH:
				var ps := load(FPViewmodelPlayer.VM_PATH) as PackedScene
				if ps != null:
					_rebuild_fp_viewmodel(ps)
		# 【射速同步】注入必须在重建【之后】：重建会释放旧 vm，先注入会全部丢失
		# （实测：set_fire_mode 在重建前注入 → 新 vm 仍是默认 auto，单发压缩失效）。
		# set_sfx_paths 同理移出 else 分支：带专属模型的武器（M82 等）原先收不到
		# 音效路径，第一人称一直用 vm 默认的 AK47 音效。
		_fp_vm.set_fire_interval(fi)
		_fp_vm.set_fire_mode(def.fire_mode)
		_fp_vm.set_sfx_paths(fire, bay, reload)
		_fp_vm.set_config_paths(fp_cfg, fp_reload)
		# 【P3 多武器动画名映射】必须每次切枪注入（切回 AK47 时空字典=零变化），
		# 并在 set_config_paths 之后（内部会重建 preview 动画并回 idle）。
		_fp_vm.set_anim_map(fp_anim_map)
		# 【P3 近战交替】挥砍交替动画（尼泊尔 midslash1/midslash2），空=不交替。
		_fp_vm.set_alt_shoot_anim(fp_alt_shoot)
		# 【P3 静音/镜像】按武器注入：无专属音效则不发声；个别武器源就右手不镜像。
		_fp_vm.set_silent(silent)
		_fp_vm.set_mirror(fp_mirror)
		# 【P3 多武器 FOV】FP 模式下切枪：fov 必须跟随当前武器配置（预览场景调的 fov），
		# 否则只有切视角才更新 fov，FP 内切枪后画面缩放与预览不一致。
		if _fp_mode and _camera_ctrl != null:
			_camera_ctrl.camera.fov = _fp_vm.get_fov()
		# 【P3 多武器】FP 模式下切枪：播新武器的出枪动画（draw）。
		# 之前只在 V 键切入 FP 时 trigger_draw，按 X 切枪后 FP 模型直接 idle，
		# 没有"切出这把枪"的过渡动画 → 观感突兀。切枪时若正处 FP 且非换弹中，
		# 立即播 draw；换弹中则等换弹收尾（_finish_reload 会回 idle，不抢播）。
		if _fp_mode and not _is_reloading:
			_fp_vm.trigger_draw()
	if _fp_action != null:
		_fp_action.set_fire_interval(fi)
		_fp_action.set_fire_mode(def.fire_mode)   # 【两人称同步】单发包络时长=fire_rate
		_fp_action.set_sfx_paths(fire, bay)
		_fp_action.set_reload_sfx(reload)
		# 【P3 静音】3P 侧同步静音开关（不套用其它武器音效）
		_fp_action.set_silent(silent)
	_applied_weapon_id = def.id
	# 【3P 姿态覆盖】手枪/尼泊尔用「合成动画替换同名动画」实现，两者共用同一批
	# PISTOL_STANCE_STATES 动画槽，因此必须严格「先全部卸载，再安装目标」，
	# 避免手枪/尼泊尔互相把对方合成动画当原动画备份。
	var _want_pistol: bool = def.weapon_type == "pistol"
	var _want_nepal: bool = def.weapon_type == "knife"
	var _want_grenade: bool = def.weapon_type == "grenade"
	# 卸载本次不需要的姿态覆盖（含对方的），让动画槽回到原始步枪动画
	if not _want_nepal:
		_apply_nepal_stance(false)
	if not _want_pistol:
		_apply_pistol_stance(false)
	if not _want_grenade:
		_apply_grenade_stance(false)
	# 安装目标姿态（此时 _*_saved 备份到的必然是真原动画）
	if _want_pistol:
		_apply_pistol_stance(true)
	if _want_nepal:
		_apply_nepal_stance(true)
	if _want_grenade:
		_apply_grenade_stance(true)
	# 姿态换装必然打断当前播放，收尾统一恢复起播（详见函数注释）
	_restart_stance_animation()

## 【切枪定格修复·关键】姿态覆盖（手枪/尼泊尔）用「install 同名动画」替换动画槽，
## 而 AnimationCombiner.install 为避免 AnimationPlayer 内部 track 缓存引用悬空资源，
## 必须先 stop() 掉「正在播放的同名动画」。问题在于状态机 _play_looping 只在
## 「current_state 发生变化」时才调 _play_animation，同状态下只更新 speed_scale：
##   → 切枪后 AnimationPlayer 处于停止态，而状态没变，状态机永远不会自己重播
##   → 角色定格在被打断的那一帧（表现为"切到刀再切回枪就卡死/崩溃"）。
## 故姿态换装收尾必须显式补一次起播。只在「确实被停掉」时介入，不抢正常播放。
func _restart_stance_animation() -> void:
	if not is_instance_valid(anim_player):
		return
	if anim_player.is_playing():
		return   # 播放未被打断 → 无需干预
	# 死亡/过渡/一次性动画各有自己的播放与回调链，不抢播（避免打断换弹、受击等）
	if is_dead or is_transitioning or _is_in_one_shot_override:
		return
	var nm: String = _anim_name_for(current_state)
	if nm.is_empty() or not anim_player.has_animation(nm):
		# 当前状态动画不可用（例如刚从尼泊尔攻击态被切走）→ 退回对应姿势的待机
		current_state = AnimState.CROUCH_IDLE_AIM if is_crouching else AnimState.IDLE_AIM
		nm = _anim_name_for(current_state)
		if nm.is_empty() or not anim_player.has_animation(nm):
			return
	_play_animation(current_state, true, 1.0)
	# 【切武器·保下半身相位】换装前记录的播放位置 → seek 回去，腿相位连续不跳变
	# （合成动画下半身轨道与原动画一致，seek 同一时间点即无缝衔接）
	if _switch_restore_pos >= 0.0:
		var _restore: float = _switch_restore_pos
		_switch_restore_pos = -1.0
		if anim_player.has_animation(anim_player.current_animation):
			anim_player.seek(_restore, true)

## 手枪姿态切换：active=true → 把 PISTOL_STANCE_STATES 各状态合成
## 「手枪待机上半身 + 原动画下半身」并替换同名动画；false → 恢复原动画。
## 备份只在首次/角色切换后做一次（_pistol_saved 为空时），后续切枪复用。
func _apply_pistol_stance(active: bool) -> void:
	# 从当前武器 rig 配置读抬臂角（编辑器改 .tres → F6 生效；非手枪默认 0 不抬）
	_pistol_arm_lift_deg = PISTOL_ARM_LIFT_DEG_DEFAULT
	var _wd: WeaponDef = _weapon_system.get_current_weapon() if _weapon_system != null else null
	if _wd != null and _wd.weapon_rig_config != null:
		var _cfg_val: Variant = _wd.weapon_rig_config.get("arm_lift_deg")
		if _cfg_val is float:
			_pistol_arm_lift_deg = _cfg_val
	if not active:
		for st in _pistol_applied:
			if not _pistol_saved.has(st):
				continue
			var orig: Animation = _pistol_saved[st]
			var name: String = _anim_name_for(st)
			if name != "" and anim_player != null and anim_player.has_animation(name):
				AnimationCombiner.install(anim_player, name, orig)
				_anim_cache[st] = orig
		_pistol_saved.clear()
		_pistol_applied.clear()
		return
	if _pistol_upper == null:
		_pistol_upper = load(PISTOL_IDLE_ANIM_PATH) as Animation
	if _pistol_upper == null:
		push_warning("手枪姿态：无法加载 " + PISTOL_IDLE_ANIM_PATH)
		return
	# 首次（或角色切换清空后）：备份各状态原动画
	if _pistol_saved.is_empty():
		for st in PISTOL_STANCE_STATES:
			var orig: Animation = _get_cached_animation(st)
			if orig != null:
				_pistol_saved[st] = orig
	# 合成并替换（install 同名替换；_anim_cache 同步）
	for st in PISTOL_STANCE_STATES:
		if not _pistol_saved.has(st):
			continue
		var lower: Animation = _pistol_saved[st]
		var combined: Animation = _pistol_combine(lower)
		var name: String = _anim_name_for(st)
		if name != "" and anim_player != null and AnimationCombiner.install(anim_player, name, combined):
			_anim_cache[st] = combined
			if not _pistol_applied.has(st):
				_pistol_applied.append(st)
		else:
			push_warning("手枪姿态合成失败: state=%s name=%s" % [st, name])
	debug_print("[手枪姿态] 已合成 %d 个状态（双臂=手枪待机，其余=原动画）" % _pistol_applied.size())

## 手枪姿态合成（只裁剪双手）：
##  长度 = 原动画整周期（循环无缝，修 1s 接缝抖动）；
##  非手臂轨道（脊柱/头/腿）原样复制；手臂轨道用手枪待机循环铺满。
##  ⚠️ loop_mode 必须 LINEAR（循环）：待机/移动动画会一直播；若设 NONE，动画播完即停，
##  骨骼姿态冻结 → 俯仰叠加(_apply_torso_pitch_overlay)每帧在上一帧叠加残留上再叠加 →
##  每帧 23°+ 指数累积 = 上半身风火轮（3P 实测 40 帧累计 948°）。
func _pistol_combine(lower: Animation) -> Animation:
	var combined := Animation.new()
	combined.length = lower.length
	combined.loop_mode = Animation.LOOP_LINEAR
	# 1) 非手臂轨道：原动画原样（整周期，无缝）
	for i in lower.get_track_count():
		if AnimationCombiner.is_upper_body_track(str(lower.track_get_path(i)), ARMS_BONES):
			continue
		AnimationCombiner.copy_track(lower, i, combined, -1)
	# 2) 手臂轨道：手枪待机循环铺满（pistol 首尾一致 → 拼接无缝）；
	#    Shoulder 轨道左乘抬臂旋转（【与步枪同高度】绕 rest x 轴，肩骨位置不动=不耸肩；
	#    右肩 -deg、左肩 +deg 镜像）。角度由配置 arm_lift_deg 控制（编辑器可调，F6 生效）。
	for i in _pistol_upper.get_track_count():
		var sp := str(_pistol_upper.track_get_path(i))
		if not AnimationCombiner.is_upper_body_track(sp, ARMS_BONES):
			continue
		if _pistol_upper.track_get_type(i) != Animation.TYPE_ROTATION_3D:
			continue
		var _is_sh: bool = sp.contains("Shoulder")
		var _q_lift: Quaternion = Quaternion.IDENTITY
		if _is_sh and absf(_pistol_arm_lift_deg) > 0.01:
			# 左右肩 rest x 轴镜像（右肩≈世界+Z、左肩≈世界-Z），绕各自局部 x 的
			# 负方向=世界同方向抬臂 → sign 统一 -1（实测右肩-18抬、左肩+18反而降）。
			var _q_lift2: Quaternion = Quaternion(Vector3(1.0, 0.0, 0.0), deg_to_rad(-_pistol_arm_lift_deg))
			_q_lift = _q_lift2
		var _ni := combined.add_track(Animation.TYPE_ROTATION_3D)
		combined.track_set_path(_ni, _pistol_upper.track_get_path(i))
		# 循环铺满到 combined.length（pistol 首尾一致 → 无缝）
		var _plen: float = _pistol_upper.length
		var _kc: int = _pistol_upper.track_get_key_count(i)
		if _plen <= 0.001:
			continue   # 【修复】零长动画防 while 铺轨死循环（损坏资源保护）
		for _j in range(_kc):
			var _t: float = _pistol_upper.track_get_key_time(i, _j)
			var _v: Quaternion = _pistol_upper.track_get_key_value(i, _j)
			if _is_sh and _q_lift != Quaternion.IDENTITY:
				_v = _q_lift * _v
			var _t2: float = _t
			while _t2 <= combined.length + 0.001:
				combined.track_insert_key(_ni, _t2, _v)
				_t2 += _plen
		combined.track_set_interpolation_type(_ni, Animation.INTERPOLATION_LINEAR)
	return combined

# ============================================================
# 【尼泊尔 3P 接入】用户自制挥砍动画（桌面"新导出"轻击.fbx/重击.fbx，骨架名已改回 Armature）。
# 只替换手臂 8 骨（Shoulder/Arm/ForeArm/Hand），其余身体沿用步枪动画（呼吸/移动）。
# 待机 = 重击末帧持刀姿态（静态手臂）+ 原动画身体呼吸。
# 攻击 = 挥砍手臂 + 「挥刀那一刻的移动状态」身体（走→走循环/跑→跑循环/跳→跳，即选项B：
#        挥刀时腿继续走/跑/跳）。一次合成，不做每帧重装（避免 AnimationPlayer 缓存重建崩溃）。
# ============================================================
## 切到尼泊尔：把常驻状态合成「尼泊尔持刀手臂 + 原动画其余」；切走：恢复原动画。
func _apply_nepal_stance(active: bool) -> void:
	if not active:
		# 【崩溃防护】切走前先停掉尼泊尔攻击动画：install/remove_animation 若在动画
		# 播放中操作会让 AnimationPlayer 内部 track 缓存访问悬空指针 → 崩溃。
		if is_instance_valid(anim_player):
			var cur: String = anim_player.current_animation
			if cur == _anim_name_for(AnimState.NEPAL_ATTACK_LIGHT) \
					or cur == _anim_name_for(AnimState.NEPAL_ATTACK_HEAVY):
				_anim_op("STOP@1015_switch_weapon")
				anim_player.stop()
		if _is_in_one_shot_override and (current_state == AnimState.NEPAL_ATTACK_LIGHT \
				or current_state == AnimState.NEPAL_ATTACK_HEAVY):
			_is_in_one_shot_override = false
			current_state = AnimState.CROUCH_IDLE_AIM if is_crouching else AnimState.IDLE_AIM
		for st in _nepal_applied:
			if not _nepal_saved.has(st):
				continue
			var orig: Animation = _nepal_saved[st]
			var name: String = _anim_name_for(st)
			if name != "" and is_instance_valid(anim_player) and anim_player.has_animation(name):
				AnimationCombiner.install(anim_player, name, orig)
				_anim_cache[st] = orig
		_nepal_saved.clear()
		_nepal_applied.clear()
		return
	# 首次加载手臂动画资源（load 失败仅警告不崩溃）
	if _nepal_idle_arms == null:
		_nepal_idle_arms = load(NEPAL_IDLE_ARMS_PATH) as Animation
	if _nepal_idle_arms == null:
		push_warning("尼泊尔姿态：无法加载 " + NEPAL_IDLE_ARMS_PATH)
		return
	if _nepal_light_arms == null:
		_nepal_light_arms = load(NEPAL_LIGHT_ARMS_PATH) as Animation
	if _nepal_heavy_arms == null:
		_nepal_heavy_arms = load(NEPAL_HEAVY_ARMS_PATH) as Animation
	# 备份各常驻状态原动画（仅首次/角色切换后）
	if _nepal_saved.is_empty():
		for st in NEPAL_STANCE_STATES:
			var orig: Animation = _get_cached_animation(st)
			if orig != null:
				_nepal_saved[st] = orig
	# 合成并替换（手臂 = 待机持刀，循环铺满；其余 = 原动画）
	for st in NEPAL_STANCE_STATES:
		if not _nepal_saved.has(st):
			continue
		var lower: Animation = _nepal_saved[st]
		var combined: Animation = _nepal_combine(lower, st)
		var name: String = _anim_name_for(st)
		if name != "" and anim_player != null and AnimationCombiner.install(anim_player, name, combined):
			_anim_cache[st] = combined
			if not _nepal_applied.has(st):
				_nepal_applied.append(st)
	debug_print("[尼泊尔姿态] 已合成 %d 个常驻状态（手臂=重击末帧持刀，其余=原动画）" % _nepal_applied.size())

## 尼泊尔待机合成：非手臂轨道=原动画原样（整周期无缝，跳过 position），
## 手臂 8 骨=重击末帧持刀姿态循环铺满（静态姿态 → 身体呼吸带动手臂跟随）。
func _nepal_combine(lower: Animation, state: int = -1) -> Animation:
	var combined := Animation.new()
	combined.length = lower.length
	# 【挥刀兼容·防卡死】循环状态（待机/走/跑/蹲走）保持 LOOP_LINEAR；一次性状态
	# （站蹲过渡/跳跃）必须 LOOP_NONE，否则合成动画循环播放 → animation_finished
	# 永不触发 → 过渡/落地状态永不完成（持刀点按蹲"自动起立失效"、持刀跳跃下落
	# 卡顿/多次落地）。_play_animation 播放时会重设 loop_mode，这里兜底其它直接
	# play 的路径（如 _nepal_maybe_follow_lower 重合成后 anim_player.play）。
	combined.loop_mode = Animation.LOOP_LINEAR
	if state in _LOOP_NONE_STATES:
		combined.loop_mode = Animation.LOOP_NONE
	# 【蹲/跳过渡·position 必须保留】循环动画跳过 position 轨道（Mixamo 循环 Hips
	# position 是错误坐标系 → 双重下压陷地）；但站蹲过渡/跳跃是【一次性】动画，其
	# Hips position 是身体真实下沉/升起的关键（持刀合成版若跳过 → 过渡期间身体不
	# 下沉、只有腿弯曲 = "腿部弹起蹲姿浮空"；自动起立时身体也不回升）。
	var _keep_pos: bool = state in _LOOP_NONE_STATES
	# 【修改·站蹲过渡也替换手臂】用户反馈"持刀蹲下/起立过程中手臂仍是 AK 持枪姿势"。
	# 原设计过渡期保留原动画手臂（08-24 曾因静态手臂+蹲身体出现"悬空"观感而妥协），
	# 现与手枪合成(_pistol_combine)对齐：所有状态一律替换为持刀手臂——手枪同机制
	# 无观感问题，且持刀手臂全程静态，过渡前后姿态天然连续，蹲定后不再有姿态跳变。
	for i in lower.get_track_count():
		if AnimationCombiner.is_upper_body_track(str(lower.track_get_path(i)), ARMS_BONES):
			continue
		if lower.track_get_type(i) == Animation.TYPE_POSITION_3D and not _keep_pos:
			continue
		AnimationCombiner.copy_track(lower, i, combined, -1)
	# 手臂轨道：待机持刀姿态循环铺满；Shoulder 左乘抬臂旋转（与手枪一致，
	# sign 统一 -1，绕 rest x 轴抬升），让持刀手臂整体抬高而非肩骨位置位移。
	var _q_lift := Quaternion.IDENTITY
	if absf(NEPAL_ARM_LIFT_DEG) > 0.01:
		_q_lift = Quaternion(Vector3(1.0, 0.0, 0.0), deg_to_rad(-NEPAL_ARM_LIFT_DEG))
	for i in _nepal_idle_arms.get_track_count():
		var sp := str(_nepal_idle_arms.track_get_path(i))
		if not AnimationCombiner.is_upper_body_track(sp, ARMS_BONES):
			continue
		if _nepal_idle_arms.track_get_type(i) != Animation.TYPE_ROTATION_3D:
			continue
		var _is_sh: bool = sp.contains("Shoulder")
		var _plen: float = _nepal_idle_arms.length
		var _kc: int = _nepal_idle_arms.track_get_key_count(i)
		if _plen <= 0.001:
			continue   # 【修复】零长动画防 while 铺轨死循环（损坏资源保护）
		var _ni := combined.add_track(Animation.TYPE_ROTATION_3D)
		combined.track_set_path(_ni, _nepal_idle_arms.track_get_path(i))
		for _j in range(_kc):
			var _t: float = _nepal_idle_arms.track_get_key_time(i, _j)
			var _v: Quaternion = _nepal_idle_arms.track_get_key_value(i, _j)
			if _is_sh:
				_v = _q_lift * _v
			var _t2: float = _t
			while _t2 <= combined.length + 0.001:
				combined.track_insert_key(_ni, _t2, _v)
				_t2 += _plen
		combined.track_set_interpolation_type(_ni, Animation.INTERPOLATION_LINEAR)
	return combined

## 启动尼泊尔挥砍（方案C·分层叠加）：只记录直驱会话，不烤动画、不进独占状态。
## 下半身由状态机照常驱动（走/跑/蹲/跳过渡天然生效）；手臂 8 骨由 _drive_nepal_arms 每帧采样直驱。
func _start_nepal_attack(state: AnimState) -> void:
	_nepal_attacking = true
	_nepal_atk_elapsed = 0.0
	_nepal_atk_arms = _nepal_light_arms if state == AnimState.NEPAL_ATTACK_LIGHT else _nepal_heavy_arms
	_nepal_atk_track_bones.clear()   # 新会话新资源：轨道映射缓存作废
	if _nepal_atk_arms == null:
		# 资源未加载（切刀瞬间挥刀等边界）→ 按路径加载一次，仍失败则放弃挥砍
		var _p := NEPAL_LIGHT_ARMS_PATH if state == AnimState.NEPAL_ATTACK_LIGHT else NEPAL_HEAVY_ARMS_PATH
		_nepal_atk_arms = load(_p) as Animation
	if _nepal_atk_arms == null:
		_nepal_attacking = false
		return
	# 记录挥刀起手（保留日志/调试语义）
	_nepal_atk_start_ms = Time.get_ticks_msec()
	_nepal_last_follow_ms = -1
	if NEPAL_LOG:
		print("[NEPAL] 挥刀起手(方案C直驱) %s: crouch=%s run=%s on_floor=%s" % [
			"轻击" if state == AnimState.NEPAL_ATTACK_LIGHT else "重击",
			str(is_crouching), str(is_running), str(_is_on_floor())])

## 挥砍手臂直驱（方案C·分层叠加）：挥砍会话期间每帧采样挥砍资源的 8 骨 local rotation，
## 用 set_bone_pose_rotation 覆盖 AP 播放的下半身动画的手臂轨道（与 _apply_torso_pitch_overlay
## 同机制，晚于 AnimationPlayer pri=0 执行）。时间轴到点自动结束会话，手臂自动回持刀待机。
func _drive_nepal_arms(delta: float) -> void:
	if not _nepal_attacking or _nepal_atk_arms == null:
		return
	if _weapon_skel == null:
		return
	_nepal_atk_elapsed += delta
	var t: float = minf(_nepal_atk_elapsed, _nepal_atk_arms.length)
	# 【性能】轨道→骨骼索引映射在会话内不变，首帧构建缓存。
	# 原先每帧对每条轨道做字符串切割 + O(骨骼数) find_bone 线性查找。
	if _nepal_atk_track_bones.is_empty():
		for track in range(_nepal_atk_arms.get_track_count()):
			if _nepal_atk_arms.track_get_type(track) != Animation.TYPE_ROTATION_3D:
				continue
			var p := String(_nepal_atk_arms.track_get_path(track))
			var colon := p.rfind(":")
			if colon < 0:
				continue
			var bidx := _weapon_skel.find_bone(p.substr(colon + 1))
			if bidx >= 0:
				_nepal_atk_track_bones[track] = bidx
	for track in _nepal_atk_track_bones:
		var rot: Variant = _sample_anim_track(_nepal_atk_arms, track, t)
		if rot != null:
			_weapon_skel.set_bone_pose_rotation(_nepal_atk_track_bones[track], rot as Quaternion)
	if _nepal_atk_elapsed >= _nepal_atk_arms.length:
		# 挥砍自然结束：清直驱会话。AP 下一帧重新写回持刀待机手臂（_apply_nepal_stance
		# 合成的常驻手臂），手臂自动复位，无需手动恢复。
		_nepal_attacking = false
		_nepal_atk_arms = null
		_nepal_atk_elapsed = 0.0
		_nepal_atk_track_bones.clear()

# ==================== 手雷 3P 手臂（Toss Grenade 裁剪版，方案C 直驱） ====================

## 当前武器是否为手雷（gaobao 槽位 4）。
func _is_grenade_weapon() -> bool:
	return _weapon_system != null and _weapon_system.get_current_weapon() != null \
			and _weapon_system.get_current_weapon().weapon_type == "grenade"

## 锁定头部（Neck/Head）姿态：记录会话开始时的低头姿态，期间每帧写回
## （消除蹲左走动画头部摆动的"磕头"；俯仰仍有效因为 Spine 旋转带动头部）。
## ⚠️【Neck/Head 必须分开锁】旧实现只记录 Neck 姿态却把它同时写给 Head——
## 待机动画里 Head 自带旋转（如 r=(-6,22,9)）≠ Neck（r=(5,8,2)），
## 拉环锁定的瞬间 Head 被强制扭成 Neck 姿态 → "头部咯噔偏一下"（用户实测观感问题）。
func _lock_grenade_head() -> void:
	if _weapon_skel == null or _grenade_head_locked:
		return
	if _grenade_neck_idx < 0:
		_grenade_neck_idx = _weapon_skel.find_bone("mixamorig_Neck")
		_grenade_head_idx = _weapon_skel.find_bone("mixamorig_Head")
	if _grenade_neck_idx >= 0:
		_grenade_neck_lock = _weapon_skel.get_bone_pose_rotation(_grenade_neck_idx)
	if _grenade_head_idx >= 0:
		_grenade_head_lock = _weapon_skel.get_bone_pose_rotation(_grenade_head_idx)
	_grenade_head_locked = true

## 启动拉环会话（左键按下）。幂等：投掷中不响应。
func _start_grenade_pull() -> void:
	if _grenade_throwing:
		return
	_grenade_pulling = true
	_grenade_holding = false
	_grenade_elapsed = 0.0
	_grenade_track_bones.clear()
	_grenade_track_res = null
	_lock_grenade_head()
	# 【WeaponRig 竞争】手雷有专属 rig(skip_follow=false)，WeaponRig 每帧按握把接管手部
	# 骨骼 → 与拉环直驱竞争 → 蹲走等移动中上半身抖动（用户实测）。拉环/投掷期间停握持。
	if _weapon_rig != null:
		_weapon_rig.skip_follow = true
	_grenade_arms = _grenade_pull_arms
	if _grenade_arms == null:
		_grenade_arms = load(GRENADE_PULL_ARMS_PATH) as Animation
		_grenade_pull_arms = _grenade_arms
	if _grenade_arms == null:
		push_warning("手雷：无法加载 " + GRENADE_PULL_ARMS_PATH)
		_grenade_pulling = false

## 启动投掷会话（持环等待中松开 / 点按拉环播完自动 / FP throw_started 信号）。幂等。
func _start_grenade_throw() -> void:
	if _grenade_throwing:
		return
	_grenade_pulling = false
	_grenade_holding = false
	_grenade_throwing = true
	_grenade_elapsed = 0.0
	_grenade_track_bones.clear()
	_grenade_track_res = null
	_lock_grenade_head()
	if _weapon_rig != null:
		_weapon_rig.skip_follow = true   # 同拉环：投掷期间停 WeaponRig 握持
	_grenade_arms = _grenade_throw_arms
	if _grenade_arms == null:
		_grenade_arms = load(GRENADE_THROW_ARMS_PATH) as Animation
		_grenade_throw_arms = _grenade_arms
	if _grenade_arms == null:
		push_warning("手雷：无法加载 " + GRENADE_THROW_ARMS_PATH)
		_grenade_throwing = false

## 清全部手雷直驱会话（切武器/死亡/复位时调用）。手臂交回持雷待机合成。
func _stop_grenade_arms() -> void:
	_grenade_held = false
	_grenade_holding = false
	_grenade_pulling = false
	_grenade_throwing = false
	_grenade_arms = null
	_grenade_elapsed = 0.0
	_grenade_track_bones.clear()
	_grenade_track_res = null
	_grenade_tail_t = 0.0
	_grenade_head_locked = false   # 释放头部锁定（蹲走头部摆动交回动画）
	# 【手雷挂右手骨骼后】WeaponRig 不再需要（skip_follow 由换装 2167 统一设为 true，
	# 全程让路——手雷模型跟骨骼动画走，不再恢复 false 以免 WeaponRig 抢回手部）

## 8 骨采样写入（按归一化进度 0..1）。轨道→骨骼映射缓存按资源区分，换资源自动重建。
func _sample_grenade_arms(res: Animation, t01: float) -> void:
	if res == null or _weapon_skel == null:
		return
	if _grenade_track_res != res or _grenade_track_bones.is_empty():
		_grenade_track_bones.clear()
		for track in range(res.get_track_count()):
			if res.track_get_type(track) != Animation.TYPE_ROTATION_3D:
				continue
			var p := String(res.track_get_path(track))
			var colon := p.rfind(":")
			if colon < 0:
				continue
			var bidx := _weapon_skel.find_bone(p.substr(colon + 1))
			if bidx >= 0:
				_grenade_track_bones[track] = bidx
		_grenade_track_res = res
	var t: float = clampf(t01, 0.0, 1.0) * res.length
	for track in _grenade_track_bones:
		var rot: Variant = _sample_anim_track(res, track, t)
		if rot != null:
			_weapon_skel.set_bone_pose_rotation(_grenade_track_bones[track], rot as Quaternion)

## 持环等待：手臂钉在拉环【末帧】（=拉环 37 帧加速后末帧，FP 的 plugin 播完 pause 同语义）。
func _drive_grenade_hold() -> void:
	if _grenade_pull_arms == null:
		_grenade_pull_arms = load(GRENADE_PULL_ARMS_PATH) as Animation
	_sample_grenade_arms(_grenade_pull_arms, 1.0)

## 骨骼坐标日志（v2 详细版）：14 骨全局位置+局部旋转欧拉 + 各系统状态，每帧 print + 写文件
func _grenade_log_coords() -> void:
	if _weapon_skel == null:
		return
	var an := ""
	var ap := 0.0
	var al := 0.0
	var playing := "-"
	var spd := 0.0
	if anim_player != null:
		an = String(anim_player.current_animation)
		ap = anim_player.current_animation_position
		al = anim_player.current_animation_length
		spd = anim_player.speed_scale
		playing = str(anim_player.is_playing())
	# dpos：本帧动画进度增量（正常 ≈ delta；跳变帧会显示 +0.4x —— 动画被快进/seek）
	var dpos := 0.0
	if _prev_log_anim == an and _prev_log_pos >= 0.0:
		dpos = ap - _prev_log_pos
	else:
		dpos = -1.0   # 动画切换帧，无法算增量
	_prev_log_pos = ap
	_prev_log_anim = an
	var fph := ""
	var fpt := 0.0
	if _fp_vm != null and _fp_vm.has_method("get_grenade_phase"):
		var ph: Dictionary = _fp_vm.get_grenade_phase()
		fph = String(ph.get("phase", ""))
		fpt = float(ph.get("t", 0.0))
	var skip := "-"
	if _weapon_rig != null:
		skip = str(_weapon_rig.skip_follow)
	# 最近一次动画操作 + 距今帧数
	var op_dist := -1
	if _anim_op_frame >= 0:
		op_dist = Engine.get_process_frames() - _anim_op_frame
	var op_s := "-"
	if _anim_op_tag != "":
		op_s = "%s(+%d帧)" % [_anim_op_tag, op_dist]
	var s := "[GRENADE] f=%d anim=%s pos=%.3f/%.3f dpos=%+.3f speed=%.3f playing=%s op=%s install=%d fp=%s/%.2f state=%s pitch=%.1f torso=%.1f hlock=%s pull=%s hold=%s throw=%s tail=%.3f skip=%s" % [
		Engine.get_process_frames(), an, ap, al, dpos, spd, playing, op_s, _stance_install_seq,
		fph, fpt, _anim_name_for(current_state),
		rad_to_deg(_camera_ctrl.pitch if _camera_ctrl != null else 0.0),
		rad_to_deg(_torso_pitch_smooth),
		str(_grenade_head_locked),
		str(_grenade_pulling), str(_grenade_holding), str(_grenade_throwing),
		_grenade_tail_t, skip]
	var bones := ["mixamorig_Hips", "mixamorig_Spine", "mixamorig_Spine1",
			"mixamorig_Spine2", "mixamorig_Neck", "mixamorig_Head",
			"mixamorig_LeftShoulder", "mixamorig_LeftArm", "mixamorig_LeftForeArm", "mixamorig_LeftHand",
			"mixamorig_RightShoulder", "mixamorig_RightArm", "mixamorig_RightForeArm", "mixamorig_RightHand"]
	for b in bones:
		var idx := _weapon_skel.find_bone(b)
		if idx >= 0:
			var p: Vector3 = _weapon_skel.get_bone_global_pose(idx).origin
			var r: Vector3 = _weapon_skel.get_bone_pose_rotation(idx).get_euler()
			s += " %s:p(%.1f,%.1f,%.1f)r(%.0f,%.0f,%.0f)" % [
				b.replace("mixamorig_", ""), p.x, p.y, p.z,
				rad_to_deg(r.x), rad_to_deg(r.y), rad_to_deg(r.z)]
	print(s)
	var f := FileAccess.open(GRENADE_LOG_PATH, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(GRENADE_LOG_PATH, FileAccess.WRITE)
	if f != null:
		f.seek_end()
		f.store_line(s)
		f.close()

## 手雷手臂直驱主循环（渲染帧调用）。
## 【FP 统一时钟】FP 模式下 3P 影子逐帧跟随 FP 视图模型动画进度（get_grenade_phase）：
##   拉环 t = BLEND_LEAD + fp_t01×FP_PULL_DUR（过渡在 FP 拉环开始前完成，动作段逐帧对齐）
##   投掷 t = fp_t01×FP_THROW_DUR（动作段对齐；尾部过渡在 FP 回 idle 后由清会话处理）
## 【3P 本地时钟】3P 视角无 FP 动画可跟随，用本地时间轴播完整（含首尾过渡）。
func _drive_grenade_arms(delta: float) -> void:
	if _weapon_skel == null:
		return
	# 【头部锁定】每帧写回会话开始时的 Neck/Head 姿态（各锁各的，勿互相覆盖；
	# 俯仰仍生效——pitch overlay 旋转 Spine，头部随父链低头）
	if _grenade_head_locked:
		if _grenade_neck_idx >= 0:
			_weapon_skel.set_bone_pose_rotation(_grenade_neck_idx, _grenade_neck_lock)
		if _grenade_head_idx >= 0:
			_weapon_skel.set_bone_pose_rotation(_grenade_head_idx, _grenade_head_lock)
	if GRENADE_DEBUG_LOG and _is_grenade_weapon():
		_grenade_log_frame += 1
		_grenade_log_coords()   # 每帧全量（用户要求详细，定位 1s 一次的"磕头"）
	if _fp_mode and _fp_vm != null and _fp_vm.has_method("get_grenade_phase"):
		var ph: Dictionary = _fp_vm.get_grenade_phase()
		match String(ph.get("phase", "")):
			"pull":
				if _grenade_pull_arms == null:
					_grenade_pull_arms = load(GRENADE_PULL_ARMS_PATH) as Animation
				_grenade_holding = false
				_grenade_throwing = false
				# 拉环 = 2 关键帧（待机→拉环末帧），时长=FP_PULL_DUR，进度 1:1 对齐 FP
				var tt: float = float(ph.get("t", 0.0)) * GRENADE_FP_PULL_DUR
				_sample_grenade_arms(_grenade_pull_arms, tt / maxf(_grenade_pull_arms.length, 0.001))
			"hold":
				_grenade_holding = true
				_grenade_throwing = false
				_drive_grenade_hold()
			"throw":
				if _grenade_throw_arms == null:
					_grenade_throw_arms = load(GRENADE_THROW_ARMS_PATH) as Animation
				_grenade_holding = false
				var action_end: float = GRENADE_THROW_LEAD + GRENADE_FP_THROW_DUR
				var tt2: float
				var t01 := float(ph.get("t", 0.0))
				if t01 < 1.0:
					tt2 = GRENADE_THROW_LEAD + t01 * GRENADE_FP_THROW_DUR
				else:
					# FP Throw 已播完 → 3P 继续播尾过渡（0.12s 回持雷），播完清会话
					_grenade_tail_t += delta
					tt2 = action_end + _grenade_tail_t
					if tt2 >= _grenade_throw_arms.length:
						_stop_grenade_arms()
						return
				_sample_grenade_arms(_grenade_throw_arms, tt2 / maxf(_grenade_throw_arms.length, 0.001))
			_:
				# FP 已回待机：若投掷尾过渡未播完则继续播，否则清会话回持雷待机合成
				if _grenade_throwing and _grenade_tail_t > 0.0 \
						and _grenade_tail_t < _grenade_throw_arms.length - (GRENADE_THROW_LEAD + GRENADE_FP_THROW_DUR):
					_grenade_tail_t += delta
					var tt3: float = GRENADE_THROW_LEAD + GRENADE_FP_THROW_DUR + _grenade_tail_t
					if tt3 >= _grenade_throw_arms.length:
						_stop_grenade_arms()
					else:
						_sample_grenade_arms(_grenade_throw_arms, tt3 / maxf(_grenade_throw_arms.length, 0.001))
				elif _grenade_pulling or _grenade_throwing or _grenade_holding:
					_stop_grenade_arms()
		return
	# ---- 3P 模式：本地时间轴 ----
	if _grenade_holding:
		_drive_grenade_hold()
		return
	if _grenade_arms == null or not (_grenade_pulling or _grenade_throwing):
		return
	_grenade_elapsed += delta
	_sample_grenade_arms(_grenade_arms,
			_grenade_elapsed / maxf(_grenade_arms.length, 0.001))
	if _grenade_elapsed >= _grenade_arms.length:
		if _grenade_pulling:
			# 拉环播完（含过渡+动作）：按住 → 持环等待（停末帧）；已松开 → 自动投掷
			_grenade_pulling = false
			_grenade_arms = null
			if _grenade_held:
				_grenade_holding = true
				_drive_grenade_hold()
			else:
				_start_grenade_throw()
		elif _grenade_throwing:
			# 投掷播完（含回待机过渡）：清会话，AP 下一帧写回持雷待机合成
			_stop_grenade_arms()

## 持雷待机合成（active=true 安装 / false 恢复）。镜像 _apply_nepal_stance，
## 手臂来源 = grenade_hold（= 尼泊尔手臂姿势，用户 2026-09-01 决策）。
func _apply_grenade_stance(active: bool) -> void:
	if not active:
		for st in _grenade_saved:
			var orig: Animation = _grenade_saved[st]
			var name: String = _anim_name_for(st)
			if name != "" and is_instance_valid(anim_player) and anim_player.has_animation(name):
				AnimationCombiner.install(anim_player, name, orig)
				_anim_cache[st] = orig
		_grenade_saved.clear()
		_grenade_applied.clear()
		return
	if _grenade_hold_arms == null:
		_grenade_hold_arms = load(GRENADE_HOLD_ARMS_PATH) as Animation
	if _grenade_hold_arms == null:
		push_warning("手雷姿态：无法加载 " + GRENADE_HOLD_ARMS_PATH)
		return
	if _grenade_saved.is_empty():
		for st in GRENADE_STANCE_STATES:
			var orig: Animation = _get_cached_animation(st)
			if orig != null:
				_grenade_saved[st] = orig
	for st in GRENADE_STANCE_STATES:
		if not _grenade_saved.has(st):
			continue
		var lower: Animation = _grenade_saved[st]
		var combined: Animation = _grenade_combine(lower, st)
		var name: String = _anim_name_for(st)
		if name != "" and anim_player != null and AnimationCombiner.install(anim_player, name, combined):
			_anim_cache[st] = combined
			if not _grenade_applied.has(st):
				_grenade_applied.append(st)
			_stance_install_seq += 1
	debug_print("[手雷姿态] 已合成 %d 个常驻状态（手臂=尼泊尔姿态）" % _grenade_applied.size())

## 持雷待机合成：非手臂轨道=原动画原样（整周期无缝），手臂 8 骨=hold（尼泊尔姿态）铺满。
## 站蹲过渡/跳跃保持 LOOP_NONE + position 轨道（与 _nepal_combine 同一套防卡死纪律）。
func _grenade_combine(lower: Animation, state: int = -1) -> Animation:
	var combined := Animation.new()
	combined.length = lower.length
	combined.loop_mode = Animation.LOOP_LINEAR
	if state in _LOOP_NONE_STATES:
		combined.loop_mode = Animation.LOOP_NONE
	var _keep_pos: bool = state in _LOOP_NONE_STATES
	for i in lower.get_track_count():
		if AnimationCombiner.is_upper_body_track(str(lower.track_get_path(i)), ARMS_BONES):
			continue
		if lower.track_get_type(i) == Animation.TYPE_POSITION_3D and not _keep_pos:
			continue
		AnimationCombiner.copy_track(lower, i, combined, -1)
	if _grenade_hold_arms != null:
		# 【抬臂已烘焙进 tres】（grenade_toss_kit.gd _apply_lift 22°），运行时直接用原值，
		# 待机合成与直驱同一份数据 → 无切换跳变
		for i in _grenade_hold_arms.get_track_count():
			if _grenade_hold_arms.track_get_type(i) != Animation.TYPE_ROTATION_3D:
				continue
			var sp := str(_grenade_hold_arms.track_get_path(i))
			if not AnimationCombiner.is_upper_body_track(sp, ARMS_BONES):
				continue
			var _v: Quaternion = _grenade_hold_arms.track_get_key_value(i, 0)
			var _ni := combined.add_track(Animation.TYPE_ROTATION_3D)
			combined.track_set_path(_ni, _grenade_hold_arms.track_get_path(i))
			combined.track_insert_key(_ni, 0.0, _v)
			if combined.length > 0.001:
				combined.track_insert_key(_ni, combined.length, _v)
			combined.track_set_interpolation_type(_ni, Animation.INTERPOLATION_LINEAR)
	return combined

## 安装一次性攻击动画：手臂 8 骨=挥砍 clip，其余全部沿用 base_state 原动画。
## base_state = 挥刀那一刻的实际状态（走/跑/跳/蹲），因此移动中挥刀下半身照常运动
## （选项B：腿继续走/跑/跳，只有手臂挥砍）。播放时长=用户动画原时长（轻击0.633s/重击1.5s）。
## base_override >= 0 时强制指定下半身状态（挥刀期间移动状态变化 → 动态跟随重合成）。
func _install_nepal_attack(state: AnimState, arms: Animation, base_override: int = -1) -> void:
	if arms == null:
		return
	var base_state: AnimState = _state_before_one_shot
	if base_override >= 0:
		base_state = base_override
	if base_state == AnimState.NEPAL_ATTACK_LIGHT or base_state == AnimState.NEPAL_ATTACK_HEAVY:
		base_state = AnimState.IDLE_AIM
	_nepal_atk_lower = base_state
	var lower: Animation = _get_cached_animation(base_state)
	if lower == null:
		lower = _get_cached_animation(AnimState.IDLE_AIM)
	if lower == null:
		return
	var combined := Animation.new()
	combined.length = arms.length
	combined.loop_mode = Animation.LOOP_NONE
	# 【修复】下半身按挥刀那一刻的移动倍率压缩时间：正常移动时腿部动画会随速度调速
	# （走路~1.5x / 跑步~1.5x），挥刀合成动画播速固定 1.0，若不压缩则腿步频与物理速度
	# 不匹配 → 观感减速/卡顿。压缩后攻击时长不变、腿节奏与正常移动一致。
	var lower_speed: float = _nepal_lower_speed_ratio()
	# 非手臂轨道（Hips/腿/脚/脊柱/头）：base_state 原动画循环铺满攻击时长；跳过 position
	for i in lower.get_track_count():
		if AnimationCombiner.is_upper_body_track(str(lower.track_get_path(i)), ARMS_BONES):
			continue
		if lower.track_get_type(i) == Animation.TYPE_POSITION_3D:
			continue
		_fill_lower_track_compressed(lower, i, combined, combined.length, lower_speed)
	# 手臂 8 骨：挥砍动画（本身覆盖全时长）
	for i in arms.get_track_count():
		var sp := str(arms.track_get_path(i))
		if not AnimationCombiner.is_upper_body_track(sp, ARMS_BONES):
			continue
		if arms.track_get_type(i) != Animation.TYPE_ROTATION_3D:
			continue
		AnimationCombiner.copy_track(arms, i, combined, -1)
	var atk_name: String = _anim_name_for(state)
	if anim_player != null and is_instance_valid(anim_player):
		# 【崩溃防护】install 内部会 remove_animation：若该动画正在播（连击重合成）
		# 会让 playback 引用悬空 → 先停播，随后 _play_animation 会重新起播。
		if anim_player.current_animation == atk_name:
			_anim_op("STOP@1529_nepal_recombine")
			anim_player.stop()
		AnimationCombiner.install(anim_player, atk_name, combined)
		_stance_install_seq += 1

## 挥刀那一刻下半身应有的动画速度倍率（与正常移动 _get_normalized_anim_speed / run 调速一致）。
func _nepal_lower_speed_ratio() -> float:
	var spd: float = Vector2(velocity.x, velocity.z).length()
	var mult: float = _ability_speed_mult
	var bs: AnimState = _state_before_one_shot
	if bs == AnimState.RUN:
		return clamp(spd / DESIGN_RUN_SPEED, 0.5, 1.5 * mult)
	if bs == AnimState.CROUCH_WALK_FORWARD or bs == AnimState.CROUCH_WALK_BACKWARD \
			or bs == AnimState.CROUCH_STRAFE_LEFT or bs == AnimState.CROUCH_STRAFE_RIGHT:
		# 【修复】蹲走用蹲速基准（MAX_CROUCH_SPEED），否则 spd/5.0≈0.44 把腿压成慢动作
		# 【挥刀兼容】蹲走挥刀起手帧 velocity 尚未满速（spd≈0）→ ratio 被压到 0.3 → 腿步频骤降
		# （观感"蹲下移动时挥刀速度变慢"）。用输入意图速度兜底：移动键已按下即按 60% 满速算。
		var anim := _get_cached_animation(bs)
		var _intent_crouch: float = MAX_CROUCH_SPEED * 0.6 if input_dir.length() > 0.1 else 0.0
		var ratio: float = clamp(maxf(spd, _intent_crouch) / MAX_CROUCH_SPEED, 0.3, 1.5 * mult)
		if anim != null and anim.length > 0.01:
			ratio *= anim.length / REFERENCE_WALK_ANIM_LEN
		return ratio
	if bs == AnimState.WALK_FORWARD or bs == AnimState.WALK_BACKWARD \
			or bs == AnimState.STRAFE_LEFT or bs == AnimState.STRAFE_RIGHT:
		var anim := _get_cached_animation(bs)
		var _intent_walk: float = DESIGN_WALK_SPEED * 0.6 if input_dir.length() > 0.1 else 0.0
		var ratio: float = clamp(maxf(spd, _intent_walk) / DESIGN_WALK_SPEED, 0.3, 1.5 * mult)
		if anim != null and anim.length > 0.01:
			ratio *= anim.length / REFERENCE_WALK_ANIM_LEN
		return ratio
	return 1.0

## 下半身轨道循环铺满 + 时间压缩（time_scale>1=加速腿步频）。与 copy_looping_track_to_fill
## 等价，但关键帧时间先 /time_scale 再循环，使合成动画播速 1.0 时腿节奏匹配移动速度。
func _fill_lower_track_compressed(src: Animation, src_idx: int, dst: Animation, target_length: float, time_scale: float) -> void:
	var new_idx := dst.add_track(src.track_get_type(src_idx))
	dst.track_set_path(new_idx, src.track_get_path(src_idx))
	var key_count := src.track_get_key_count(src_idx)
	var src_len: float = src.length
	if key_count < 2 or src_len <= 0.01:
		return
	var scaled_len: float = src_len / time_scale
	if scaled_len <= 0.001:
		return
	var repeats := int(ceil(target_length / scaled_len)) + 1
	for r in range(repeats):
		var time_offset: float = r * scaled_len
		for j in range(key_count):
			var new_time: float = src.track_get_key_time(src_idx, j) / time_scale + time_offset
			if new_time > target_length + 0.001:
				break
			dst.track_insert_key(new_idx, new_time, src.track_get_key_value(src_idx, j))
	dst.track_set_interpolation_type(new_idx, src.track_get_interpolation_type(src_idx))

## 当前武器是否为尼泊尔刀（近战类）
func _is_nepal_weapon() -> bool:
	return _weapon_system != null and _weapon_system.get_current_weapon() != null \
		and _weapon_system.get_current_weapon().weapon_type == "knife"

## 按实时输入/姿态推断挥刀时应显示的下半身状态（不经状态机，供挥刀期间下半身跟随用）。
## 解决：点按移动键同时挥刀（挥刀时刻状态还是待机 → 腿不动）、转身/变向时挥刀（腿锁定旧方向）卡顿。
func _nepal_lower_state_now(on_floor: bool) -> AnimState:
	if not on_floor:
		if velocity.y > 0.5:
			return AnimState.JUMP_UP
		return AnimState.JUMP_DOWN
	var fwd: bool = input_dir.y > 0.1
	var back: bool = input_dir.y < -0.1
	var left: bool = input_dir.x < -0.1
	var right: bool = input_dir.x > 0.1
	if is_crouching:
		if fwd:
			return AnimState.CROUCH_WALK_FORWARD
		if back:
			return AnimState.CROUCH_WALK_BACKWARD
		if left:
			return AnimState.CROUCH_STRAFE_LEFT
		if right:
			return AnimState.CROUCH_STRAFE_RIGHT
		return AnimState.CROUCH_IDLE_AIM
	if is_running and fwd:
		return AnimState.RUN
	if fwd:
		return AnimState.WALK_FORWARD
	if back:
		return AnimState.WALK_BACKWARD
	if left:
		return AnimState.STRAFE_LEFT
	if right:
		return AnimState.STRAFE_RIGHT
	return AnimState.IDLE_AIM

## 挥刀期间下半身动态跟随：移动状态（走↔跑↔跳↔蹲↔方向）变化时重新合成并 seek 回进度。
## ⚠️ 只在状态变化时重装（不每帧 install），install 前已 stop → 规避历史"每帧 install 缓存重建崩溃"。
func _nepal_maybe_follow_lower() -> void:
	if anim_player == null or not is_instance_valid(anim_player):
		return
	if current_state != AnimState.NEPAL_ATTACK_LIGHT and current_state != AnimState.NEPAL_ATTACK_HEAVY:
		return
	# 【挥刀兼容·防打断】重合成会 stop+install+play 挥刀动画 → 频繁触发=挥刀动画反复重启
	# = 用户看到的"挥刀瞬间任何操作都卡顿/错乱"。两道闸：
	# ① 起手保护期（0.12s）：挥刀起手帧不跟随，避免"挥刀+按蹲/移动"瞬间的立即重合成
	#   （此时下半身按起手锁定意图合成，短暂不跟也不会脱节）；
	# ② 限频（0.08s）：蹲/方向快速变化时合并为一次重合成，不逐帧打断。
	var now_ms: int = Time.get_ticks_msec()
	if now_ms - _nepal_atk_start_ms < NEPAL_FOLLOW_START_GUARD_MS:
		return
	if _nepal_last_follow_ms >= 0 and now_ms - _nepal_last_follow_ms < NEPAL_FOLLOW_MIN_INTERVAL_MS:
		return
	var want: AnimState = _nepal_lower_state_now(_is_on_floor())
	if want == _nepal_atk_lower:
		return
	var pos: float = anim_player.current_animation_position
	var arms: Animation = _nepal_light_arms if current_state == AnimState.NEPAL_ATTACK_LIGHT else _nepal_heavy_arms
	if NEPAL_LOG:
		print("[NEPAL] 下半身跟随重合成: %s → %s (进度 %.3f)" % [
			_anim_state_str(_nepal_atk_lower), _anim_state_str(want), pos])
	_install_nepal_attack(current_state, arms, want)
	_nepal_last_follow_ms = now_ms
	var nm: String = _anim_name_for(current_state)
	if nm != "" and anim_player.has_animation(nm):
		_anim_op("PLAY@1649_restart_stance")
		anim_player.play(nm)
		_anim_op("SEEK@1650_restart_stance")
		anim_player.seek(min(pos, anim_player.get_animation(nm).length - 0.001), true)
	debug_print("挥刀下半身跟随: %s (进度 %.3f)" % [str(want), pos])

## 计算节点下所有 MeshInstance3D 的合并【局部】AABB（用于挂载前缩放+居中）。
## 递归遍历子节点，合并每个 MeshInstance3D 的 mesh.aabb（经其局部变换）。
func _compute_local_mesh_aabb(root: Node) -> AABB:
	var aabb := AABB()
	var has := false
	var stack: Array[Node] = [root]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			var local_ba: AABB = mi.mesh.get_aabb()
			# 应用 MeshInstance3D 自身 transform 到 AABB 8 顶点
			var t: Transform3D = mi.transform
			for i in 8:
				var wp: Vector3 = t * local_ba.get_endpoint(i)
				if not has:
					aabb = AABB(wp, Vector3.ZERO)
					has = true
				else:
					aabb = aabb.expand(wp)
		for c in n.get_children():
			stack.append(c)
	if not has:
		return AABB(Vector3.ZERO, Vector3(0.38, 0.05, 0.05))
	return aabb

# 集中复位所有会导致"卡死/输入吞没"的状态锁与计时器，避免散落复制导致遗漏。
# 角色切换(on_character_switched)与复活(_resurrect)共用，确保状态机复位一致。
func _reset_all_locks() -> void:
	is_transitioning = false
	transition_timer = 0.0
	is_crouching = false
	_crouch_hold = false
	_crouch_press_time = 0.0
	is_running = false
	_jump_from_run = false
	_jump_delay_timer = 0.0
	_running_exit_timer = 0.0
	_target_visual_y = 0.0
	_is_in_one_shot_override = false
	_state_before_one_shot = AnimState.IDLE_AIM
	_nepal_atk_lower = AnimState.IDLE_AIM   # 复位挥刀下半身跟随基准
	# 【方案C】清挥砍直驱会话
	_nepal_attacking = false
	_nepal_atk_arms = null
	_nepal_atk_elapsed = 0.0
	_nepal_atk_track_bones.clear()   # 【性能】会话缓存同步作废
	# 【方案C】清手雷直驱会话（拉环/持环/投掷）
	_stop_grenade_arms()
	_is_in_crouch_hit_back = false
	_is_reloading = false
	_reload_input_buffer = 0.0   # 清换弹输入缓冲，避免死亡/切换后残留的 R 误触发换弹
	_reload_elapsed = 0.0
	# 【P3 开镜射击】全量重置（死亡/复活/切角色）时丢弃自动重开镜流程，防残留误开镜
	_scope_shot_pending = false
	_scope_shot_cancel = false

## 换弹时长 = FP reload 动画时长 与 3P Reloading 动画时长 的中间值（用户要求：
## 3P 动画按 _reload_duration 加速、FP 动画按 _reload_duration 放慢，两侧节奏一致）。
## 统一「初装」与「角色切换」两条路径的算法，避免切换角色后换弹声 pitch 突变（变低沉/变尖）。
## 换弹声 pitch = 音效自然时长 / _reload_duration，故 _reload_duration 越长 → 声音越「低沉」。
func _recompute_reload_duration() -> void:
	# 【P3 多武器】武器可显式覆盖换弹时长（WeaponDef.reload_duration>0），
	# 狙击枪等换弹节奏特殊的武器优先用自身节奏，不被 3P Mixamo 均值拖长。
	if _weapon_system != null and _weapon_system.get_current_weapon() != null:
		var _wd: WeaponDef = _weapon_system.get_current_weapon()
		if _wd.reload_duration > 0.01:
			_reload_duration = _wd.reload_duration
			return
	var _fp_reload_dur: float = -1.0
	if _fp_vm != null and _fp_vm.has_method("get_reload_anim_duration"):
		_fp_reload_dur = _fp_vm.get_reload_anim_duration()
	if _fp_reload_dur > 0.01 and _reload_anim_len > 0.01:
		_reload_duration = (_fp_reload_dur + _reload_anim_len) * 0.5
	elif _fp_reload_dur > 0.01:
		_reload_duration = _fp_reload_dur
	elif _reload_anim_len > 0.01:
		_reload_duration = _reload_anim_len

## 统一换弹变体 speed_scale：变体长 / _reload_duration，clamp 到 [0.5, 4.0]。
## 换弹启动(_play_one_shot_override)与换弹中切换(_switch_reload_animation)共用同一算法，
## 避免两处 clampf 漂移导致后续维护只改一处、两个路径节奏不一致。
## 边界：变体长或 _reload_duration 过小(<=0.01)时返回 1.0（不缩放），杜绝除零/NaN。
func _reload_speed_scale(anim_len: float) -> float:
	if anim_len <= 0.01 or _reload_duration <= 0.01:
		return 1.0
	return clampf(anim_len / _reload_duration, 0.5, 4.0)

## ============================================================
## 【新武器键位 P3+】数字键直选 / Q 上一把 的共用实现
## ============================================================

## 统一"装备并应用某武器"流程（原 X 键 switch_next 主体提取复用）。
## 数字键直选、Q 上一把 都走这里，避免逻辑重复。
func _switch_to_weapon(def: WeaponDef) -> void:
	if def == null:
		return
	# 【蹲/站过渡中切武器·不跳过过渡动画】过渡只有 ~0.1s，把切换挂起到过渡自然
	# 播完（_on_transition_done）再执行。旧实现直接 _finish_crouch_transition_now()
	# 瞬间完成 → 用户实测"蹲下-站立的过渡动画一瞬间切武器会直接跳过过渡"。
	if is_transitioning:
		_pending_switch_def = def   # 后按的覆盖先按的（以最后一次为准）
		return
	_do_switch_weapon(def)

## 实际执行切换（过渡中由 _on_transition_done 在过渡播完后调用）。
func _do_switch_weapon(def: WeaponDef) -> void:
	if def == null:
		return
	# 【Q键·上一把】记录切换前实际持有的武器：任何成功换枪都会把当前枪存为
	# "上一把"，Q 即可在最近两把枪之间往返 toggle；开局/复活时无记录 → Q 走第二把。
	var _prev_cur: WeaponDef = _weapon_system.get_current_weapon() if _weapon_system != null else null
	if _prev_cur != null and _prev_cur.id != def.id:
		_prev_weapon_id = _prev_cur.id
	# 【切武器·清残留锁】一次性动画（挥刀/换弹）未完成就切武器，one_shot 残留 →
	# 新武器下状态机锁死（实测：state 卡在 NEPAL_ATTACK、动画停止）。切武器 = 干净打断。
	# （蹲/站过渡不会到这里——已由 _switch_to_weapon 挂起等过渡播完。）
	_nepal_attacking = false
	_nepal_atk_arms = null
	_nepal_atk_elapsed = 0.0
	if _is_in_one_shot_override:
		# 【切武器·挥刀状态先归位】必须先把 current_state 从 NEPAL_ATTACK 改回待机，
		# 否则 _apply_nepal_stance(false) 的 893-896（one_shot 且挥刀 → 回待机）因
		# one_shot 已被下面清掉而跳过 → current_state 残留 32/33 → _restart_stance_animation
		# 用挥刀状态名重播挥砍动画 → 切回步枪后手一直挥刀姿势（实测 1 帧后 cur 仍是
		# Nepal Attack Light、手部偏差 0.79m）。
		if current_state in _NEPAL_ATTACK_STATES:
			current_state = AnimState.CROUCH_IDLE_AIM if is_crouching else AnimState.IDLE_AIM
			_state_before_one_shot = current_state
		_is_in_one_shot_override = false
		if is_instance_valid(anim_player) and anim_player.is_playing():
			_anim_op("STOP@1775_cancel_oneshot")
			anim_player.stop()
		if _is_reloading:
			_is_reloading = false
	_cancel_scope()
	if _weapon_system != null:
		_weapon_system.equip(def.id)
	var wd: WeaponDef = def
	if wd != null and wd.id != _applied_weapon_id:
		_apply_weapon_to_subsystems(wd)
		_applied_weapon_id = wd.id
		_scope_shot_cancel = true
		_recompute_reload_duration()
		if wd.weapon_type == "rifle":   # rifle = 使用角色内嵌枪模型的步枪（当前即 AK47）
			if _dynamic_world_model != null and is_instance_valid(_dynamic_world_model):
				_free_dynamic_world_model()
			var _embedded: Node3D = character_visual.find_child("Weapon_AK47", true, false) as Node3D if character_visual != null else null
			if _embedded != null:
				_embedded.visible = true
				_weapon_holder = _embedded
				_apply_weapon_fp_shadow(_fp_mode)
				if _weapon_rig != null:
					_weapon_rig.skip_follow = false
		else:
			_ensure_3p_world_model(wd)
		if character_visual != null and _weapon_rig != null and _weapon_skel != null:
			var holder: Node3D = _weapon_holder
			if holder != null:
				var base_cfg: WeaponRigConfig = null
				if char_manager != null and char_manager.get_active_asset() != null:
					base_cfg = char_manager.get_active_asset().weapon_rig_config as WeaponRigConfig
				_weapon_rig.setup(_weapon_skel, holder, _weapon_system.prepare_rig_config(base_cfg))

## 按武器 id 直选（数字键）：当前角色无此武器则提示，不切换。
func _select_weapon_by_id(wid: String) -> void:
	if _weapon_system == null:
		return
	var def: WeaponDef = _weapon_system.find_weapon(wid)
	if def == null:
		var hud := _get_hud()
		if hud != null and hud.has_method("show_message"):
			hud.call("show_message", "当前角色无此武器", 1.0)
		return
	_switch_to_weapon(def)

## 当前角色可用武器按槽位顺序（跳过空槽，如 4=手雷）。
## 纯列表查询已下沉 WeaponSystem.get_slot_weapons，此处仅传槽位映射。
func _available_slot_weapons() -> Array:
	if _weapon_system == null:
		return []
	return _weapon_system.get_slot_weapons(WEAPON_SLOT_IDS)

## Q 键：切换上一把【实际持有过】的武器（last-weapon toggle）。
## 无上一把（开局/复活后未换过枪）→ 切到第二把武器（2 号槽；当前角色没有 2 号槽
## 武器时回退到可用清单的第二把）。
func _switch_prev_weapon() -> void:
	if _weapon_system == null:
		return
	var target: WeaponDef = null
	if _prev_weapon_id != "":
		target = _weapon_system.find_weapon(_prev_weapon_id)
	if target == null:
		var list := _weapon_system.get_slot_weapons(WEAPON_SLOT_IDS)
		if list.size() >= 2:
			target = list[1] as WeaponDef
	if target == null:
		return
	var cur: WeaponDef = _weapon_system.get_current_weapon()
	if cur != null and target.id == cur.id:
		return   # 已是目标武器（如开局默认就是 2 号槽）→ 无操作
	_switch_to_weapon(target)

func on_character_switched(char_id: String) -> void:
	if char_manager == null:
		return
	var asset: CharacterAsset = char_manager.get_active_asset()
	if asset == null or asset.anim_lib == null:
		return
	# 【P3 开镜射击】角色切换 = 手动干预：中断自动重开镜流程
	_scope_shot_cancel = true
	# 【阶段3】切角色 = 骨架重建：作废在途的尼泊尔刀挂载状态机（旧 skel 引用已释放，
	# 否则 _process_nepal_mount_pending 读 _nepal_mount_pending[2] 时遇 freed instance）。
	_nepal_mount_pending = []
	# 0) 【P2 修订】重新挂载新角色视觉到挂载点 + 重新解析引用
	#    （必须在退出开镜之前执行：_exit_scope 会按 character_visual 恢复显隐/阴影，
	#     若先关镜，_set_character_visual_fp_shadow_only 强制 visible=true 会落到已被
	#     switch_to 移回 manager 隐藏的【旧角色】上 → 旧角色重新可见 + 新角色可见
	#     = 地图上同时出现两个角色模型。先挂新角色，恢复逻辑作用在新角色上。）
	char_manager.mount_active_to(self)
	var active := $Character.get_node_or_null("ActiveCharacter")
	if active != null:
		character_visual = active as Node3D
		anim_player = active.find_child("AnimationPlayer", true, false) as AnimationPlayer
	# 【P3 多武器】切换角色时强制退出开镜（新角色可能不带瞄准镜，避免准镜残留）。
	# 必须在 mount_active_to 之后：_exit_scope 的显隐/阴影恢复作用于新 character_visual。
	_cancel_scope()
	# 【P3 多武器】角色切换后刷新武器系统：重新拉取当前角色武器清单，
	# 确保 current_def 跟随激活角色（清单不同的角色切换时不会拿到旧角色武器）。
	if _weapon_system != null:
		_weapon_system.refresh()
	# 1) 更换动画库（当前角色资产换算好的动画库 + 【P4】AnimClip 扩展库）
	if anim_player != null:
		anim_player.remove_animation_library("")
		# 【修复】与 _ready 写法一致加守卫：角色资产无 extra_anim_lib 时 "clips"
		# 库从未添加，无条件 remove 会在每次切角色时刷引擎报错(clips does not exist)
		if anim_player.has_animation_library("clips"):
			anim_player.remove_animation_library("clips")
		anim_player.add_animation_library("", asset.anim_lib)
		if asset.extra_anim_lib != null:
			anim_player.add_animation_library("clips", asset.extra_anim_lib)
	# 2) 清空动画缓存（角色动画库不同）
	_anim_cache.clear()
	# 【P2 修复】重做动画库后处理：新角色库的 position 轨道从未被剥离，
	# 不处理会导致蹲姿动画 Hips 双重下压（动画值 + 视觉偏移）→ 大半个身子陷地。
	_post_process_anim_library()
	# 3) 重新计算换弹时长：先取新库 Reloading 长度（含回位尾巴）作 3P 基准，
	# 再用统一算法（FP+3P 均值）重算 _reload_duration——与初装一致，
	# 修复「切换角色后换弹声 pitch 突变变低沉」。详见 _recompute_reload_duration 注释。
	var _reload_src: Animation = _get_cached_animation(AnimState.RELOADING)
	if _reload_src:
		_reload_anim_len = _reload_src.length
	# 4) 【P2 修订】重新绑定武器系统到新角色（骨架/武器/FP/标注球隐藏）
	_rebind_weapon_for_visual()
	# 【修复】换弹/一次性覆盖中切换角色：必须清除换弹锁与一次性动画锁，
	# 否则 _is_in_one_shot_override 残留 true → _physics_process 走一次性动画分支
	# 但 current_state 已是 IDLE_AIM（循环动画永不播完）→ 换弹/蹲下/移动输入
	# 全部被吞 → 角色卡死（实测：切后按 R/蹲下均无反应）。
	# 【修复】蹲下过渡中切换：is_transitioning 残留 → 过渡分支（1003行）永久接管，
	# 3s 超时后 _on_transition_done 因 current_state=IDLE_AIM 不匹配任何分支、锁不清
	# → 永久卡死；蹲姿受击倒地中切换：_is_in_crouch_hit_back 残留 → 874行分支锁定输入。
	# 完整状态清理（与 _resurrect 共用 _reset_all_locks，避免遗漏导致卡死）
	_reset_all_locks()
	character_visual.position.y = 0.0
	_update_collision_height(_standing_height())
	if camera_controller != null:
		camera_controller.set_crouch(false, 0.3)      # 相机恢复站立高度
		camera_controller.set_rotation_locked(false)  # 解锁角色旋转（蹲姿受击锁过）
	_reset_fp_state()  # 切换角色时清 FP 子系统（停换弹/连发/后坐、视图模型回 idle）
	# 【P3 换皮】FP 视图模型按角色切换：新角色配了专属 fp_viewmodel_scene 且与
	# 当前来源不同 → 重建视图模型（释放旧模型，加载新场景挂到相机）。两角色均
	# 未配置专属场景（共享默认）时 cur==new 不触发，零开销。
	if _fp_vm != null:
		var new_fp_scene: PackedScene = asset.fp_viewmodel_scene
		var new_fp_path: String = new_fp_scene.resource_path if new_fp_scene != null and new_fp_scene.resource_path != "" else FPViewmodelPlayer.VM_PATH
		if _fp_vm.vm_scene_path != new_fp_path:
			_rebuild_fp_viewmodel(new_fp_scene)
	# 【修复】换弹时长按统一算法（FP+3P 均值）重算，须放在 FP 视图模型重建之后，
	# 才能用上新角色专属 fp_viewmodel 的 reload 时长；与初装 _recompute_reload_duration 一致。
	_recompute_reload_duration()
	# 【P3 多武器】角色切换后子系统已重建 → 重新把当前武器行为数据应用到新子系统
	# （数据驱动；AK47 字段为空→走默认常量，行为不变）。
	# 【手枪姿态】角色动画库已换 → 丢弃旧备份，_apply_pistol_stance 会为新角色重新备份/合成
	_pistol_saved.clear()
	_pistol_applied.clear()
	# 【尼泊尔姿态】同上：丢弃旧角色备份，_apply_nepal_stance 会为新角色重新合成
	_nepal_saved.clear()
	_nepal_applied.clear()
	# 【手雷姿态】同上：丢弃旧角色备份，_apply_grenade_stance 会为新角色重新合成
	_grenade_saved.clear()
	_grenade_applied.clear()
	_apply_weapon_to_subsystems(_weapon_system.get_current_weapon() if _weapon_system != null else null)
	# 【P3】切换角色：强制结束激活中的能力（防残留加速/状态）
	_force_finish_ability()
	_ability_speed_mult = 1.0
	# 【修复】按当前视角模式重设 3P 角色/武器的显隐状态：
	# FP 下切换角色 → 新角色若保持默认 SHADOW_CASTING_ON，3P 实体 + FP viewmodel
	# 会同时渲染（穿模）；必须按 _fp_mode 对新角色重新应用 SHADOWS_ONLY / ON。
	_apply_view_mode_to_visual()
	# 5) 回到待机
	_change_state(AnimState.IDLE_AIM)
	_play_animation(AnimState.IDLE_AIM, true, 1.0)
	# 【P2 修复】anim_player 已换成新角色的播放器：重连动画完成信号，
	# 否则新角色的一次性动画（蹲伏过渡/换弹/跳跃等）播完无法触发状态切换。
	_connect_anim_signals()
	debug_print("on_character_switched: %s（动画库+武器已重绑）" % char_id)

## 【P2 修复】连接当前 anim_player 的 animation_finished 信号。
## 角色切换时 anim_player 被替换为新角色的播放器，旧连接失效 →
## 动画播完信号无人监听，状态机卡死。此方法保证始终监听【当前】播放器。
func _connect_anim_signals() -> void:
	if _connected_anim_player == anim_player and anim_player != null:
		return
	# 断开旧播放器的连接（防止旧节点释放后信号悬挂）
	if _connected_anim_player != null and is_instance_valid(_connected_anim_player):
		if _connected_anim_player.animation_finished.is_connected(_on_animation_finished):
			_connected_anim_player.animation_finished.disconnect(_on_animation_finished)
	_connected_anim_player = anim_player
	if anim_player != null:
		anim_player.animation_finished.connect(_on_animation_finished)

# ============================================================
# 【P2 修订】切换角色后重新绑定武器系统到新视觉：
# - 重新解析 _weapon_skel / _weapon_holder（当前角色视觉下的）
# - WeaponRig.setup 重新标定（换皮自适应在 setup 内：按骨架缩放换算握持偏移）
# - FPActionRetarget 重新 setup（骨架/武器/火光）
# - 隐藏所有 GripPoint 标注球（避免编辑器标定球在游戏里可见）
# ============================================================
func _rebind_weapon_for_visual() -> void:
	if character_visual == null:
		return
	# 骨架与武器挂点（当前角色视觉下）
	_weapon_skel = character_visual.find_child("Skeleton3D", true, false) as Skeleton3D
	var holder: Node3D = character_visual.find_child("Weapon_AK47", true, false) as Node3D
	_weapon_holder = holder
	# 【P3 二期】3P 世界枪 world_model 动态实例化（仅角色【未内嵌】武器节点时）：
	# 角色内嵌 Weapon_AK47 → holder 非空 → 复用内嵌，绝不实例化（AK47 走此路径，行为零变化）；
	# 角色未内嵌（新武器+新角色场景不挂枪节点）→ 按当前武器 world_model 实例化挂到角色下，
	# 使"加新武器=填 world_model 字段"即出 3P 枪，无需改代码。切换回内嵌角色时释放上一动态实例。
	if holder == null:
		_ensure_3p_world_model(_weapon_system.get_current_weapon() if _weapon_system != null else null)
		holder = _weapon_holder   # 后续握持/枪口绑定用动态实例（若有）
	else:
		# 角色内嵌 Weapon_AK47：先恢复 visible（切到 M82 时 _ensure_3p_world_model 隐藏过它）；
		# 当前武器若不是 ak47（角色切换后仍是 M82）→ 重新隐藏内嵌 + 实例化当前武器 3P 枪。
		holder.visible = true
		_free_dynamic_world_model()
		if _weapon_rig != null:
			_weapon_rig.skip_follow = false   # 恢复内嵌 AK47 的握持跟随
		var _cur_def: WeaponDef = _weapon_system.get_current_weapon() if _weapon_system != null else null
		if _cur_def != null and _cur_def.weapon_type != "rifle":
			_ensure_3p_world_model(_cur_def)
			holder = _weapon_holder   # 后续握持/枪口绑定用动态实例
	if _weapon_skel != null:
		_weapon_bone_idx = _weapon_skel.find_bone("mixamorig_RightHand")
		_lhand_bone_idx = _weapon_skel.find_bone("mixamorig_LeftHand")
		_torso_bone_idx = _weapon_skel.find_bone(TORSO_BONE)
		if _torso_bone_idx >= 0:
			_torso_parent_idx = _weapon_skel.get_bone_parent(_torso_bone_idx)
	# 重新 setup WeaponRig（换皮自适应偏移在 setup 内按骨架缩放）
	if _weapon_rig != null and _weapon_skel != null and holder != null:
		var cfg: WeaponRigConfig = null
		# 【P3】走 WeaponSystem：武器握持配置（WeaponDef）+ 当前角色骨架缩放
		if _weapon_system != null:
			var base_cfg: WeaponRigConfig = null
			if char_manager != null and char_manager.get_active_asset() != null:
				base_cfg = char_manager.get_active_asset().weapon_rig_config as WeaponRigConfig
			cfg = _weapon_system.prepare_rig_config(base_cfg)
		if cfg == null:
			cfg = load("res://resources/weapon_rig_config.tres") as WeaponRigConfig
		_weapon_rig.setup(_weapon_skel, holder, cfg)
	# 隐藏标注球（编辑器标定用，游戏内不可见）
	for gp_name in ["GripPoint_RH", "GripPoint_LH", "GripPoint_Elbow_RH",
					"GripPoint_Muzzle", "GripPoint_Butt", "GripPoint_GunGrip"]:
		var gp = character_visual.find_child(gp_name, true, false)
		if gp != null:
			gp.visible = false
	# 【修复】隐藏枪口标注球 MarkerBall（红色球，编辑器标注用，挂 MuzzleMarker 下）
	# MuzzleMarker 位置节点本身保留（射击火光/逻辑用它），只隐藏其下标注网格。
	var mball: Node3D = character_visual.find_child("MarkerBall", true, false) as Node3D
	if mball != null:
		mball.visible = false
	# FPActionRetarget 重绑（骨架变化后需要新引用）——直接更新引用字段，
	# 不重复调 setup（setup 会重建 AudioStreamPlayer → 内存泄漏 + 音效叠加）
	if _fp_action != null:
		_fp_action.skel = _weapon_skel
		_fp_action.gun_holder = holder
		_fp_action.weapon_rig = _weapon_rig
		# 火光重挂到新武器 MuzzleMarker（若存在），保证射击火光跟随当前角色
		if holder != null and _fp_action.muzzle_flash != null:
			var marker: Node3D = holder.find_child("MuzzleMarker", true, false) as Node3D
			if marker != null:
				_fp_action.muzzle_flash.get_parent().remove_child(_fp_action.muzzle_flash)
				marker.add_child(_fp_action.muzzle_flash)

## 【P3 二期】3P 世界枪动态实例化：按当前武器 WeaponDef.world_model 实例化 3P 枪挂到角色下。
## - 角色【未内嵌】武器节点 → 直接实例化（新武器+新角色场景）。
## - 角色【内嵌 Weapon_AK47】（飞虎队/SWAT 等）：当前武器不是 ak47 时，隐藏内嵌枪
##   （_weapon_holder.visible=false 保留节点，切回 AK47 恢复），再实例化本武器 3P 枪，
##   避免两把枪重叠。全部失败路径静默降级（push_warning），绝不抛错/崩。
func _ensure_3p_world_model(def: WeaponDef) -> void:
	if character_visual == null or def == null:
		return
	# 【崩溃修复·卫哨】_weapon_holder 会被动态实例（刀/M82/高抛）覆盖（见下方 _weapon_holder = inst）。
	# 上一把动态实例释放后该引用悬空（freed instance），此处任何 .visible 访问都会崩。
	# 进函数先自检：无效则重新指回当前角色视觉下的内嵌 Weapon_AK47（找不到留 null）。
	_revalidate_weapon_holder()
	# 无 3P 世界模型（纯 FP 武器，如 v_deagle/尼泊尔）：隐藏内嵌 AK47 枪 + 释放动态实例，
	# 3P 下不显示"错枪"（宁可空手，不拿 AK47）。
	if def.world_model == null:
		if _weapon_holder != null and def.weapon_type != "rifle":
			_weapon_holder.visible = false
		_free_dynamic_world_model()
		return
	# 内嵌步枪枪：仅当切换到其它武器时隐藏它；仍是内嵌步枪则早退（复用内嵌，零变化）
	var is_embedded_rifle: bool = def.weapon_type == "rifle"
	if is_embedded_rifle:
		# 【修复】上一把武器（刀/手枪/M82）把内嵌枪设成 visible=false，切回 AK47 必须
		# 先释放那把动态实例（否则两把枪重叠）再恢复内嵌枪可见，否则手里空空。
		_free_dynamic_world_model()
		if _weapon_holder != null:
			_weapon_holder.visible = true
			return   # AK47：角色内嵌枪直接复用，不实例化
	# 【修复 BUG】有 world_model 的非 ak47 武器（v_deagle/gaobao）也必须隐藏内嵌 AK47 枪，
	# 否则 3P 下 AK47 内嵌枪与动态武器重叠（AK47 盖住手枪 → 用户看到"手枪不见了"）。
	if _weapon_holder != null:
		_weapon_holder.visible = false
	# 释放上一把动态实例（同一无内嵌角色内换武器场景，_dynamic_world_model 指向旧实例）
	if _dynamic_world_model != null and is_instance_valid(_dynamic_world_model):
		if _dynamic_world_model.get_parent() != null:
			_dynamic_world_model.get_parent().remove_child(_dynamic_world_model)
		_dynamic_world_model.queue_free()
		_dynamic_world_model = null
	var inst: Node3D = def.world_model.instantiate() as Node3D
	if inst == null:
		push_warning("武器 world_model 实例化失败（%s），3P 枪不显示" % str(def.world_model))
		return
	character_visual.add_child(inst)
	# 【P3 多武器】3P 枪摆位：
	# - use_world_3p_pose=true → 用户手动标定固定摆位（world_3p_*），最终效果；
	#   WeaponRig 不覆盖（skip_follow=true），枪挂角色下跟随移动但不跟手臂动画。
	# - 否则有专属 weapon_rig_config → WeaponRig 跟手（轴线匹配）。
	# - 否则自动兜底（几何中心对齐 AK47 握持位）。
	var _has_own_rig: bool = (def != null and def.weapon_rig_config != null)
	var _use_manual: bool = (def != null and def.use_world_3p_pose)
	if _use_manual:
		inst.transform = Transform3D(
			Basis.from_euler(def.world_3p_rot).scaled(Vector3.ONE * def.world_3p_scale),
			def.world_3p_pos)
		if DEBUG_MODE: print("3P 枪摆位(手动): %s pos=%s rot=%s scale=%s" % [def.id, def.world_3p_pos, def.world_3p_rot, def.world_3p_scale])
	elif def.id == "nepal_kukri":
		_mount_nepal_knife_world_model(def, inst)
		return
	elif def.id == "gaobao":
		_mount_grenade_world_model(def, inst)
		return
	elif _has_own_rig:
		# 专属 rig：WeaponRig 每帧接管（下方 skip_follow=false）
		pass
	else:
		# 自动兜底：M82 枪口方向（flash 骨骼实测，模型挂原点无动画时）= (0.1544, 0.4801, -0.8635)。
		const M82_MUZZLE_LOCAL := Vector3(0.154428, 0.480094, -0.863517)
		var ak_center := Vector3(-0.299815, 2.400911, 1.058839)  # AK47 网格世界中心（编辑器标定）
		var my_center := _mesh_center_local(inst)  # M82 网格本地中心（米）
		var target_fwd := Vector3(0, 0, -1)
		var basis := Basis(Quaternion(M82_MUZZLE_LOCAL.normalized(), target_fwd))
		var origin := ak_center - basis * my_center
		inst.transform = Transform3D(basis, origin)
		if DEBUG_MODE: print("3P 枪摆位(自动): %s origin=%s" % [def.id, origin])
	# 隐藏内嵌标注球（与内嵌节点一致处理，避免编辑器标定球在游戏内可见）
	for gp_name in ["GripPoint_RH", "GripPoint_LH", "GripPoint_Elbow_RH",
					"GripPoint_Muzzle", "GripPoint_Butt", "GripPoint_GunGrip", "MarkerBall"]:
		var gp = inst.find_child(gp_name, true, false)
		if gp != null:
			gp.visible = false
	# 非 AK47：隐藏内嵌 AK47 枪（保留节点，切回 AK47 时恢复）
	if _weapon_holder != null:
		_weapon_holder.visible = false
	_weapon_holder = inst
	_dynamic_world_model = inst
	# 【P3 多武器】动态 3P 枪握持跟随策略：
	# - 手动标定（use_world_3p_pose）→ skip_follow=true（固定摆位，不被 WeaponRig 覆盖）。
	# - 专属 weapon_rig_config → skip_follow=false（WeaponRig 轴线匹配跟手）。
	# - 无专属 → skip_follow=true（固定摆位）。
	# - 【尼泊尔】刀由 BoneAttachment3D 绑左手骨骼（动画驱动左臂），
	#   WeaponRig 是枪械右手握持逻辑，会污染刀的 transform → 强制 skip_follow=true。
	if _weapon_rig != null:
		_weapon_rig.skip_follow = _use_manual or not _has_own_rig or def.id == "nepal_kukri" or def.id == "gaobao"
	# 【P3 修复】实例化新 3P 枪后按【当前视角模式】设 shadow：FP→SHADOWS_ONLY
	# （实体不渲染只投影，避免与 FP viewmodel 同屏=两把枪）、3P→ON（正常渲染）。
	# 之前仅 FP 分支处理，3P 下新枪 cast_shadow 依赖实例默认（可能残留旧值）。
	_apply_weapon_fp_shadow(_fp_mode)
	debug_print("3P 世界枪已动态实例化: %s" % def.id)

## 【尼泊尔刀·每角色挂点标定】刀相对右手骨骼局部系的 transform。
## 数据来源：标定场景 scenes/nepal_knife_calib.tscn（编辑器拖拽 → 一键保存到
## 对应角色的 nepal_knife_calib_<角色>.tres）。每角色独立标定，无 k 跨角色换算
## （k 假设两骨架纯缩放，实测 SWAT 骨骼姿态有旋转差 → 纯 k 会偏移，用户实测）。
## tres 缺失/角色未标定时回退：旧全局常量 × k（改动前行为）。结果按角色缓存。
const NEPAL_KNIFE_CALIB_PATHS := {
	"feihu": "res://resources/characters/nepal_knife_calib_feihu.tres",
	"swat": "res://resources/characters/nepal_knife_calib_swat.tres",
}
var _nepal_calib_cache: Dictionary = {}   # char_id -> Transform3D

func _get_nepal_knife_local() -> Transform3D:
	var char_id: String = ""
	if char_manager != null and char_manager.get_active_asset() != null:
		char_id = char_manager.get_active_asset().id
	if _nepal_calib_cache.has(char_id):
		return _nepal_calib_cache[char_id]
	var L: Transform3D
	var loaded = null
	var path: String = NEPAL_KNIFE_CALIB_PATHS.get(char_id, "")
	if path != "" and ResourceLoader.exists(path):
		loaded = load(path)   # NepalKnifeCalib（duck-type 访问，规避 headless 类缓存）
	if loaded != null:
		L = Transform3D(Basis(loaded.local_rot).scaled(loaded.local_scale), loaded.local_pos)
	else:
		# 回退：旧全局常量 × k 换算（A 空间 → 当前角色空间，改动前行为）
		var role_scale: float = 0.00026
		if _weapon_system != null:
			role_scale = _weapon_system.get_role_skeleton_scale()
		var k: float = 0.00026 / role_scale if role_scale > 0.0 else 1.0
		L = Transform3D(Basis(NEPAL_KNIFE_LOCAL_ROT).scaled(NEPAL_KNIFE_LOCAL_SCALE * k),
			NEPAL_KNIFE_LOCAL_POS * k)
		if char_id != "":
			push_warning("尼泊尔刀: 角色 %s 无标定资源，回退全局常量×k（请在标定场景 scenes/nepal_knife_calib.tscn 重新保存）" % char_id)
	_nepal_calib_cache[char_id] = L
	return L

## 尼泊尔刀 3P 世界模型挂载（骨骼 BoneAttachment 绑右手 / 无骨骼退化为固定摆位）
## 【WYSIWYG·直读预览】不再使用烤死的常量：运行时加载 nepal_knife_preview.tscn，
## 读取用户调好的 Knife 子树 + 刀柄标注点，用与预览 _bind_handle_to_palm 完全一致的公式，
## 算成"相对右手骨骼的局部 transform"挂上去。编辑器怎么调，游戏就怎么显示
## （含 22° 抬臂待机，游戏侧 _apply_nepal_stance 已在装备时安装）。
func _mount_nepal_knife_world_model(def: WeaponDef, inst: Node3D) -> void:
	if DEBUG_MODE: print("[NEPAL-MOUNT] _mount_nepal_knife_world_model 开始, def=", def.id if def != null else "null")
	if inst.get_parent() != null:
		inst.get_parent().remove_child(inst)
	inst.queue_free()
	var skel_n: Skeleton3D = null
	for n in character_visual.find_children("*", "Skeleton3D", true, false):
		skel_n = n as Skeleton3D
		break
	if skel_n != null and skel_n.find_bone(NEPAL_KNIFE_BONE) >= 0:
		if DEBUG_MODE: print("[NEPAL-MOUNT] 找到右手骨骼，创建 BoneAttachment3D")
		var ba := BoneAttachment3D.new()
		ba.name = "NepalKnifeBone"
		ba.bone_name = NEPAL_KNIFE_BONE
		skel_n.add_child(ba)
		_nepal_knife_attach = ba
		# 【挥刀兼容·同步接管】切刀瞬间立即让 WeaponRig 停止每帧握持跟随，
		# 不能等异步挂刀完成（2~4 帧后才设 skip_follow）：
		# 窗口期内 WeaponRig 仍用 AK47 握把锚点覆盖手部骨骼 → 切刀后立刻挥刀/
		# 移动时手被拉回持枪姿态（视觉错乱）、双手连线被拉歪 → torso 俯仰轴歪。
		if _weapon_rig != null:
			_weapon_rig.skip_follow = true
		# 异步：等预览场景的 22° 抬臂待机合成播放几帧后再读取骨骼姿态，保证绑定正确
		# 【崩溃修复】改用帧计数状态机（无协程）：先递增代际使上一轮 pending（若有）作废，
		# 再注册新一轮 pending —— _physics_process 每帧轮询推进，彻底杜绝协程 await 恢复崩溃。
		_nepal_mount_generation += 1
		_nepal_mount_pending = [0, _nepal_mount_generation, skel_n, ba, def, null, 0]
		if DEBUG_MODE: print("[NEPAL-MOUNT] 注册挂载 pending gen=", _nepal_mount_generation)
	else:
		# 退化：无右手骨骼，挂固定摆位
		var fb := load("res://resources/models/nepal/nepal_knife.glb").instantiate() as Node3D
		if fb != null:
			character_visual.add_child(fb)
			fb.transform = Transform3D(Basis.IDENTITY, Vector3(0, 1.2, 0.6))
			_nepal_knife = fb
			_weapon_holder = fb
			_dynamic_world_model = fb
			if _weapon_rig != null:
				_weapon_rig.skip_follow = true
			_apply_weapon_fp_shadow(_fp_mode)
			debug_print("3P 尼泊尔刀: 无右手骨骼，退化为固定摆位")

## 【WYSIWYG·直读编辑器】运行时加载预览场景(nepal_knife_preview.tscn)里用户调好的 Knife 子树，
## 用与预览 _bind_handle_to_palm 完全一致的公式算成"相对右手骨骼的局部 transform"挂到 ba 上。
## 因绑定依赖"22° 抬臂待机"下的骨骼姿态，需等预览场景的待机合成播放几帧后再读取，故为异步
## （刀在 2~3 帧后挂载，视觉无感）。编辑器怎么调，游戏就怎么显示，重调也自动生效。
func _process_nepal_mount_pending() -> void:
	# 【崩溃修复·治本】尼泊尔刀挂载帧计数状态机。
	# 历史：协程版（await）与状态机版（load 预览场景）都在用户实机（Vulkan Forward+）
	# 切刀时 SIGSEGV 崩溃。用户日志 backtrace 精确指向 load(NEPAL_PREVIEW_SCENE) 一行：
	#   [0] _process_nepal_mount_pending (player.gd:1724) = load()
	# 预览场景 nepal_knife_preview.tscn 内嵌整个 character.tscn（2.1MB），运行时加载它在
	# 用户机器上与游戏侧已实例化的 character.tscn（main.tscn 内嵌）冲突崩溃。
	# 而预览场景只是【编辑器标定工具】——标定结果已写死为 NEPAL_KNIFE_LOCAL_POS/ROT/SCALE
	# 常量（相对飞虎队右手骨骼的局部 transform，编辑器打印值）。
	# 【治本】运行时永不加载预览场景：等 2 帧抬臂待机生效后，直接用
	#   ngal_knife.glb（422KB，退化分支已用，从不崩）+ 标定常量挂载。
	if _nepal_mount_pending.is_empty():
		return
	var step: int = _nepal_mount_pending[0]
	var gen: int = _nepal_mount_pending[1]
	# 先取弱引用并检查有效性，再强转为类型变量（避免 freed 对象上赋值/强转报错）
	var skel_raw = _nepal_mount_pending[2]
	var ba_raw = _nepal_mount_pending[3]
	var wait: int = _nepal_mount_pending[6]
	# 代际失效：期间又切了武器/释放了动态实例，放弃本 pending
	if gen != _nepal_mount_generation:
		if DEBUG_MODE: print("[NEPAL-MOUNT] 代际失效 gen=", gen, " 当前=", _nepal_mount_generation, "，放弃 pending")
		_nepal_mount_pending = []
		return
	# 挂载对象已释放：放弃
	if not is_instance_valid(skel_raw) or (ba_raw != null and not is_instance_valid(ba_raw)):
		if DEBUG_MODE: print("[NEPAL-MOUNT] skel/ba 已释放，放弃 pending")
		_nepal_mount_pending = []
		return
	var skel: Skeleton3D = skel_raw as Skeleton3D
	var ba: Node3D = ba_raw as Node3D
	if step == 0:
		# 等 2 帧让抬臂待机动画生效（骨骼姿态落到 22° 抬臂位）
		wait += 1
		if wait >= 2:
			step = 1
			wait = 0
	if step == 1:
		# 【治本】不加载预览场景。用标定源常量（Kw + HandleMarker）+ 当前骨骼实时姿态
		# 按预览 _bind_handle_to_palm 完全一致的公式计算 L，直接挂载 nepal_knife.glb。
		# 不用 k 纯缩放换算：SWAT/飞虎队骨骼姿态有旋转差（Hips 差 ~86°），纯 k 换算
		# 会导致 SWAT 下刀位偏移（用户实测）。用骨骼实时姿态算 L 自动适配任意角色骨架。
		var sub: Node3D = load("res://resources/models/nepal/nepal_knife.glb").instantiate() as Node3D
		if sub == null:
			push_warning("尼泊尔刀: nepal_knife.glb 加载失败")
			_nepal_mount_pending = []
			return
		# 【移动切刀漂移修复】不采样运行时骨骼姿态算 L（移动/跑动中骨骼姿态随动画
		# 变化，每次切刀采样时刻不同 → L 不同 → 刀位每次切刀都变）。
		# 【每角色标定资源】L 来自该角色的标定 tres（标定场景
		# scenes/nepal_knife_calib.tscn 拖拽保存，见 _get_nepal_knife_local）——
		# 每角色直接标定自己的右手骨骼局部系，彻底移除 k 跨角色换算
		# （k 假设两骨架纯缩放，实测 SWAT 骨骼姿态有旋转差 → 纯 k 会偏移）。
		# 刀挂 BoneAttachment3D 后每帧跟骨骼走，L 固定 → 任意姿态下刀位恒定。
		var L: Transform3D = _get_nepal_knife_local()
		sub.transform = L
		if ba == null or not is_instance_valid(ba):
			sub.queue_free()
			_nepal_mount_pending = []
			return
		ba.add_child(sub)
		_nepal_knife = sub
		if DEBUG_MODE: print("[NEPAL-MOUNT] 挂载完成（固定L·k换算）L=", L.origin, " scale=", L.basis.get_scale())
		# 收尾：隐藏标注球、接管 weapon_holder、跳过 WeaponRig 跟手、设阴影
		for gp_name in ["GripPoint_RH", "GripPoint_LH", "GripPoint_Elbow_RH",
						"GripPoint_Muzzle", "GripPoint_Butt", "GripPoint_GunGrip", "MarkerBall"]:
			var gp = sub.find_child(gp_name, true, false)
			if gp != null:
				gp.visible = false
		if _weapon_holder != null:
			_weapon_holder.visible = false
		_weapon_holder = sub
		_dynamic_world_model = sub
		if _weapon_rig != null:
			_weapon_rig.skip_follow = true
		_apply_weapon_fp_shadow(_fp_mode)
		debug_print("3P 尼泊尔刀(固定L·k换算): 已挂右手骨骼 %s" % NEPAL_KNIFE_BONE)
		_nepal_mount_pending = []
		return
	_nepal_mount_pending = [step, gen, skel, ba, null, null, wait]

## 手雷 3P 世界模型挂载（BoneAttachment3D 绑右手骨骼，仿尼泊尔刀流程）。
## 模型 = grenade_world.glb（纯手雷，无手），挂 mixamorig_RightHand 后随手臂动画走
## （拉环/投掷直驱时手雷跟手）。标定 transform 每角色 calib tres（duck-type 读）。
## ⚠️【不缓存】标定文件可能被编辑器改动——若用 _grenade_calib_cache 缓存，
## 游戏运行中改了标定会命中旧值（用户实测"保存了但位置没变"）。每次 CACHE_MODE_REPLACE
## 强制读盘，切一次武器即生效，无需重启游戏。
func _get_grenade_local() -> Transform3D:
	var char_id: String = ""
	if char_manager != null and char_manager.get_active_asset() != null:
		char_id = char_manager.get_active_asset().id
	var path: String = GRENADE_CALIB_PATHS.get(char_id, "")
	if path != "" and ResourceLoader.exists(path):
		var loaded = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
		if loaded != null:
			return Transform3D(Basis(loaded.local_rot).scaled(loaded.local_scale), loaded.local_pos)
		if char_id != "":
			push_warning("手雷: 角色 %s 标定资源加载失败，回退默认摆位" % char_id)
	else:
		if char_id != "":
			push_warning("手雷: 角色 %s 无标定资源，回退默认摆位（请用标定场景微调）" % char_id)
	return _grenade_default_local()

## 手雷默认摆位（无 calib tres 时回退）：按 feihu 实测估算——
## ⚠️【高危易错】手雷挂在角色骨架下，世界长轴必须【逐层相乘】，缺一项就看不见：
##   世界长轴 = raw长轴 11.5032 × GLB内mesh节点scale 0.0254 × local_scale × Armature缩放
##   其中 0.0254 是 grenade_world.glb 的 MeshInstance3D 节点自带缩放（Blender 导出时
##   Armature=0.0254 残留），在节点树里显示为子节点 scale，肉眼极易漏算，必须实测
##   （tools/probe_grenade_raw.gd / probe_grenade_scale.gd）。
##   feihu Armature≈0.00026 → local_scale / 13163.6 = 世界长轴(米)。
## 本坑已踩两次：① 0.0087（按 1:1 空间算）→ 0.02mm 不可见；② 37.8（漏乘 0.0254）→ 2.9mm 不可见。
## ⚠️【跨角色别比 local_scale 数值】feihu/swat 骨架缩放差 53.06 倍，
##   feihu_scale = swat_scale × 53.06 才等价。当前两角色标定均按"世界长轴≈0.3225m"
##   （用户在标定场景里定下的观感尺寸，比真实手雷 10cm 夸张）：feihu 4245.27 / swat 80。
## ⚠️【scale 与 pos 必须成对改】几何中心偏移与 scale 成正比，只放大 scale 不改 pos
##   手雷会飘离手掌（实测只改 scale → 中心跑到手腕外 59cm）。
## 标定场景 scenes/grenade_calib.tscn 调准后存 tres，本函数仅兜底。
func _grenade_default_local() -> Transform3D:
	const S := 4245.2682
	var rot: Quaternion = Quaternion(Vector3(0.0, 0.0, 1.0), Vector3(0.0, -1.0, 0.0))
	var pos := Vector3(-1079.1437, 2308.8135, -796.2861)
	return Transform3D(Basis(rot).scaled(Vector3.ONE * S), pos)

func _mount_grenade_world_model(def: WeaponDef, inst: Node3D) -> void:
	if DEBUG_MODE: print("[GRENADE-MOUNT] _mount_grenade_world_model 开始, def=", def.id if def != null else "null")
	if inst.get_parent() != null:
		inst.get_parent().remove_child(inst)
	inst.queue_free()
	var skel_n: Skeleton3D = null
	for n in character_visual.find_children("*", "Skeleton3D", true, false):
		skel_n = n as Skeleton3D
		break
	if skel_n != null and skel_n.find_bone(GRENADE_MODEL_BONE) >= 0:
		var ba := BoneAttachment3D.new()
		ba.name = "GrenadeBone"
		ba.bone_name = GRENADE_MODEL_BONE
		skel_n.add_child(ba)
		_grenade_attach = ba
		# 【WeaponRig 让路】手雷挂右手骨骼由动画驱动（待机合成/拉环直驱），
		# WeaponRig 是枪械右手握持逻辑，会污染手雷 transform → 全程 skip_follow=true
		# （换装时 2167 统一设置，_stop_grenade_arms 不再恢复 false）。
		if _weapon_rig != null:
			_weapon_rig.skip_follow = true
		# 异步帧状态机：等 2 帧让待机合成（22° 抬臂）生效后再读标定挂载
		_grenade_mount_generation += 1
		_grenade_mount_pending = [0, _grenade_mount_generation, skel_n, ba, 0]
	else:
		# 退化：无右手骨骼，挂固定摆位（胸前）
		var fb := load(GRENADE_MODEL_PATH).instantiate() as Node3D
		if fb != null:
			character_visual.add_child(fb)
			fb.transform = Transform3D(Basis.IDENTITY, Vector3(0, 1.2, 0.5))
			_grenade_model = fb
			_weapon_holder = fb
			_dynamic_world_model = fb
			if _weapon_rig != null:
				_weapon_rig.skip_follow = true
			_apply_weapon_fp_shadow(_fp_mode)
			debug_print("3P 手雷: 无右手骨骼，退化为固定摆位")

## 手雷挂载帧状态机（_physics_process 每帧轮询，无协程——仿尼泊尔刀防崩溃方案）。
func _process_grenade_mount_pending() -> void:
	if _grenade_mount_pending.is_empty():
		return
	var step: int = _grenade_mount_pending[0]
	var gen: int = _grenade_mount_pending[1]
	var skel_raw = _grenade_mount_pending[2]
	var ba_raw = _grenade_mount_pending[3]
	var wait: int = _grenade_mount_pending[4]
	if gen != _grenade_mount_generation:
		_grenade_mount_pending = []
		return
	if not is_instance_valid(skel_raw) or (ba_raw != null and not is_instance_valid(ba_raw)):
		_grenade_mount_pending = []
		return
	var skel: Skeleton3D = skel_raw as Skeleton3D
	var ba: Node3D = ba_raw as Node3D
	if step == 0:
		wait += 1
		if wait >= 2:
			step = 1
			wait = 0
	if step == 1:
		var sub: Node3D = load(GRENADE_MODEL_PATH).instantiate() as Node3D
		if sub == null:
			push_warning("手雷: grenade_world.glb 加载失败")
			_grenade_mount_pending = []
			return
		var L: Transform3D = _get_grenade_local()
		sub.transform = L
		if ba == null or not is_instance_valid(ba):
			sub.queue_free()
			_grenade_mount_pending = []
			return
		ba.add_child(sub)
		_grenade_model = sub
		if DEBUG_MODE: print("[GRENADE-MOUNT] 挂载完成 L=", L.origin, " scale=", L.basis.get_scale())
		if _weapon_holder != null:
			_weapon_holder.visible = false
		_weapon_holder = sub
		_dynamic_world_model = sub
		if _weapon_rig != null:
			_weapon_rig.skip_follow = true
		_apply_weapon_fp_shadow(_fp_mode)
		debug_print("3P 手雷: 已挂右手骨骼 %s" % GRENADE_MODEL_BONE)
		_grenade_mount_pending = []
		return
	_grenade_mount_pending = [step, gen, skel, ba, wait]

## 释放上一角色/上一把武器留下的动态 3P 实例（切换回内嵌角色或换武器前调用）。
## 仅释放由本类动态创建的实例，内嵌 Weapon_AK47 不受影响；失败路径静默跳过。
func _free_dynamic_world_model() -> void:
	# 【崩溃修复】释放动态 3P 实例时递增代际：使正在 await 的尼泊尔刀挂载协程
	# 在下次恢复时立即放弃（否则它可能继续 load/实例化预览场景，与下一次切刀协程并发）。
	_nepal_mount_generation += 1
	# 【手雷】同尼泊尔：挂点连带释放手雷本体，先摘引用再置空，严禁二次 free
	_grenade_mount_generation += 1
	var gmod: Node3D = _grenade_model
	if _grenade_attach != null and is_instance_valid(_grenade_attach):
		var gba: Node3D = _grenade_attach
		if gba.get_parent() != null:
			gba.get_parent().remove_child(gba)
		gba.queue_free()
	_grenade_attach = null
	_grenade_model = null
	if gmod != null:
		if _dynamic_world_model == gmod:
			_dynamic_world_model = null
		if _weapon_holder == gmod:
			_weapon_holder = null
	# 【尼泊尔·崩溃修复】刀挂在 BoneAttachment3D 下 → 释放挂点会连带释放刀本体。
	# 但 _dynamic_world_model 与 _weapon_holder 都指向【同一把刀】，若继续走下面的
	# remove_child + queue_free，会把已排队释放的子节点摘成孤儿再二次 free
	# ——这正是"切到刀再切枪直接崩溃"的根因。先摘引用，再统一置空。
	var knife: Node3D = _nepal_knife
	if _nepal_knife_attach != null and is_instance_valid(_nepal_knife_attach):
		var ba: Node3D = _nepal_knife_attach
		if ba.get_parent() != null:
			ba.get_parent().remove_child(ba)   # 立即脱离骨架，旧刀不会多存活一帧
		ba.queue_free()                        # 子节点（刀）随挂点一并释放
	_nepal_knife_attach = null
	_nepal_knife = null
	if knife != null:
		# 刀已随挂点释放：清掉全部别名引用，严禁再次 free
		if _dynamic_world_model == knife:
			_dynamic_world_model = null
		if _weapon_holder == knife:
			_weapon_holder = null
	if _dynamic_world_model != null and is_instance_valid(_dynamic_world_model):
		if _weapon_holder == _dynamic_world_model:
			_weapon_holder = null              # 同一实例的别名，先断开再释放
		if _dynamic_world_model.get_parent() != null:
			_dynamic_world_model.get_parent().remove_child(_dynamic_world_model)
		_dynamic_world_model.queue_free()
	_dynamic_world_model = null
	# 动态实例已全部释放：把 _weapon_holder 拉回内嵌 Weapon_AK47，
	# 否则它悬空，切回 AK47 时访问 .visible 会崩（freed instance）。
	_revalidate_weapon_holder()

## 【崩溃修复】校验 _weapon_holder 是否仍是有效实例：
## 它会被动态武器实例覆盖（_weapon_holder = inst），实例释放后引用悬空，
## 任何 .visible / find_children 访问都会触发 "previously freed instance" 崩溃。
## 无效时重新解析当前角色视觉下的内嵌 Weapon_AK47；找不到则保持 null（调用方均判空）。
func _revalidate_weapon_holder() -> void:
	if _weapon_holder != null and is_instance_valid(_weapon_holder):
		return
	_weapon_holder = null
	if character_visual == null:
		return
	var emb: Node3D = character_visual.find_child("Weapon_AK47", true, false) as Node3D
	if emb != null:
		_weapon_holder = emb

## 模型网格几何中心（相对模型自身原点，米）：直接合并各 mesh.get_aabb()（本地空间），
## 再乘 Armature 节点 scale（gltf 网格坐标常是原始英寸，Armature 0.0254 缩放才成米）。
func _mesh_center_local(model: Node3D) -> Vector3:
	if model == null:
		return Vector3.ZERO
	var comb := AABB()
	var have := false
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m == null or m.mesh == null:
			continue
		if not have:
			comb = m.get_aabb()
			have = true
		else:
			comb = comb.merge(m.get_aabb())
	if not have:
		return Vector3.ZERO
	var s: float = _armature_scale(model)
	return comb.get_center() * s

## 单网格的世界空间 AABB 中心（8 角点经 global_transform expand 后取中心；用于 AK47 参照枪）
func _mesh_world_center(m: MeshInstance3D) -> Vector3:
	if m == null or m.mesh == null:
		return Vector3.ZERO
	var la: AABB = m.get_aabb()
	var gt: Transform3D = m.global_transform
	var box := AABB()
	var have := false
	for xi in [0, 1]:
		for yi in [0, 1]:
			for zi in [0, 1]:
				var wp: Vector3 = gt * (la.position + Vector3(la.size.x * xi, la.size.y * yi, la.size.z * zi))
				if not have:
					box.position = wp
					box.size = Vector3.ZERO
					have = true
				else:
					box = box.expand(wp)
	return box.get_center()

## 模型网格本地长轴方向（单位向量）：直接合并各 mesh.get_aabb()（本地空间，不依赖
## global_transform 刷新时序），取最长轴（X/Y/Z）。用于 3P 动态枪自动对齐前向。
func _mesh_long_axis_local(model: Node3D) -> Vector3:
	if model == null:
		return Vector3.FORWARD
	var comb := AABB()
	var have := false
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m == null or m.mesh == null:
			continue
		if not have:
			comb = m.get_aabb()
			have = true
		else:
			comb = comb.merge(m.get_aabb())
	if not have:
		return Vector3.FORWARD
	var sz: Vector3 = comb.size
	if sz.x >= sz.y and sz.x >= sz.z:
		return Vector3.RIGHT
	elif sz.y >= sz.z:
		return Vector3.UP
	return Vector3.FORWARD

## Armature 节点缩放（gltf 网格坐标 → 米）：找模型下 Armature 的 scale（通常 0.0254）。
func _armature_scale(model: Node3D) -> float:
	if model == null:
		return 1.0
	var arm: Node3D = model.find_child("Armature", true, false) as Node3D
	if arm != null:
		return arm.scale.x if arm.scale.x > 0.0 else 1.0
	return 1.0

## 枪口方向（模型本地系，单位向量）：找 MDL 的 flash 骨骼（=枪口闪光点），
## 取其 world 位置 - 网格中心 = 枪口指向。找不到 flash 返回 ZERO（调用方兜底）。
func _muzzle_dir_local(model: Node3D, center: Vector3) -> Vector3:
	if model == null:
		return Vector3.ZERO
	var skel: Skeleton3D = model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null:
		return Vector3.ZERO
	var flash_idx: int = -1
	for i in range(skel.get_bone_count()):
		if "flash" in skel.get_bone_name(i).to_lower():
			flash_idx = i
			break
	if flash_idx < 0:
		return Vector3.ZERO
	var flash_world: Vector3 = skel.global_transform * skel.get_bone_global_pose(flash_idx).origin
	return flash_world - center

## 模型网格本地"次长轴"方向（UP 参考）：长轴之外的轴中较长者，用于枪身滚转对齐。
func _mesh_up_local(model: Node3D) -> Vector3:
	if model == null:
		return Vector3.UP
	var comb := AABB()
	var have := false
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m == null or m.mesh == null:
			continue
		if not have:
			comb = m.get_aabb()
			have = true
		else:
			comb = comb.merge(m.get_aabb())
	if not have:
		return Vector3.UP
	var sz: Vector3 = comb.size
	var long_axis := _mesh_long_axis_local(model)
	if long_axis == Vector3.RIGHT:
		return Vector3.UP if sz.y >= sz.z else Vector3.FORWARD
	elif long_axis == Vector3.UP:
		return Vector3.RIGHT if sz.x >= sz.z else Vector3.FORWARD
	else:  # 长轴 Z
		return Vector3.UP if sz.y >= sz.x else Vector3.RIGHT

# ============================================================
# 预缓存所有动画引用（启动时加载，减少运行时开销）
# ============================================================
func _cache_animations():
	if anim_player == null:
		return
	for state in AnimState.values():
		var anim_name: String = _anim_name_for(state)
		if anim_name != "" and anim_player.has_animation(anim_name):
			_anim_cache[state] = anim_player.get_animation(anim_name)

## 【P2 抽取】动画库后处理（原 _ready 内流程）：
## 1. 预缓存动画引用；2. 移除循环动画的位置轨道（否则 Mixamo Hips 位置
## 在错误坐标系 → 骨骼位置跳变/蹲姿双重下压陷地）；3. 换弹回位尾巴；
## 4. 合成换弹+行走变体；5. 更新换弹固定时长。
## 角色切换换库后必须重做——新角色的动画库（如 mixamo_lib_swat.tres）
## 的 position 轨道从未被剥离，直接播放会导致蹲姿 Hips 被动画值+视觉下压
## 双重压低（实测 Hips=-0.2m，大半个身子陷地）。
## 【架构根治·copy-on-write】把共享动画库复制为 player 私有副本。
## 病灶：asset.anim_lib（mixamo_lib.tres / mixamo_lib_swat.tres）是两角色 +
## preview 场景共用的共享 .tres；后续后处理（移除 position 轨道 / 换弹回位尾巴 /
## 合成换弹变体 / 尼泊尔与手枪合成）全部直接 mutate 共享动画对象 →
## "改飞虎队动画→污染共享库→SWAT/preview 也坏"（修好 A 坏 B 的根因）。
## 本函数在首次 mutate 前把主库("")逐动画 deep-duplicate 成私有副本，
## 后续 mutate 只作用于私有副本，.tres 本体永不污染。
func _make_anim_library_private() -> void:
	if anim_player == null or not is_instance_valid(anim_player):
		return
	var src_lib := anim_player.get_animation_library("")
	if src_lib == null:
		return
	var private_lib := AnimationLibrary.new()
	for aname in src_lib.get_animation_list():
		var a: Animation = src_lib.get_animation(aname)
		if a != null:
			private_lib.add_animation(aname, a.duplicate(true))
	anim_player.remove_animation_library("")
	anim_player.add_animation_library("", private_lib)
	# 复制后旧引用全部失效：清缓存 + 判重字典，让后续重新缓存私有副本
	_anim_cache.clear()
	_reload_tail_applied.clear()

func _post_process_anim_library() -> void:
	# 【架构根治·copy-on-write】必须先复制再缓存：否则 _cache_animations 缓存的是
	# 共享引用，后续 mutate 仍会污染 .tres 本体。
	_make_anim_library_private()
	# 预缓存所有动画引用（避免运行时重复查找，提升性能）
	_cache_animations()
	# 调试模式：打印动画轨道信息
	if DEBUG_MODE:
		_print_all_animation_track_info()
		_log_jump_anim_frames()
	# 移除循环动画中的位置关键帧（避免骨骼位置跳变导致闪现）
	_remove_position_tracks_from_looping_anims()
	# 换弹动画"回位尾巴"（动画层根治）：换弹动画末帧双手往往未完全回到站姿待机
	# 位，直接切换会跳。这里给 Reloading 动画末尾追加一段过渡，把末帧平滑过渡到
	# IDLE_AIM（站姿待机）首帧姿态——换弹结束瞬间枪/手已在待机位，无缝衔接。
	# 换弹动画被延长 RELOAD_RECOVERY_DUR，换弹固定时长（_reload_duration）随之更新。
	# 【顺序关键】必须在 _combine_animations() 之前执行：换弹+行走变体（走路/蹲姿换弹）
	# 以上半身取自 Reloading，先加尾巴再合成 ⇒ 变体同样包含回位尾巴、长度与
	# RELOADING 一致（3.85s），保证站姿/走路换弹速度统一（speed 相同）、结束时
	# 上半身都回位无跳变。若顺序颠倒，变体长度=3.5s（无尾巴）⇒ 同一换弹动作在
	# 站姿(1.39x)与走路(1.26x)速度不一致（用户反馈"走路换弹和站姿换弹不一样"）。
	_append_reload_recovery()
	# 合成换弹+行走混合动画（上下半身分离）
	_combine_animations()
	# 记录换弹固定时长（以 Reloading 动画长度为准，作为换弹状态机计时基准）
	var _reload_src = _get_cached_animation(AnimState.RELOADING)
	if _reload_src:
		_reload_duration = _reload_src.length
		_reload_anim_len = _reload_src.length
	# 调试模式：验证移除后轨道信息
	if DEBUG_MODE:
		_verify_animation_tracks()

# ============================================================
# 换弹动画"回位尾巴"（动画层根治换弹结束跳变）
# 在 Reloading 动画末尾追加 RELOAD_RECOVERY_DUR 秒过渡段：每根骨骼轨道从
# "换弹末帧值"插值到"站姿待机(IDLE_AIM)首帧值"，动画结束时姿态=待机首帧，
# 切换回待机零跳变。换弹动画被延长，_reload_duration 随之更新（已在调用方重新取）。
# 目标值取 idle 同轨道 key0（idle 无该轨道则用 rest——与 idle 播放时行为一致；
# 注意 idle 是循环动画，位置轨道可能已被 _remove_position_tracks 剥离）。
# ============================================================
# 回位过渡时长（秒）：换弹末帧双手到待机首帧的过渡动画长度。
const RELOAD_RECOVERY_DUR := 0.35
## 【P2 修复】已追加过"回位尾巴"的 Reloading 动画对象（防重入）。
## 角色切换会重走 _post_process_anim_library → _append_reload_recovery，
## 而 anim_player.get_animation 返回的是同一个【共享】Animation 对象——
## 若不判重，每次切换都再追加 0.35s 尾巴，长度 3.5→3.85→4.2→4.55 无限膨胀，
## _reload_duration 随之变长 → 换弹像慢动作。
var _reload_tail_applied: Dictionary = {}
func _append_reload_recovery() -> void:
	var reload := _get_cached_animation(AnimState.RELOADING)
	var idle := _get_cached_animation(AnimState.IDLE_AIM)
	if reload == null or idle == null:
		return
	# 【P2 修复】防重入：同一动画对象只加一次尾巴
	if _reload_tail_applied.has(reload):
		return
	_reload_tail_applied[reload] = true
	var skel := character_visual.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null:
		return
	var body_end: float = reload.length
	var tail_time := body_end + RELOAD_RECOVERY_DUR
	for t in reload.get_track_count():
		var sp := str(reload.track_get_path(t))
		var kc: int = reload.track_get_key_count(t)
		if kc == 0:
			continue
		var target: Variant
		var idle_t := -1
		for it in idle.get_track_count():
			if str(idle.track_get_path(it)) == sp and idle.track_get_type(it) == reload.track_get_type(t):
				idle_t = it
				break
		if idle_t >= 0:
			target = idle.track_get_key_value(idle_t, 0)
		else:
			var bone_name := sp.substr(sp.rfind(":") + 1)
			var bi := skel.find_bone(bone_name)
			if bi < 0:
				continue
			var rest := skel.get_bone_rest(bi)
			match reload.track_get_type(t):
				Animation.TYPE_POSITION_3D:
					target = rest.origin
				Animation.TYPE_ROTATION_3D:
					target = rest.basis.get_rotation_quaternion()
				Animation.TYPE_SCALE_3D:
					target = rest.basis.get_scale()
				_:
					continue
		var last_time: float = reload.track_get_key_time(t, kc - 1)
		if last_time < body_end - 0.001:
			reload.track_set_key_time(t, kc - 1, body_end)
		reload.track_insert_key(t, tail_time, target)
		reload.track_set_interpolation_type(t, Animation.INTERPOLATION_LINEAR)
	reload.length = tail_time

# ============================================================
# 获取缓存的动画对象（优先从缓存读取）
# ============================================================
func _get_cached_animation(state: AnimState) -> Animation:
	if _anim_cache.has(state):
		return _anim_cache[state]
	var anim_name: String = _anim_name_for(state)
	if not anim_name.is_empty() and anim_player.has_animation(anim_name):
		var anim = anim_player.get_animation(anim_name)
		_anim_cache[state] = anim
		return anim
	return null

# 采样动画在 t 时刻指定骨骼的骨架空间全局姿态（与编辑器预览姿态一致）
# 注意：动画对象的位置轨道已由 _remove_position_tracks 剥离（除双肩），
# 故 local_pos 默认取 rest，与运行时行为一致。
func _sample_anim_bone_pose(anim: Animation, t: float, bone_idx: int) -> Transform3D:
	if _weapon_skel == null or bone_idx < 0:
		return Transform3D.IDENTITY
	var local_pos := {}
	var local_rot := {}
	for i in range(_weapon_skel.get_bone_count()):
		var rest: Transform3D = _weapon_skel.get_bone_rest(i)
		local_pos[i] = rest.origin
		local_rot[i] = Quaternion(rest.basis.orthonormalized())
	for track in range(anim.get_track_count()):
		var p := String(anim.track_get_path(track))
		var colon := p.rfind(":")
		if colon < 0 or not p.contains("Skeleton3D"):
			continue
		var idx := _weapon_skel.find_bone(p.substr(colon + 1))
		if idx < 0:
			continue
		if anim.track_get_type(track) == Animation.TYPE_ROTATION_3D:
			var r: Variant = _sample_anim_track(anim, track, t)
			if r != null:
				local_rot[idx] = r
		elif anim.track_get_type(track) == Animation.TYPE_POSITION_3D:
			var q: Variant = _sample_anim_track(anim, track, t)
			if q != null:
				local_pos[idx] = q
	var hips_i := _weapon_skel.find_bone("mixamorig_Hips")
	if hips_i < 0:
		push_error("角色 %s 缺少 mixamorig_Hips 骨，_sample_anim_bone_pose 程序化叠加被跳过" % (character_visual.name if character_visual != null else "?"))
		return Transform3D.IDENTITY
	var poses := {}
	poses[hips_i] = Transform3D(Basis(local_rot[hips_i]), local_pos[hips_i])
	var queue: Array[int] = [hips_i]
	while not queue.is_empty():
		var parent: int = queue.pop_front()
		var pg: Transform3D = poses[parent]
		for i in range(_weapon_skel.get_bone_count()):
			if _weapon_skel.get_bone_parent(i) == parent:
				poses[i] = pg * Transform3D(Basis(local_rot[i]), local_pos[i])
				queue.push_back(i)
	return poses.get(bone_idx, Transform3D.IDENTITY)

func _sample_anim_track(anim: Animation, track: int, t: float) -> Variant:
	var n := anim.track_get_key_count(track)
	if n == 0:
		return null
	var is_rot := anim.track_get_type(track) == Animation.TYPE_ROTATION_3D
	for i in range(n):
		if absf(anim.track_get_key_time(track, i) - t) < 0.0005:
			return anim.track_get_key_value(track, i)
	var i0 := 0
	while i0 < n and anim.track_get_key_time(track, i0) < t:
		i0 += 1
	if i0 == 0:
		return anim.track_get_key_value(track, 0)
	if i0 >= n:
		return anim.track_get_key_value(track, n - 1)
	var t0: float = anim.track_get_key_time(track, i0 - 1)
	var t1: float = anim.track_get_key_time(track, i0)
	var w: float = clampf((t - t0) / maxf(t1 - t0, 1e-6), 0.0, 1.0)
	var v0: Variant = anim.track_get_key_value(track, i0 - 1)
	var v1: Variant = anim.track_get_key_value(track, i0)
	if is_rot:
		return (v0 as Quaternion).slerp(v1 as Quaternion, w)
	return (v0 as Vector3).lerp(v1 as Vector3, w)

# ============================================================
# 计算标准化动画播放速度
# 不同方向的动画长度不同，用参考长度标准化后，
# 使所有方向的动画在相同移动速度下播放频率一致
# ============================================================
func _get_normalized_anim_speed(state: AnimState, horizontal_speed: float, max_speed: float, reference_len: float) -> float:
	# 【修复】上限随能力倍率放宽：普通行走上限 1.5 不变；冲刺爆发(2x)时允许到 3.0，
	# 否则腿部动画步频被 clamp 卡死 → 太空步（速度×2 腿速×1.5）
	var speed_ratio: float = clamp(horizontal_speed / max_speed, 0.3, 1.5 * _ability_speed_mult)
	var anim = _get_cached_animation(state)
	if anim and anim.length > 0.01:
		# 标准化：长动画需加速播放，短动画需减速播放，使所有方向步频一致
		# 修正倍率 = 该动画时长 / 参考时长（长动画 > 1.0 = 加速，短动画 < 1.0 = 减速）
		speed_ratio *= anim.length / reference_len
	return speed_ratio

# ============================================================
# 启动时打印所有动画的轨道信息
# ============================================================
func _print_all_animation_track_info():
	if not DEBUG_MODE:
		return
	var names: Array = []
	for state in AnimState.values():
		var n: String = _anim_name_for(state)
		if not n.is_empty():
			names.append(n)
	AnimationDiagnostics.print_all_animation_track_info(anim_player, names)

func _verify_animation_tracks():
	if not DEBUG_MODE:
		return
	AnimationDiagnostics.verify_position_tracks_removed(
		anim_player, _anim_names_for(POSITION_TRACK_STRIP_STATES)
	)

func _log_jump_anim_frames():
	if not DEBUG_MODE:
		return
	AnimationDiagnostics.log_jump_anim_frames(
		anim_player,
		_anim_names_for([AnimState.JUMP_UP, AnimState.JUMP_DOWN, AnimState.JUMP_FORWARD])
	)

func _remove_position_tracks_from_looping_anims():
	debug_print(">>>> 开始移除位置轨道...")
	# 所有动画移除所有位置轨道
	# Mixamo FBX 的 Hips 位置轨道值在错误的坐标系中（~80-15000 vs rest pose ~6900），
	# 保留会导致Hips位置错误。蹲姿高度由 _crouch_visual_offset() 动态控制。
	# 例外：Death 动画刻意保留位置轨道（不在下方 target_states 中），
	# 用于播放完整的倒地位移；若希望尸体不位移，可将其加入 target_states。
	var target_states = [
		AnimState.IDLE_AIM,
		AnimState.WALK_FORWARD,
		AnimState.WALK_BACKWARD,
		AnimState.STRAFE_LEFT,
		AnimState.STRAFE_RIGHT,
		AnimState.CROUCH_IDLE_AIM,
		AnimState.CROUCH_WALK_FORWARD,
		AnimState.CROUCH_WALK_BACKWARD,
		AnimState.CROUCH_STRAFE_LEFT,
		AnimState.CROUCH_STRAFE_RIGHT,
		AnimState.STAND_TO_CROUCH,
		AnimState.CROUCH_TO_STAND,
		AnimState.HIT_REACTION,
		AnimState.TOSS_GRENADE,
		AnimState.RUN,
		AnimState.CROUCH_HIT_BACK,
		AnimState.RELOADING,
		AnimState.RELOAD_WALK_FORWARD,
		AnimState.RELOAD_WALK_BACKWARD,
		AnimState.RELOAD_STRAFE_LEFT,
		AnimState.RELOAD_STRAFE_RIGHT,
		AnimState.RELOAD_CROUCH_WALK_FORWARD,
		AnimState.RELOAD_CROUCH_WALK_BACKWARD,
		AnimState.RELOAD_CROUCH_STRAFE_LEFT,
		AnimState.RELOAD_CROUCH_STRAFE_RIGHT,
		AnimState.RELOAD_CROUCH_IDLE,
		AnimState.RELOAD_STAND_TO_CROUCH,
		AnimState.RELOAD_CROUCH_TO_STAND,
		# 跳跃动画
		# 保留会导致角色在动画播放期间位置闪现/悬空。
		# 角色物理位置由 CharacterBody3D 控制，动画只负责视觉姿态。
		AnimState.JUMP_UP,
		AnimState.JUMP_DOWN,
		AnimState.JUMP_FORWARD,
	]
	
	var total_removed: int = 0
	for state in target_states:
		var anim_name: String = _anim_name_for(state)
		if anim_name.is_empty():
			continue
		if not anim_player.has_animation(anim_name):
			# 预期情况：合成动画（Reloading Walk/Strafe/Crouch 系列）由 _combine_animations()
			# 在本函数之后才创建，其源动画此时已清理完毕，合成结果天然无位置轨道，无需再处理。
			if DEBUG_MODE:
				debug_print("动画尚未创建（跳过移除位置轨道）: " + anim_name)
			continue
		var anim = anim_player.get_animation(anim_name)
		var track_count: int = anim.get_track_count()
		var removed: int = 0
		for i in range(track_count - 1, -1, -1):
			var track_type = anim.track_get_type(i)
			if track_type == Animation.TYPE_POSITION_3D:
				# 全部位置轨道剥离：Mixamo 位置轨道值在错误坐标系，保留会导致骨骼位置跳变。
				# 左手/右手贴合由 Mixamo 原始持枪动画旋转轨道天然保证，无需烘焙补偿轨道。
				anim.remove_track(i)
				removed += 1
		if removed > 0:
			total_removed += removed
			debug_print("  [" + anim_name + "] 移除了 " + str(removed) + " 个位置轨道, 剩余轨道数=" + str(anim.get_track_count()))
		else:
			debug_print("  [" + anim_name + "] 没有位置轨道需要移除（轨道数=" + str(track_count) + "）")
	
	debug_print(">>>> 位置轨道移除完成, 共移除 " + str(total_removed) + " 个轨道")
	debug_print(">>>> 蹲姿高度由 _crouch_visual_offset() 动态控制 (idle=" + str(_crouch_visual_offset()) + " walk=" + str(_crouch_walk_visual_offset()) + ")")

# ============================================================
# 过渡动画碰撞体高度插值
# 在蹲下/起立过渡动画期间，平滑插值碰撞体高度
# 视觉模型位置由动画的Hips位置轨道控制，不做手动偏移
# ============================================================
func _update_transition_visual(delta: float):
	var anim_name = _anim_name_for(current_state)
	if anim_name.is_empty() or not anim_player.has_animation(anim_name) or not anim_player.is_playing():
		return
	
	var anim = _get_cached_animation(current_state)
	if anim == null:
		return
	var progress = anim_player.current_animation_position / anim.length
	progress = clamp(progress, 0.0, 1.0)
	
	if current_state == AnimState.STAND_TO_CROUCH:
		# 站→蹲：碰撞体从1.8m→1.1m，视觉模型从0→_crouch_visual_offset()
		var target_height = lerpf(_standing_height(), _crouching_height(), progress)
		_update_collision_height(target_height)
		_target_visual_y = lerpf(0.0, _crouch_visual_offset(), progress)
		character_visual.position.y = _target_visual_y
		
		if _debug_counter % 3 == 0:
				if DEBUG_MODE: _log_spatial_info("蹲下过渡 p=" + str(snapped(progress, 0.01)))
		
	elif current_state == AnimState.CROUCH_TO_STAND:
		# 蹲→站：碰撞体从1.1m→1.8m，视觉模型从_crouch_visual_offset()→0
		var target_height = lerpf(_crouching_height(), _standing_height(), progress)
		_update_collision_height(target_height)
		_target_visual_y = lerpf(_crouch_visual_offset(), 0.0, progress)
		character_visual.position.y = _target_visual_y
		
		if _debug_counter % 3 == 0:
				if DEBUG_MODE: _log_spatial_info("起立过渡 p=" + str(snapped(progress, 0.01)))

# ============================================================
# _physics_process(delta)
# 物理更新 + 动画状态机更新
# ============================================================
func _physics_process(delta):
	# 启动帧计数，用于稳定地面检测
	_startup_frames += 1
	_debug_counter += 1

	# 【崩溃修复】尼泊尔刀挂载帧计数状态机轮询（无协程，主线程同步推进）
	_process_nepal_mount_pending()
	_process_grenade_mount_pending()

	# 换弹输入缓冲：R 的 just_pressed 仅当帧有效。当 R 与蹲/刺刀同帧按下，或蹲过渡/
	# 刺刀防护期按下时，R 会被其他输入分支的早退或换弹守卫吞掉；这里先把 R 记进缓冲，
	# 后续换弹检测用 "just_pressed 或 缓冲>0" 判定，使换弹在可触发的那一帧补触发。
	# 放在最前，确保任何早退分支之前都执行（每帧递减，超时归零）。
	if Input.is_action_just_pressed("reload") and not _is_reload_state(current_state):
		# 【修复】换弹进行中不再记缓冲：换弹中按 R 会被 one-shot 早退吞掉、缓冲不清零，
		# 换弹结束后 0.5s 内残留缓冲会自动补触发第二次换弹（连按 R 必现）。
		_reload_input_buffer = RELOAD_INPUT_BUFFER
	_reload_input_buffer = maxf(0.0, _reload_input_buffer - delta)

	# 【P3】能力系统每帧推进：冷却 + 激活中能力更新
	_update_abilities(delta)

	# --- 死亡状态锁：只维持物理，不响应任何输入（除了相机）
	if is_dead:
		_process_death_locked(delta)
		return
	
	# 蹲姿受击倒地动画播放中：锁定所有输入，只处理重力防止悬空
	if _is_in_crouch_hit_back:
		if not is_on_floor():
			velocity.y += GRAVITY * delta
		move_and_slide()
		return
	
	# --- 读取输入（放在最前面，确保移动输入始终被更新） ---
	input_dir = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	
	# --- 能力（Q 键技能）已取消：Q 现用于「切换上一把武器」（见 _unhandled_input）。
	# 能力框架代码保留，此处不再绑定激活。 ---
	
	# --- 检测 Ctrl 键状态（提前处理，确保换弹期间也能响应） ---
	var crouch_just_pressed: bool = Input.is_action_just_pressed("crouch")
	var crouch_just_released: bool = Input.is_action_just_released("crouch")
	
	# --- 跟踪蹲下键按住时间（放在过渡检测之前，确保过渡期间也能累计时间） ---
	# 用实时 is_action_pressed 作为"是否仍按住"的真值来源，避免 just_released 偶发误触发
	# 导致长按过程中 _crouch_hold 被提前清零、press_time 冻结，从而把长按误判为点击。
	if _crouch_hold or Input.is_action_pressed("crouch"):
		_crouch_press_time += delta
	
	# 一次性动画播放中（换弹/受击/投掷/尼泊尔挥刀）
	if _is_in_one_shot_override:
		_process_one_shot_override(delta, crouch_just_pressed, crouch_just_released)
		# 【修复】one-shot 帧也要同步封锁状态：原先此分支早退跳过 _process_fire_block_sync，
		# set_reloading/set_fire_blocked 停在旧值，换弹/挥刀期间的射击准入判定读到陈旧状态。
		_process_fire_block_sync(_is_on_floor())
		return
	
	var on_floor: bool = _is_on_floor()  # 带容错的地面检测
	
	_process_anim_position_log(delta)
	
	# 调试日志：每帧输出动画状态详情（仅在 DEBUG_MODE 开启时执行，避免关闭后仍有字符串拼接开销）
	if DEBUG_MODE:
		var anim_info = "无"
		if anim_player:
			anim_info = "is_playing=" + str(anim_player.is_playing()) + " cur_anim=" + anim_player.current_animation + " speed=" + str(anim_player.speed_scale)
		debug_print("=== FRAME=" + str(_debug_counter) + " state=" + str(current_state) + " last_played=" + str(_last_played_state) + " input_dir=" + str(input_dir) + " anim=[" + anim_info + "]" + " is_dead=" + str(is_dead) + " is_trans=" + str(is_transitioning) + " is_crouch=" + str(is_crouching) + " is_running=" + str(is_running) + " _is_in_oneshot=" + str(_is_in_one_shot_override) + " _is_in_crouch_hit=" + str(_is_in_crouch_hit_back))
	
	# --- 蹲下键释放检测（长按后松开→起立，放在过渡检测之前，确保过渡期间也能响应） ---
	# 额外用实时 is_action_pressed 确认按键确实已抬起，避免 just_released 抖动造成误判
	if crouch_just_released and not Input.is_action_pressed("crouch"):
		_crouch_hold = false
		# 如果已经完全蹲下且不在过渡中，立即起立
		if is_crouching and not is_transitioning:
			debug_print("蹲下释放: 长按结束，起立")
			_start_stand_transition()
			_process_movement(delta)
			return
	
	# --- 落地防抖 ---
	if on_floor:
		if was_in_air:
			landing_cooldown_timer = LANDING_COOLDOWN
			was_in_air = false
		if landing_cooldown_timer > 0:
			landing_cooldown_timer -= delta
	else:
		was_in_air = true
	
	# --- 过渡超时保护（防止卡死） ---
	if is_transitioning:
		_process_transition(delta)
		return
	
	# --- 调试输出（每60帧输出一次地面状态） ---
	if _startup_frames % 60 == 1:
		debug_print("地面检测: is_on_floor=" + str(is_on_floor()) + "  global_y=" + str(global_position.y) + "  startup_frames=" + str(_startup_frames))
	
	# --- 蹲下键按下检测 ---
	# 【修复】换弹中按蹲：不要进这个分支（否则会 _is_in_one_shot_override=false 取消换弹、
	# 又早退吞掉后续 R 检测）。换弹期间蹲下/起立由上方"一次性动画覆盖"时间轴统一处理
	# （切对应蹲/站换弹变体），换弹与声音都连续。仅非换弹时才走正常蹲姿过渡。
	if crouch_just_pressed and not is_transitioning and on_floor and not _is_reloading:
		_process_crouch_press(delta)
		return
	
	# --- 蹲姿受击倒地输入（U键） ---
	if not is_dead and is_crouching and on_floor and not is_transitioning:
		if Input.is_action_just_pressed("crouch_hit_back"):
			debug_print(">> [INPUT] 蹲姿受击倒地 U键 触发, current_state=" + str(current_state) + " is_crouching=" + str(is_crouching))
			_start_crouch_hit_back()
			_process_movement(delta)
			return
		else:
			if _debug_counter % 10 == 0:
				debug_print(">> [INPUT] 蹲姿受击倒地条件满足但U未按下, current_state=" + str(current_state))
	
	# --- 换弹输入（R键） ---
	# 刺刀进行中不允许换弹（刺刀不可被打断，规则4）
	var _bay_active: bool = _is_bayonet_active()
	if not is_dead and not is_transitioning and not is_running and not _bay_active \
		and current_state not in _RELOAD_BLOCK_STATES:
		# 【修复】用 "just_pressed 或 缓冲>0"：R 与蹲/刺刀同帧或蹲过渡期被吞时，
		# 由 _reload_input_buffer 在可触发的那一帧补触发，避免"换弹没触发→没声音"。
		if (Input.is_action_just_pressed("reload") or _reload_input_buffer > 0.0):
			# 【P3 多武器】换弹打断开镜（开镜时按 R → 关镜换弹）
			_cancel_scope()
			# 【P3 开镜射击】换弹 = 手动干预：中断"射击动画结束后自动重开镜"流程
			_scope_shot_cancel = true
			debug_print(">> [INPUT] 换弹 R键 触发, current_state=" + str(current_state) + " is_crouching=" + str(is_crouching))
			_play_one_shot_override(AnimState.RELOADING)
			_reload_input_buffer = 0.0   # 换弹已触发，清空缓冲
			if _fp_mode and _fp_vm != null:
				# FP reload 动画按中间值时长放慢（speed = 动画原长/中间值 < 1），
				# 与 3P（加速适配）节奏一致
				_fp_vm.trigger_reload_duration(_reload_duration if _reload_duration > 0.01 else 2.2)
			elif not _fp_mode and _fp_action != null:
				# 3P 换弹音效（此前 3P 换弹无音；FP 由 viewmodel 自身播放，此处补上）
				# 传 _reload_duration 使 3P 换弹声时长跟随动画（与 FP 一致）
				_fp_action.trigger_reload(_reload_duration)
			_process_movement(delta)
			return
		else:
			if _debug_counter % 30 == 0:
				debug_print(">> [INPUT] R键未按下, current_state=" + str(current_state) + " run_pressed=" + str(Input.is_action_pressed("run")))
	
	# --- 死亡输入 ---
	if Input.is_action_just_pressed("death"):
		_die()
		return
	
	# --- 受击/投掷输入（优先级：不打断死亡、跳跃、站蹲过渡） ---
	if not is_dead and not is_transitioning and current_state not in _AIR_STATES:
		if Input.is_action_just_pressed("hit_reaction"):
			# 【P3 多武器】受击打断开镜
			_cancel_scope()
			_play_one_shot_override(AnimState.HIT_REACTION)
		# 【手雷接入】G 键投掷已取消：手雷统一走 4 号槽位（持雷为独立武器，见 WEAPON_SLOT_IDS）。
		# 原 G 键_play_one_shot_override(TOSS_GRENADE) 逻辑移除；后续真实投掷玩法再单独设计。
	
	# --- 跳跃输入 ---
	var should_jump: bool = Input.is_action_just_pressed("jump") and on_floor and not is_transitioning
	if should_jump:
		# 【P3 多武器】跳跃打断开镜
		_cancel_scope()
		_jump_delay_timer = JUMP_DELAY  # 启动跳跃延迟，让动画蓄力帧先播放
	
	# --- 物理移动 ---
	_process_movement(delta, should_jump)
	
	# 获取当前实际水平速度
	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	
	# --- 奔跑状态更新（进入/维持/退出） ---
	_update_running_state(delta, on_floor)

	# --- 射击封锁（奔跑禁射）全流程 ---
	_process_fire_block_sync(on_floor)
	
	# --- 动画状态机更新 ---
	_update_animation_state(should_jump, on_floor, horizontal_speed, delta)

## 死亡状态：K 手动复活 / 自动复活倒计时 / 只维持物理
func _process_death_locked(delta: float) -> void:
	# 手动复活：K 键上升沿检测（防止死亡当帧按下同时触发死亡与复活）
	# 放在自动复活计时之前，保证倒计时期间按 K 也能立即起身
	# 【修复】改走 InputMap（"death" action 同为 K 键）：硬编码物理键码绕过改键
	# 设置，且会与 InputMap 里未来的 K 绑定冲突。
	var k_pressed: bool = Input.is_action_pressed("death")
	if k_pressed and not _k_was_pressed:
		_k_was_pressed = true
		_resurrect()
		return
	elif not k_pressed:
		_k_was_pressed = false
	# 自动复活：死亡动画播完后开始倒计时，到点自动起身
	if _death_await_revive:
		_death_revive_timer -= delta
		if _death_revive_timer <= 0.0:
			_resurrect()
			return
	# 死亡期间只维持物理：悬空则继续下落，落地则静止
	if not is_on_floor():
		velocity.y += GRAVITY * delta
	else:
		velocity = Vector3.ZERO
	move_and_slide()

## 一次性动画覆盖中（换弹/受击/投掷/尼泊尔挥刀）：换弹时间轴推进 + 蹲切换 + 移动
func _process_one_shot_override(delta: float, crouch_just_pressed: bool, crouch_just_released: bool) -> void:
	# 换弹期间：动态切换合成动画
	if _is_reload_state(current_state):
		# 统一换弹时间轴：进度由 _reload_elapsed 线性推进，与当前展示的换弹变体无关。
		# 中途切换移动方向或蹲/站，换弹都按固定总时长一次性走完，绝不重播。
		_reload_elapsed += delta
		if _reload_elapsed >= _reload_duration:
			_finish_reload_flexible()
			_process_movement(delta)
			return
		# 【修复】FP viewmodel 换弹自愈：任何时序原因导致第一人称换弹掉线
		# （换弹中切视角/换弹中换弹/切角色后残留等），下一帧自动从当前进度补播，
		# 保证 FP 枪手动画与 3P 影子（地上的换弹投影）始终同步。
		if _fp_mode and _fp_vm != null and _is_reloading and not _fp_vm.is_reload():
			# 【修复】原用 str(current_animation).contains("reload") 字符串匹配，
			# 动画名偶含 "reload" 子串或 current_animation 为空时会误判/漏判。
			# 改用显式状态查询 is_reload()（与 is_shoot/is_bayonet 同源），语义精确。
			var _rem := maxf(_reload_duration - _reload_elapsed, 0.1)
			var _prg := clampf(_reload_elapsed / _reload_duration, 0.0, 0.999)
			_fp_vm.trigger_reload_duration(_rem, _prg, false)
	# 【修复】蹲下/起立切换：对所有一次性动画生效（换弹/尼泊尔挥刀等）。
	# 【v22 修复·蹲下过渡动画】原实现为“瞬切”（只切 is_crouching/碰撞体/视觉偏移，
	# 不播过渡动画）→ 用户反馈“蹲下+挥砍同帧触发时不出现蹲下-起立过渡动画”。
	# 改为委托 _process_crouch_press：它会取消当前一次性动画（挥砍/换弹）→ 停动画 →
	# 播 STAND_TO_CROUCH 过渡 → 松键自动起立（与“蹲下打断换弹”行为一致，
	# 该路径已在 08-24 第20轮验证不卡死）。
	# 点击=peek（按下蹲、松开即起），长按=按住时蹲、松开即起，与正常模式完全对齐。
	if crouch_just_pressed and not _crouch_hold:
		_process_crouch_press(delta)
		return
	if crouch_just_released and _crouch_hold and not Input.is_action_pressed("crouch"):
		_crouch_hold = false
		# 【v22 修复·起立过渡动画】同蹲下：不再瞬切，播 CROUCH_TO_STAND 过渡。
		# 若当前正处于 STAND_TO_CROUCH 过渡（刚蹲下即松开）→ 交给 _on_transition_done
		# 的“松键立即起立”逻辑（_start_stand_transition），此处不重复处理。
		if _is_in_one_shot_override:
			# 挥砍/换弹中松蹲：取消一次性动画，播起立过渡（与 _process_crouch_press 对称）
			# 【修复】同蹲下打断路径：换弹被打断先走统一收尾（复位 _is_reloading + 停音）
			if _is_reloading:
				_finish_reload_flexible()
			_is_in_one_shot_override = false
			if is_instance_valid(anim_player) and anim_player.is_playing():
				_anim_op("STOP@3101_crouch_interrupt")
				anim_player.stop()
		is_crouching = false
		camera_controller.set_crouch(false, CROUCH_TRANSITION_DURATION)
		_update_collision_height(_standing_height())
		_start_stand_transition()
		_process_movement(delta)
		return
	# 【修复】挥刀等一次性动画期间也更新奔跑状态（shift+W 可进入/维持奔跑），
	# 否则挥刀时移动速度被锁在挥刀前状态 → 观感减速。
	_update_running_state(delta, _is_on_floor())
	# 【修复】挥刀期间下半身动态跟随输入（转身/变向/按移动键挥刀不卡顿）
	if current_state == AnimState.NEPAL_ATTACK_LIGHT or current_state == AnimState.NEPAL_ATTACK_HEAVY:
		_nepal_maybe_follow_lower()
	# 【修复】挥刀等一次性动画期间也可跳跃：跳跃物理生效后 _nepal_maybe_follow_lower
	# 会把下半身切到 JUMP_UP/DOWN（选项B：空中挥刀腿继续跳）。换弹中不跳。
	var _jump_ok: bool = Input.is_action_just_pressed("jump") and _is_on_floor() \
		and not is_transitioning and not _is_reload_state(current_state)
	if _jump_ok:
		_cancel_scope()
		_jump_delay_timer = JUMP_DELAY   # 延迟让挥砍起手帧先播再离地
	# 换弹变体切换 + 视觉高度（仅换弹）
	if _is_reload_state(current_state):
		# 按移动方向无缝切换换弹变体（保留进度，不重头播放）
		_update_reload_animation_for_movement()
		# 视觉高度插值（站=0 / 蹲=offset / 蹲走=walk offset，平滑过渡）
		if is_crouching:
			var has_movement: bool = abs(input_dir.x) > 0.1 or abs(input_dir.y) > 0.1
			_target_visual_y = _crouch_walk_visual_offset() if has_movement else _crouch_visual_offset()
		else:
			_target_visual_y = 0.0
		character_visual.position.y = lerpf(character_visual.position.y, _target_visual_y, clampf(VISUAL_LERP_SPEED * delta, 0.0, 1.0))
	_process_movement(delta, _jump_ok)

## 逐帧动画位置检测（记录/校正位置跳变，调试用）
func _process_anim_position_log(delta: float) -> void:
	# --- 逐帧动画位置检测（每帧都记录，检测跳变）---
	_anim_log_counter += 1
	if anim_player and anim_player.is_playing():
		var cur_pos = anim_player.current_animation_position
		var cur_anim = anim_player.current_animation
		var pos_diff = cur_pos - _prev_anim_position
		
		# 检测位置跳变（负值表示回退，或突变超过预期步长）
		var expected_step = delta * anim_player.speed_scale
		if _prev_anim_position >= 0 and pos_diff < -0.01:
			_anim_position_jumps += 1
			var anim = anim_player.get_animation(cur_anim) if anim_player.has_animation(cur_anim) else null
			var anim_len = anim.length if anim else 0
			# 只记录非循环回绕的跳变（循环回绕是正常的：pos从length回到0）
			if DEBUG_MODE and abs(pos_diff + anim_len) > 0.01:
				debug_print(">> [ANIM JUMP] frame=" + str(_debug_counter) + " anim=" + cur_anim + " pos=" + str(_prev_anim_position) + " -> " + str(cur_pos) + " diff=" + str(pos_diff) + " expected_step=" + str(expected_step))
		
		# 【正向跳变校正】pos 一帧前进远超预期步长（且不是循环回绕）= 动画被快进/跳段
		# → 蹲走等循环动画每循环跳过一段，上半身姿态突跳"磕头"（用户实测：拉环态蹲左走
		# 1s 一下；日志 pos 0.38→0.87 一帧 +0.49）。校正回连续位置，阻止跳段。
		if _prev_anim_position >= 0 and pos_diff > expected_step * 5.0 and pos_diff < 0.4:
			_anim_position_jumps += 1
			if DEBUG_MODE:
				debug_print(">> [ANIM POS FIX] anim=" + str(cur_anim) + " pos=" + str(_prev_anim_position) + " -> " + str(cur_pos) + " diff=" + str(pos_diff) + " exp=" + str(expected_step) + " (正向跳变校正)")
			_anim_op("SEEK@3160_pos_fix")
			anim_player.seek(_prev_anim_position + expected_step, true)
			cur_pos = _prev_anim_position + expected_step
		
		_prev_anim_position = cur_pos
	
	# 每 60 帧输出一次详细动画位置日志（仅调试模式）
	if DEBUG_MODE and _debug_counter % 60 == 1:
		if anim_player and anim_player.is_playing():
			var cur_anim = anim_player.current_animation
			var cur_pos = anim_player.current_animation_position
			var anim = anim_player.get_animation(cur_anim) if anim_player.has_animation(cur_anim) else null
			var anim_len = anim.length if anim else 0
			debug_print(">>> [ANIM POS] frame=" + str(_debug_counter) + " anim=" + cur_anim + " pos=" + str(cur_pos) + "/" + str(anim_len) + " speed=" + str(anim_player.speed_scale) + " state=" + str(current_state) + " jumps_total=" + str(_anim_position_jumps))

## 站蹲过渡动画播放中：超时保护 + 过渡内换弹 + 移动
func _process_transition(delta: float) -> void:
	# --- 过渡超时保护（防止卡死） ---
	transition_timer += delta
	if transition_timer > 3.0:
		debug_print("WARNING: 过渡动画超时，强制完成")
		_on_transition_done()
	
	# 蹲下/起立过渡期间：平滑插值碰撞体高度和视觉模型位置
	if current_state in _TRANSITION_STATES:
		_update_transition_visual(delta)
	# 站/蹲过渡瞬间允许按 R 触发换弹：原本会落到下面 is_transitioning 分支末尾的
	# 提前 return，整段过渡期（约 0.1s）完全跳过第 712 行的 R 键检测，导致
	# "站蹲切换那一瞬间按换弹不生效"。先把过渡落地到稳定的站/蹲姿态，再进入
	# 换弹，避免半蹲半站地播换弹动画；_play_one_shot_override 会依据 is_crouching
	# 自动选用对应换弹变体，并把当前稳定姿态记为恢复态。
	if not is_dead and current_state in _TRANSITION_STATES:
		if (Input.is_action_just_pressed("reload") or _reload_input_buffer > 0.0):
			if current_state == AnimState.STAND_TO_CROUCH:
				is_crouching = true
				_update_collision_height(_crouching_height())
				character_visual.position.y = _crouch_visual_offset()
				_change_state(AnimState.CROUCH_IDLE_AIM)
			else:  # CROUCH_TO_STAND
				is_crouching = false
				_update_collision_height(_standing_height())
				character_visual.position.y = 0.0
				_change_state(AnimState.IDLE_AIM)
			# —— 以下整段仅在"站蹲过渡中确实按了换弹(R)"时执行 ——
			# 【修复】原代码因缩进错误把这段放到 reload 判断之外，导致整个蹲伏过渡期
			# (STAND_TO_CROUCH/CROUCH_TO_STAND 约 0.5s) 内每帧都强制清 is_transitioning、
			# 强播换弹动画+换弹声并 return，于是"按 Ctrl 蹲下"反而触发换弹（"蹲键和换弹
			# 错乱"），且蹲伏动画被覆盖而永远收不了尾。现收回到 reload 判断内：纯蹲伏
			# 不进此分支，落到下方 _process_movement 继续过渡，由 animation_finished→
			# _on_transition_done 正常收尾；仅过渡中真按了 R 才短路进换弹。
			is_transitioning = false
			transition_timer = 0.0
			debug_print(">> [INPUT] 站蹲过渡中触发换弹, trans_state=" + str(current_state))
			# 【P3 开镜射击】换弹 = 手动干预：中断自动重开镜流程
			_scope_shot_cancel = true
			_play_one_shot_override(AnimState.RELOADING)
			_reload_input_buffer = 0.0   # 换弹已触发，清空缓冲
			# 【修复】站蹲过渡中触发换弹也必须播放换弹声（与主线换弹分支一致）。
			# 否则 reload+crouch 一起按（或射击+换弹+蹲一起按）时，换弹动画播了但没声音：
			# 蹲下先占帧开启 STAND_TO_CROUCH 过渡，缓冲的 R 在下一帧被本过渡分支吃掉，
			# 原代码只播动画漏了触发换弹音。
			if _fp_mode and _fp_vm != null:
				_fp_vm.trigger_reload_duration(_reload_duration if _reload_duration > 0.01 else 2.2)
			elif not _fp_mode and _fp_action != null:
				_fp_action.trigger_reload(_reload_duration)
			_process_movement(delta)
			return


	_process_movement(delta)

## 蹲下键按下：站→蹲过渡 / 蹲→站切换（含清换弹缓冲防误触）
func _process_crouch_press(delta: float) -> void:
	# 【修复·续9b】蹲下起步即清换弹输入缓冲：这是"一个 Ctrl 同时触发蹲+换弹"的真实根因。
	# 玩家此前轻点过 R（_reload_input_buffer 被置为>0，约 0.5s 内衰减），随后按 Ctrl 蹲下；
	# 蹲伏过渡分支读到缓冲>0 即把这次残留的 R 当 reload 强播，于是"纯蹲下反而换弹"。
	# Ctrl 只应=蹲：此处清缓冲后，① 纯蹲不再误换弹；② R 与 Ctrl 同帧也只蹲不换弹；
	# ③ 蹲定后、或蹲过渡中再按 R，仍可正常换弹（走过渡分支/主分支的 just_pressed 判定）。
	_reload_input_buffer = 0.0
	_crouch_hold = true
	_crouch_press_time = 0.0
	# 如果正在播放一次性覆盖动画（如换弹），取消它，让过渡动画接管
	if _is_in_one_shot_override:
		# 【修复】换弹被打断必须先走统一收尾（复位 _is_reloading + 停 1P/3P 换弹音）：
		# 换弹计时器只活在 _process_one_shot_override 里，这里把 one-shot 取消后
		# _finish_reload_flexible 永远不会执行 → _is_reloading 卡 true（封锁射击/刺刀）、
		# 换弹音不受控播完整段。挥刀等非换弹 one-shot 不受影响。
		if _is_reloading:
			_finish_reload_flexible()
		_is_in_one_shot_override = false
		# 【挥刀兼容·防卡死】取消一次性动画时必须同步停掉正在播放的一次性动画，
		# 否则其播完信号 _on_animation_finished 仍按旧 current_state（如 NEPAL_ATTACK）
		# 分支处理 → 与蹲伏过渡动画竞争 → 状态错乱/动画卡死。
		if is_instance_valid(anim_player) and anim_player.is_playing():
			if NEPAL_LOG and current_state in _NEPAL_ATTACK_STATES:
				print("[NEPAL] 蹲下打断挥刀: 停动画 %s" % anim_player.current_animation)
			_anim_op("STOP@3255_crouch_interrupt_nepal")
			anim_player.stop()
		debug_print("蹲下: 取消一次性动画覆盖，过渡动画接管")
	if not is_crouching:
		# 站姿 → 蹲姿过渡（退出奔跑状态）
		is_running = false
		is_transitioning = true
		transition_timer = 0.0
		if NEPAL_LOG:
			print("[NEPAL] 蹲下过渡开始: oneshot=%s state=%s" % [str(_is_in_one_shot_override), _anim_state_str(current_state)])
		camera_controller.set_crouch(true, CROUCH_TRANSITION_DURATION)
		_change_state(AnimState.STAND_TO_CROUCH)
		debug_print("蹲下: 站→蹲过渡开始")
		_log_spatial_info("蹲下开始")
		# 动画播放速度 = 动画原始时长 / 目标过渡时长，使动画在0.1s内播完
		var crouch_down_anim = _get_cached_animation(AnimState.STAND_TO_CROUCH)
		var crouch_down_speed: float = crouch_down_anim.length / CROUCH_TRANSITION_DURATION if crouch_down_anim else 1.0
		_play_animation(AnimState.STAND_TO_CROUCH, false, crouch_down_speed)
	else:
		# 已蹲下 → 起立（切换）
		debug_print("蹲下: 切换起立")
		_start_stand_transition()
	# 跳过本帧其他动画逻辑
	_process_movement(delta)

## 射击封锁同步：奔跑禁射全流程（地面奔跑立即打断射击并禁射；空中解除封锁）
func _process_fire_block_sync(on_floor: bool) -> void:
	# 地面奔跑=is_running 且着地；跳跃（空中）时 on_floor=false → 解除封锁，允许射击；
	# 落地瞬间 on_floor=true 且 is_running 仍为 true（0.15s 退出延迟内）→ 立刻恢复封锁 → 射击立即停止。
	if _fp_action != null or _fp_vm != null:
		var _ground_run: bool = is_running and on_floor and not is_crouching
		if _fp_action != null:
			_fp_action.set_fire_blocked(_ground_run)
			_fp_action.set_reloading(_is_reloading)  # 每帧同步换弹状态：3P 射击约束与 FP is_reload() 对齐
			if _ground_run:
				_fp_action.interrupt_shoot()  # 奔跑瞬间立即打断正在播放的射击动作
		if _fp_vm != null:
			_fp_vm.set_fire_blocked(_ground_run)
			if _ground_run:
				_fp_vm.interrupt_shoot()

# ============================================================
# 武器姿态：躯干俯仰叠加（本类） + 双手握持（WeaponRig，P0-1 抽离）
#  - _apply_torso_pitch_overlay()：上半身随相机俯仰（仅站/蹲待机与移动态）。
#  - 双手皮肤点连线定位 + 枪身轴线对齐 + 跳跃/换弹分支：已移至 scripts/weapon_rig.gd
#    （标定常量见 resources/weapon_rig_config.tres），由 _process 每帧调用 _weapon_rig.update()。
# ============================================================
# 上半身俯仰是否应在当前状态叠加：站姿待机/移动、蹲姿待机/移动、站蹲过渡；
# 跳跃/换弹/受击/投掷/死亡/蹲倒等其它状态返回 false（由 _process 平滑衰减、不叠加）。
func _torso_pitch_allowed() -> bool:
	return current_state in TORSO_PITCH_STATES

## 当前是否处于刺刀攻击进行中（第一人称走 FP 视图模型，第三人称走 FP 动作重定向）。
## 【修复 M5】统一判空：避免 _fp_mode 为 true 但 _fp_vm 尚未建好（切换/重挂瞬间）时
## 直接解引用 _fp_vm 崩溃。原两处完全相同的内联表达式（换弹输入、鼠标输入）合并为此方法。
func _is_bayonet_active() -> bool:
	if _fp_mode:
		return _fp_vm != null and _fp_vm.is_bayonet()
	return _fp_action != null and _fp_action.is_bayonet()

# 上半身随相机俯仰抬起/低下（仅动画层附加旋转，作用于腰部枢轴骨 mixamorig_Spine）：
# 旋转该骨=整条上半身链(脊/头/双臂)随之俯仰。游戏/握持/斜率差均读实时骨骼全局姿态→自动跟随，
# 不影响其他功能。须在 process_priority 高于 AnimationPlayer 的本函数内、调用 _weapon_rig.update 之前执行，
# 使握持系统读到的骨骼姿态已含本次俯仰。
# 抽成独立方法：既被 _process 每帧调用（保持 process_priority 语义），也可被无头探针 call() 直接驱动验证。
func _apply_torso_pitch_overlay(delta: float) -> void:
	# 每帧缓存一次骨架全局变换：torso 块复用，避免重复层级回溯（握持侧在 WeaponRig 内各自缓存）
	# 【修复 M3】必须在判空之后取全局变换：否则 _weapon_skel 为 null（切换/重挂瞬间）时
	# 直接解引用崩溃/读到恒等矩阵 → 上半身俯仰公式全错。
	if _weapon_skel == null or _torso_bone_idx < 0:
		return
	_skel_global = _weapon_skel.global_transform
	# 【修复】相机缺失（角色切换/重挂瞬间 _camera_ctrl 临时为空）时仍平滑衰减俯仰角回正，
	# 否则 _torso_pitch_smooth 冻结在上一帧非零值 → 相机恢复后上半身持续歪斜。
	if _camera_ctrl == null:
		_torso_pitch_smooth = lerp_angle(_torso_pitch_smooth, 0.0, clampf(delta * TORSO_PITCH_SPEED, 0.0, 1.0))
		return
	# 仅【站姿待机/移动、蹲姿待机/移动】四类状态叠加上半身俯仰；
	# 跳跃/换弹/受击/投掷/死亡/蹲倒/站蹲过渡等其它状态不叠加，并把 _torso_pitch_smooth
	# 平滑衰减到 0，回到允许状态时从 0 自然回升，避免回正瞬移。
	if _torso_pitch_allowed():
		var cam_pitch: float = _camera_ctrl.pitch
		var target_pitch: float = clampf(cam_pitch * TORSO_PITCH_FOLLOW * TORSO_PITCH_SIGN, -TORSO_PITCH_MAX, TORSO_PITCH_MAX)
		_torso_pitch_smooth = lerp_angle(_torso_pitch_smooth, target_pitch, clampf(delta * TORSO_PITCH_SPEED, 0.0, 1.0))
		if absf(_torso_pitch_smooth) > 0.0002 and _weapon_bone_idx >= 0 and _lhand_bone_idx >= 0:
			var rh_g: Transform3D = _weapon_skel.get_bone_global_pose(_weapon_bone_idx)
			var lh_g: Transform3D = _weapon_skel.get_bone_global_pose(_lhand_bone_idx)
			var d_skel: Vector3 = (lh_g.origin - rh_g.origin).normalized()
			var skel_up: Vector3 = (_skel_global.basis.inverse() * Vector3.UP).normalized()
			var right_skel: Vector3
			if _grenade_pulling or _grenade_throwing or _grenade_holding \
					or not _grenade_applied.is_empty():
				# 【手雷武器全程】双手被直驱摆到拉环姿态/持雷姿态，双手连线叉乘可能随
				# 蹲姿翻转（蹲左走时俯仰方向每步交替"磕头"，用户实测 + 探针实锤：
				# probe_pitch_axis_leftwalk.gd 叉乘方向序列 L→R→L→R 每步伐周期翻转）。
				# ⚠️ 手雷 stance 挂 _grenade_applied，而原判断只看 _pistol/_nepal_applied
				# → 手雷武器误入"步枪"叉乘动态分支。改为手雷 stance 生效即固定 LEFT
				# （=站立拉环实测方向，站立逻辑零变化、蹲走不再翻转）。
				right_skel = Vector3.LEFT
			elif _pistol_applied.is_empty() and _nepal_applied.is_empty():
				# 步枪/其它武器：旋转轴固定为骨架局部 X（左右轴），符号按双手连线叉乘的
				# 主方向决定。⚠️ 原逻辑 d_skel.cross(skel_up) 对双手位置敏感：步枪持枪时
				# 双手连线非纯前向（左手握护木在右前方），headless 实测叉乘出 (-0.96,0,0.28)
				# 偏 16° → 低头抬头带 16° 左右滚转分量 = "抬头低头变左右歪" + 上半身
				# （含手臂）跟着歪 = "手动画异常"。固定纯 X 后只绕真正左右轴，与双手位置无关。
				right_skel = d_skel.cross(skel_up)
				if right_skel.length() > 0.001:
					right_skel = Vector3.LEFT if right_skel.dot(Vector3.RIGHT) < 0.0 else Vector3.RIGHT
				else:
					right_skel = Vector3.RIGHT
			else:
				# 手枪/尼泊尔(双持持刀)：双手贴近/斜置/同向前伸，连线叉乘出的轴歪斜
				# （低头抬头变左右滚转）。单独用骨架固定轴，方向族与原逻辑一致
				# （步枪实测连线轴≈骨架局部 -X）。
				right_skel = -Vector3.RIGHT
			right_skel = right_skel.normalized()
			var R: Basis = Basis(Quaternion(right_skel, _torso_pitch_smooth))
			# 【俯仰基准·哨兵检测】两个历史 bug 源于同一个两难：
			#   基准读实时骨骼姿态(get_bone_pose)=读-改-写：AP 未重写该骨的窗口帧
			#   （尼泊尔重合成 stop/install/play、AP 停播）会读到自己上一帧的输出 →
			#   逐帧累积 → 上半身绕水平轴失控旋转（旧 bug）。
			#   基准一律从动画采样：0.15s 交叉淡入期间 AP 实际写的是新旧动画混合值，
			#   而采样只有新动画 → 叠加层把旧动画的脊柱贡献瞬间清零 → 待机↔行走
			#   切换瞬间上半身抖一下（新 bug，方向=两动画脊柱姿态差）。
			# 哨兵方案两全：每帧记录写入值。下帧骨骼姿态仍==上次写入值（引擎逐字
			# 复制，可精确比较）→ AP 本帧未重写 → 从渲染值剥离旧俯仰恢复动画基准
			# （逐帧自校正，永不累积）；否则 → AP 已重写（含淡入混合）→ 直接用实时
			# 姿态（淡入平滑）。回归：tools/probe_torso_spin.gd（不累积）+
			# tools/probe_torso_fade.gd（切换平滑）。
			if _torso_last_skel_id != _weapon_skel.get_instance_id():
				_torso_last_skel_id = _weapon_skel.get_instance_id()
				_torso_has_last = false   # 换角色/换骨架：哨兵失效重置
			var live_q: Quaternion = _weapon_skel.get_bone_pose(_torso_bone_idx).basis.get_rotation_quaternion()
			var base_q: Quaternion
			if _torso_has_last and live_q.angle_to(_torso_last_render_q) < 0.0001:
				base_q = _torso_last_local_q.inverse() * live_q
			else:
				base_q = live_q
			var base_pos: Vector3 = _weapon_skel.get_bone_pose(_torso_bone_idx).origin
			var parent_global: Transform3D = _weapon_skel.get_bone_global_pose(_torso_parent_idx) if _torso_parent_idx >= 0 else Transform3D.IDENTITY
			var local_R: Basis = parent_global.basis.inverse() * R * parent_global.basis
			var new_local_basis: Basis = (local_R * Basis(base_q)).orthonormalized()
			_weapon_skel.set_bone_pose(_torso_bone_idx, Transform3D(new_local_basis, base_pos))
			_torso_last_render_q = new_local_basis.get_rotation_quaternion()
			_torso_last_local_q = local_R.get_rotation_quaternion()
			_torso_has_last = true
	else:
		_torso_pitch_smooth = lerp_angle(_torso_pitch_smooth, 0.0, clampf(delta * TORSO_PITCH_SPEED, 0.0, 1.0))

# 【俯仰基准·哨兵状态】上一帧写入值/已施加局部俯仰/是否有效/骨架实例 id
var _torso_last_render_q: Quaternion = Quaternion.IDENTITY
var _torso_last_local_q: Quaternion = Quaternion.IDENTITY
var _torso_has_last: bool = false
var _torso_last_skel_id: int = 0

func _process(delta: float) -> void:
	# 角色基底（世界→角色本地系换算；转身由 char_basis 瞬时吸收，枪跟随身体不脱手）
	var char_basis: Basis = character_visual.global_transform.basis.orthonormalized() if character_visual != null else Basis.IDENTITY
	# 【修复·刺刀俯仰 + 自由观察视角】前刺/后坐方向跟随"角色枪口实际瞄准方向"
	# = 角色水平前向(char_basis.z) 绕角色右轴 按 pitch 俯仰，而非相机视线 -camera.basis.z。
	# 原因：自由观察视角(`键)下相机会绕角色任意角度观察，-camera.basis.z 会跟着观察者相机
	# 翻转（相机绕到正面时 -camera.basis.z 指向 +Z 角色身后），导致低头/侧视时刺刀前后看似反向；
	# 而角色枪口瞄准只由"角色朝向 + pitch"决定，与观察者相机位置无关。
	# 普通/FP 视角下 -camera.basis.z 与"角色前向+pitch"等价，故该改法不改变既有正确观感。
	var aim_forward: Vector3 = char_basis.z
	if _camera_ctrl != null:
		var fwd_h := Vector3(char_basis.z.x, 0.0, char_basis.z.z)
		if fwd_h.length_squared() < 1e-6:
			fwd_h = Vector3(0.0, 0.0, 1.0)
		fwd_h = fwd_h.normalized()
		# 角色右轴（水平分量）：forward(+Z) × up(+Y) = +X-ish；取 char_basis.x 水平投影
		var right_axis := Vector3(char_basis.x.x, 0.0, char_basis.x.z)
		if right_axis.length_squared() < 1e-6:
			right_axis = Vector3(1.0, 0.0, 0.0)
		right_axis = right_axis.normalized()
		# pitch>0 = 低头：绕右轴正向旋转使水平前向朝下（与相机俯仰一致）。
		# 取不到相机时回退水平 char_basis.z（旧行为兜底）。
		aim_forward = fwd_h.rotated(right_axis, _camera_ctrl.pitch)
	# 【P3 开镜射击】射击动画结束后自动重开镜（FP/3P 统一检测，见函数注释）。
	# 放在视角分支之前：开镜射击的关镜状态与视角无关，两边都需被覆盖。
	_maybe_rescope_after_shot()
	# 【方案C】挥砍手臂直驱：必须在渲染帧（_process）执行，晚于 AnimationPlayer(pri=0)
	# 每帧推进骨骼。此前误放在 _physics_process，物理帧的直驱被渲染帧的持刀待机动画覆盖
	# → 手臂永远持刀待机，挥砍动画消失。直驱用渲染帧 delta 累计挥砍时间轴。
	_drive_nepal_arms(delta)
	# 【方案C】手雷手臂直驱（拉环/持环/投掷），与挥砍同纪律：渲染帧晚于 AP pri=0。
	_drive_grenade_arms(delta)
	if _fp_mode:
		# ---- 第一人称模式 ----
		# 3P 角色虽不可见(SHADOWS_ONLY)，但其骨架动画仍在播放、手部位姿随动作变化；
		# 必须继续驱动【躯干俯仰叠加 + 武器握持】，否则 3P 枪(及其地面投影)会冻结在
		# 切入 FP 瞬间的姿态，导致"第一人称的枪影子与第三人称对不上"（手在动、枪影不动，
		# 且瞄准俯仰不跟随）。两者仅改骨骼/枪变换、无音效副作用，可安全在 FP 下补跑。
		# 3P 刺刀/射击叠加(_fp_action.update)故意不在此调用：FP 下由视图模型接管，
		# 重跑会重复触发 3P 音效（连发/刺刀）。
		# 【修复 BUG#2】FP 视图模型更新独立于 3P 武器骨架有效性：即便武器骨缺失
		# （_weapon_bone_idx<0）也不冻结连发/呼吸动画；依赖 3P 骨架的叠加在下方另行守卫。
		if _fp_vm != null:
			_fp_vm.update(delta)
		# 武器骨架相关的 3P 叠加需要 rig/skel/骨有效，缺失则仅跑视图模型
		if _weapon_rig == null or _weapon_skel == null or _weapon_bone_idx < 0:
			return
		_apply_torso_pitch_overlay(delta)
		var oneshot_remaining: float = INF
		if _is_in_one_shot_override and _is_reloading:
			oneshot_remaining = _reload_duration - _reload_elapsed
		# FP 下补跑 3P 角色的后坐/刺刀叠加（仅视觉、无音效）：3P 角色为 SHADOW_ONLY，
		# 其手臂后坐会被投影到地面，使影子随射击/刺刀抖动（修复"FP 射击时影子没有抖动"）。
		# 须在 WeaponRig.update 之前（与 3P 一致），使枪身跟随手部后坐同步投影。
		if _fp_action != null:
			_fp_action.update_shadow(delta, char_basis, aim_forward)
		if _weapon_rig != null:
			_weapon_rig.update(delta, char_basis, _is_in_one_shot_override, _is_jump_state(), oneshot_remaining)
		return
	# 第三人称：全部依赖 3P 武器骨架，缺失则跳过
	if _weapon_rig == null or _weapon_skel == null or _weapon_bone_idx < 0:
		return
	# 上半身俯仰叠加（须在武器握持之前：手点需读到含俯仰的骨骼姿态）
	_apply_torso_pitch_overlay(delta)
	# 第三人称刺刀/射击动作叠加：驱动双臂肩骨 + 世界枪偏移（须在 WeaponRig.update 之前，
	# 使枪身冻结基础在稳定待机位、偏移精确叠加）
	if _fp_action != null:
		_fp_action.update(delta, char_basis, aim_forward)
	# 武器握持交由 WeaponRig 处理（双手皮肤点连线定位 + 枪身轴线对齐 + 跳跃/换弹分支）
	# 换弹时传入剩余时间，让枪身在动画结束前 ONE_SHOT_PRELEAD 秒提前切回双手连线方向，
	# 消除"换弹末帧双手未回位导致轴线延迟/跳变"（其他 one-shot 传 INF 不提前）。
	var oneshot_remaining: float = INF
	if _is_in_one_shot_override and _is_reloading:
		oneshot_remaining = _reload_duration - _reload_elapsed
	_weapon_rig.update(delta, char_basis, _is_in_one_shot_override, _is_jump_state(), oneshot_remaining)


# ============================================================
# 物理移动处理
# ============================================================
## 奔跑状态更新（进入/维持/退出）。正常流程与一次性动画（换弹/挥刀）共用，
## 保证挥刀等覆盖动画期间 shift+W 也能进入/维持奔跑（修复"挥刀减速"）。
func _update_running_state(delta: float, on_floor: bool) -> void:
	# --- 进入奔跑状态检测 ---
	if not is_running and not is_crouching and on_floor and not is_transitioning and not is_dead:
		var has_forward_input: bool = input_dir.y > 0.1
		var shift_held: bool = Input.is_action_pressed("run")
		if shift_held and has_forward_input:
			is_running = true
			_running_exit_timer = 0.0
			debug_print("奔跑: 进入奔跑状态")
	# --- 处理奔跑退出延迟（input_dir短暂波动不退出奔跑） ---
	if is_running:
		var has_forward_input: bool = input_dir.y > 0.1
		var shift_held: bool = Input.is_action_pressed("run")
		if shift_held and has_forward_input and on_floor and not is_crouching:
			_running_exit_timer = 0.0  # 维持奔跑，重置计时器
		else:
			_running_exit_timer += delta
			if _running_exit_timer > 0.15:  # 持续0.15秒无满足条件才退出
				is_running = false
				_running_exit_timer = 0.0
	else:
		_running_exit_timer = 0.0

func _process_movement(delta: float, should_jump: bool = false):
	# 始终应用重力，确保 move_and_slide() 每次都有向下速度来检测地面
	# 不再使用 if not is_on_floor() 条件，因为 velocity.y=0 时 move_and_slide() 可能丢失地面检测
	velocity.y += GRAVITY * delta
	
	# 跳跃延迟计时器：等待动画蓄力帧播放后再施加物理跳跃
	if _jump_delay_timer > 0:
		_jump_delay_timer -= delta
		if _jump_delay_timer <= 0:
			velocity.y = JUMP_VELOCITY
			_jump_delay_timer = 0.0
	
	# 计算移动方向（基于相机朝向）
	var direction: Vector3 = Vector3.ZERO
	if input_dir.length() > 0.1:
		direction = camera_controller.get_movement_direction(input_dir)
	else:
		input_dir = Vector2.ZERO
	
	# 移动速度参数（优先级：蹲姿 > 奔跑跳跃 > 奔跑 > 行走）
	# _jump_from_run: 奔跑起跳后维持 MAX_RUN_SPEED 作为目标速度，防止空中骤减速
	var max_speed: float = MAX_CROUCH_SPEED if is_crouching else (MAX_RUN_SPEED if (is_running or _jump_from_run) else MAX_WALK_SPEED)
	# 【P3】能力移动速度倍率（如冲刺爆发加速）
	max_speed *= _ability_speed_mult
	var floor_speed_mult: float = 1.0 if is_on_floor() else AIR_CONTROL_FACTOR
	var accel: float = ACCELERATION * floor_speed_mult
	var decel: float = DECELERATION * floor_speed_mult
	
	# 水平移动
	if direction.length() > 0.1:
		var target_vel: Vector3 = direction * max_speed
		# 起步速度提升：从静止开始移动时直接给到30%满速，消除蓄力粘滞感
		var current_horizontal: Vector2 = Vector2(velocity.x, velocity.z)
		if current_horizontal.length() < max_speed * START_BOOST_RATIO and is_on_floor():
			velocity.x = target_vel.x * START_BOOST_RATIO
			velocity.z = target_vel.z * START_BOOST_RATIO
		velocity.x = move_toward(velocity.x, target_vel.x, accel * delta)
		velocity.z = move_toward(velocity.z, target_vel.z, accel * delta)
	else:
		# 奔跑时使用更高的减速度，消除滑行
		var effective_decel: float = RUN_DECELERATION if is_running else decel
		velocity.x = move_toward(velocity.x, 0.0, effective_decel * delta)
		velocity.z = move_toward(velocity.z, 0.0, effective_decel * delta)
	
	move_and_slide()

	# 丝滑度保障：采样切换跳变 + 统一视觉Y平滑（每帧；死亡/蹲姿倒地分支不进此函数）
	_sample_spatial_jump(delta)
	_update_visual_y_smooth(delta)

	# 调试：每30帧输出速度
	if _debug_counter % 30 == 1:
		var horiz = Vector2(velocity.x, velocity.z).length()
		if DEBUG_MODE: debug_print("  >> 移动: dir=" + str(direction) + " vel=" + str(horiz)+ " input_dir=" + str(input_dir))

# ============================================================
# 动画状态机（核心逻辑）
# ============================================================
func _update_animation_state(should_jump: bool, on_floor: bool, horizontal_speed: float, delta: float):
	# --- 受击/投掷覆盖中：不更新动画状态，等待动画完成回调 ---
	if _is_in_one_shot_override:
		# 【尼泊尔·崩溃修复·关键】挥刀期间状态机冻结。下半身跟随在攻击「起手那一刻」
		# 已锁定合成（_play_one_shot_override 用 _state_before_one_shot 作为 lower 基础
		# 状态），整段攻击下半身保持起手时的移动姿态（走路↔挥刀不脱节，不会僵直）。
		return
	
	# --- 过渡动画播放中：不切换状态，等待动画完成回调 ---
	if is_transitioning:
		return
	
	# --- 跳跃/空中动画更新 ---
	if current_state in _AIR_STATES:
		_handle_air_animation(on_floor)
		return
	
	# --- 死亡状态：不更新动画 ---
	if current_state == AnimState.DEATH:
		return
	
	# --- 蹲姿受击倒地：不更新动画 ---
	if current_state == AnimState.CROUCH_HIT_BACK:
		return
	
	# --- 地面状态 ---
	if on_floor:
		# 默认视觉Y偏移为0（站立/行走/奔跑）；蹲姿分支会覆盖为蹲姿偏移
		_target_visual_y = 0.0
		# 跳跃触发
		if should_jump:
			# 蹲伏状态下点击跳跃改为起立（不播放跳跃动画）
			if is_crouching:
				debug_print("蹲伏跳跃: 改为起立")
				_start_stand_transition()
				return
			if is_running and input_dir.y > 0.1:
				# 奔跑状态 → 向前跳跃（仅奔跑状态允许 Jump Forward）
				_jump_from_run = true  # 标记跳跃源自奔跑，维持奔跑速度
				is_running = false
				_change_state(AnimState.JUMP_FORWARD)
				_play_animation(AnimState.JUMP_FORWARD, false, 1.0)
			else:
				# 原地或行走起跳（禁止 Jump Forward）
				_change_state(AnimState.JUMP_UP)
				_play_animation(AnimState.JUMP_UP, false, 1.0)
			return
		
		# 蹲伏状态
		if is_crouching:
			_update_crouch_animation(horizontal_speed)
			return
		
		# 奔跑状态：由 _physics_process 中的退出延迟机制控制 is_running
		# 这里只处理奔跑动画播放
		if is_running:
			_update_run_animation(horizontal_speed)
			return
		
		# 站立 - 行走/横移逻辑
		_update_stand_walk_animation(horizontal_speed)
	
	else:
		# --- 空中状态 ---
		if current_state not in _AIR_STATES:
			# 从地面进入空中（比如从平台边缘掉落）
			# 如果之前是跳跃状态，保持；否则进入下落
			if velocity.y > 0:
				_change_state(AnimState.JUMP_UP)
				_play_animation(AnimState.JUMP_UP, false, 1.0)
			else:
				_change_state(AnimState.JUMP_DOWN)
				_play_animation(AnimState.JUMP_DOWN, false, 1.0)

## 蹲伏动画更新（移动/待机，含动态视觉偏移与空间坐标日志）
func _update_crouch_animation(horizontal_speed: float) -> void:
	if DEBUG_MODE:
		if DEBUG_MODE: debug_print(">> [CROUCH] 正在蹲伏状态, input_dir=" + str(input_dir) + " is_crouching=" + str(is_crouching) + " state=" + str(current_state) + " _is_in_one_shot_override=" + str(_is_in_one_shot_override))
	# 蹲伏移动逻辑：前后左右独立动画
	var has_forward: bool = input_dir.y > 0.1
	var has_backward: bool = input_dir.y < -0.1
	var has_left: bool = input_dir.x < -0.1
	var has_right: bool = input_dir.x > 0.1
	var crouch_speed: float = MAX_CROUCH_SPEED  # 蹲姿动画基准速度
	
	# 动态视觉偏移：蹲姿移动使用较浅的偏移（-0.55），待机使用较深的偏移（-1.0）
	# 蹲姿移动动画的腿部旋转伸展更远，较浅的偏移让脚不陷入地面
	var is_crouch_moving: bool = has_forward or has_backward or has_left or has_right
	if is_crouch_moving:
		_target_visual_y = _crouch_walk_visual_offset()
	else:
		_target_visual_y = _crouch_visual_offset()
	
	# 蹲姿空间坐标日志（每10帧输出一次，对比蹲姿待机vs移动的高度差异）
	if _debug_counter % 10 == 0:
		var ctx = "蹲姿待机"
		if has_forward:
			ctx = "蹲姿前进"
		elif has_backward:
			ctx = "蹲姿后退"
		elif has_left:
			ctx = "蹲姿左移"
		elif has_right:
			ctx = "蹲姿右移"
		_log_spatial_info(ctx)
	
	if has_forward:
		_play_looping(AnimState.CROUCH_WALK_FORWARD, _get_normalized_anim_speed(AnimState.CROUCH_WALK_FORWARD, horizontal_speed, crouch_speed, REFERENCE_CROUCH_ANIM_LEN))
	elif has_backward:
		_play_looping(AnimState.CROUCH_WALK_BACKWARD, _get_normalized_anim_speed(AnimState.CROUCH_WALK_BACKWARD, horizontal_speed, crouch_speed, REFERENCE_CROUCH_ANIM_LEN))
	elif has_left:
		_play_looping(AnimState.CROUCH_STRAFE_LEFT, _get_normalized_anim_speed(AnimState.CROUCH_STRAFE_LEFT, horizontal_speed, crouch_speed, REFERENCE_CROUCH_ANIM_LEN))
	elif has_right:
		_play_looping(AnimState.CROUCH_STRAFE_RIGHT, _get_normalized_anim_speed(AnimState.CROUCH_STRAFE_RIGHT, horizontal_speed, crouch_speed, REFERENCE_CROUCH_ANIM_LEN))
	else:
		if current_state != AnimState.CROUCH_IDLE_AIM:
			_change_state(AnimState.CROUCH_IDLE_AIM)
			_play_animation(AnimState.CROUCH_IDLE_AIM, true, 1.0)

## 奔跑动画更新（含保底速度值解决视角转向加速问题）
func _update_run_animation(horizontal_speed: float) -> void:
	# 使用保底速度值：取实际速度和MAX_RUN_SPEED*85%的较大值
	# 解决视角转动控制方向时，方向变化导致move_toward重新加速，horizontal_speed短暂下降的问题
	# 在不转动视角时，horizontal_speed ≈ MAX_RUN_SPEED=15.0，保底不生效，动画按实际速度播放
	var run_anim_speed: float = max(horizontal_speed, MAX_RUN_SPEED * 0.85)
	# 【修复】上限随能力倍率放宽（冲刺 2x → 上限 3.0），否则冲刺时腿步频跟不上速度=太空步
	var run_speed_scale: float = clamp(run_anim_speed / DESIGN_RUN_SPEED, 0.5, 1.5 * _ability_speed_mult)
	_play_looping(AnimState.RUN, run_speed_scale)

## 站立 - 行走/横移动画更新（前后/左右/待机）
func _update_stand_walk_animation(horizontal_speed: float) -> void:
	var has_forward_input: bool = input_dir.y > 0.1
	var has_backward_input: bool = input_dir.y < -0.1
	var has_side_input: bool = abs(input_dir.x) > 0.1
	
	# 调试日志：行走分支选择
	if _debug_counter % 30 == 1:
		if DEBUG_MODE: debug_print("  >> 行走分支: fwd=" + str(has_forward_input) + " bwd=" + str(has_backward_input) + " side=" + str(has_side_input) + " speed=" + str(horizontal_speed))
	
	if has_forward_input:
		# 向前走（优先使用行走动画，不混合横移）
		_play_looping(AnimState.WALK_FORWARD, _get_normalized_anim_speed(AnimState.WALK_FORWARD, horizontal_speed, DESIGN_WALK_SPEED, REFERENCE_WALK_ANIM_LEN))
		
	elif has_backward_input:
		# 向后走
		_play_looping(AnimState.WALK_BACKWARD, _get_normalized_anim_speed(AnimState.WALK_BACKWARD, horizontal_speed, DESIGN_WALK_SPEED, REFERENCE_WALK_ANIM_LEN))
	
	elif has_side_input:
		# 纯左右横移（无前后输入时使用横移动画）
		if input_dir.x > 0.1:
			_play_looping(AnimState.STRAFE_RIGHT, _get_normalized_anim_speed(AnimState.STRAFE_RIGHT, horizontal_speed, DESIGN_WALK_SPEED, REFERENCE_WALK_ANIM_LEN))
		else:
			_play_looping(AnimState.STRAFE_LEFT, _get_normalized_anim_speed(AnimState.STRAFE_LEFT, horizontal_speed, DESIGN_WALK_SPEED, REFERENCE_WALK_ANIM_LEN))
		
	else:
		# 静止待机
		if current_state != AnimState.IDLE_AIM:
			_change_state(AnimState.IDLE_AIM)
			_play_animation(AnimState.IDLE_AIM, true, 1.0)
		# 站姿待机空间坐标日志（每30帧输出一次，作为基准对比）
		if _debug_counter % 30 == 0:
			_log_spatial_info("站姿待机")

# ============================================================
# 空中动画更新（处理升空→下落→落地切换）
# ============================================================
func _handle_air_animation(on_floor: bool):
	# 【挥刀兼容·关键】一次性动画（挥刀/换弹/受击/投掷）播放中：空中阶段不切换状态机。
	# 否则挥刀中落地会把挥砍动画强行切到 IDLE_AIM → one_shot 状态(32/33)与动画不符：
	# ① 挥砍动画被夺走 → 挥刀被中断但 _is_in_one_shot_override 仍 true → 后续输入全部被吞；
	# ② IDLE_AIM 播完触发 _on_animation_finished → match state=32 → 又恢复 → 二次切换
	#    = 用户看到的"跳跃空中挥刀多次落地 / 下落卡顿"。
	if _is_in_one_shot_override:
		return
	if on_floor:
		# 跳跃延迟期间（蓄力帧已播放但物理跳跃尚未施加），不检查落地
		# 否则会立即将 JUMP_FORWARD/JUMP_UP 覆盖为 IDLE_AIM
		if _jump_delay_timer > 0:
			return
		# on_floor 是在 _physics_process 开头捕获的旧值，_process_movement 可能在同帧
		# 已设置 velocity.y = JUMP_VELOCITY。若速度仍向上说明刚起跳，不检查落地
		if velocity.y > 0.5:
			return
		# Jump Forward：让动画自然播放完成，不强制切换到IDLE_AIM
		# _on_animation_finished 回调会在动画结束时处理落地
		if current_state == AnimState.JUMP_FORWARD:
			_jump_from_run = false
			# 如果动画已播放完毕（不在播放中），落地时直接切换到待机
			if not anim_player.is_playing() or anim_player.current_animation != _anim_name_for(AnimState.JUMP_FORWARD):
				if landing_cooldown_timer <= 0:
					_change_state(AnimState.IDLE_AIM)
					_play_animation(AnimState.IDLE_AIM, true, 1.0)
			return
		# 落地：清除奔跑跳跃标志，回到地面待机（防抖期内不立即切换）
		_jump_from_run = false
		if landing_cooldown_timer <= 0:
			_change_state(AnimState.IDLE_AIM)
			_play_animation(AnimState.IDLE_AIM, true, 1.0)
		return
	
	# 空中的上下阶段切换
	# 上升阶段：velocity.y > 0 时保持 JUMP_UP 动画
	# 滞空阶段：velocity.y 在 0 到 -1.5 之间时，继续播放 JUMP_UP（制造滞空效果）
	# 下落阶段：velocity.y <= -1.5 时切换到 JUMP_DOWN（落地动画）
	# Jump Forward 保持自然完成，不切换为 JUMP_DOWN
	if velocity.y > 0.5 and current_state == AnimState.JUMP_DOWN:
		# 再次上升（罕见情况，如踩到弹跳板）
		_change_state(AnimState.JUMP_UP)
		_play_animation(AnimState.JUMP_UP, false, 1.0)
	elif velocity.y <= -1.5 and current_state == AnimState.JUMP_UP:
		# 开始下落，切换到落地动画（仅JUMP_UP，JUMP_FORWARD不中断）
		_change_state(AnimState.JUMP_DOWN)
		_play_animation(AnimState.JUMP_DOWN, false, 1.0)

# ============================================================
# 蹲伏过渡完成回调
# ============================================================
func _on_transition_done():
	debug_print("过渡完成, 当前状态: " + str(current_state) + ", 蹲伏: " + str(is_crouching) + ", 按住: " + str(_crouch_hold))
	if NEPAL_LOG:
		print("[NEPAL] 过渡完成: state=%s crouch=%s held=%s" % [
			_anim_state_str(current_state), str(is_crouching), str(Input.is_action_pressed("crouch"))])
	match current_state:
		AnimState.STAND_TO_CROUCH:
			is_crouching = true
			_update_collision_height(_crouching_height())
			character_visual.position.y = _crouch_visual_offset()  # 设置蹲下视觉偏移
			# 松开即起：用实时按键状态作为"是否仍按住"的唯一真值来源。
			# 不再依赖 _crouch_hold（释放事件偶发丢失、或同一帧 just_released 与
			# is_action_pressed 冲突时会把它卡成"长按"），也不再要求 press_time<阈值——
			# 否则"按下≥0.2s 但在 0.5s 蹲下过渡途中松开"会落进"保持蹲姿"分支而永久卡蹲。
			# 只要过渡完成时按键已松开（含上述卡蹲死区），就立即起立。
			var _still_held: bool = Input.is_action_pressed("crouch")
			if not _still_held:
				# 键已松开 → 立即起立（peek / 松开即起语义）
				debug_print("蹲下过渡完成且已松键，立即起立")
				_start_stand_transition()
			else:
				# 长按中 → 保持蹲姿
				is_transitioning = false
				transition_timer = 0.0
				_target_visual_y = _crouch_visual_offset()
				character_visual.position.y = _crouch_visual_offset()
				_change_state(AnimState.CROUCH_IDLE_AIM)
				_play_animation(AnimState.CROUCH_IDLE_AIM, true, 1.0)
				debug_print("切换到蹲姿待机, 碰撞体高度: " + str(_crouching_height()))
				_log_spatial_info("蹲下完成")
		AnimState.CROUCH_TO_STAND:
			is_crouching = false
			_update_collision_height(_standing_height())
			_target_visual_y = 0.0
			character_visual.position.y = 0.0  # 视觉模型恢复到站立位置
			is_transitioning = false
			transition_timer = 0.0
			_change_state(AnimState.IDLE_AIM)
			_play_animation(AnimState.IDLE_AIM, true, 1.0)
			debug_print("切换到站姿待机, 碰撞体高度: " + str(_standing_height()))
			_log_spatial_info("起立完成")
	# 【蹲/站过渡中切武器】过渡已自然播完 → 执行挂起的切武器（不跳过过渡动画）
	if _pending_switch_def != null:
		var _pd: WeaponDef = _pending_switch_def
		_pending_switch_def = null
		_do_switch_weapon(_pd)

# ============================================================
# 开始起立过渡
# ============================================================
## 【蹲+挥刀同按·真正完成过渡】过渡被武器输入（挥刀/射击）打断时，必须把蹲/站过渡
## "完整落定"（更新 is_crouching/碰撞体/视觉偏移）再让一次性动画接管。否则：
## ① 只改 state → 相机已 set_crouch 下降、碰撞体未更新 → 挥刀瞬间播站待机动画但相机在
##    蹲位 = "腿弹起蹲姿浮空一瞬间 + 相机抖"；
## ② _on_transition_done 被跳过 → is_crouching 永不更新 → 点按蹲的"自动起立"失效。
func _finish_crouch_transition_now() -> void:
	var _dir_crouch: bool = current_state == AnimState.STAND_TO_CROUCH
	is_transitioning = false
	transition_timer = 0.0
	if _dir_crouch:
		is_crouching = true
		_update_collision_height(_crouching_height())
		_target_visual_y = _crouch_visual_offset()
		character_visual.position.y = _crouch_visual_offset()
		_change_state(AnimState.CROUCH_IDLE_AIM)
	else:
		is_crouching = false
		_update_collision_height(_standing_height())
		_target_visual_y = 0.0
		character_visual.position.y = 0.0
		_change_state(AnimState.IDLE_AIM)

func _start_stand_transition():
	is_transitioning = true
	transition_timer = 0.0
	if NEPAL_LOG:
		print("[NEPAL] 起立过渡开始: state=%s crouch=%s" % [_anim_state_str(current_state), str(is_crouching)])
	camera_controller.set_crouch(false, CROUCH_TRANSITION_DURATION)
	_change_state(AnimState.CROUCH_TO_STAND)
	# 动画播放速度 = 动画原始时长 / 目标过渡时长，使动画在0.1s内播完
	var stand_up_anim = _get_cached_animation(AnimState.CROUCH_TO_STAND)
	var stand_up_speed: float = stand_up_anim.length / CROUCH_TRANSITION_DURATION if stand_up_anim else 1.0
	_play_animation(AnimState.CROUCH_TO_STAND, false, stand_up_speed)
	debug_print("起立: 蹲→站过渡开始")
	_log_spatial_info("起立开始")

# ============================================================
# 碰撞体高度更新
# ============================================================
func _update_collision_height(height: float):
	var capsule = collision_shape.shape as CapsuleShape3D
	if capsule:
		capsule.height = height
		collision_shape.position.y = height / 2.0

# ============================================================
# 换弹+行走动画合成（上下半身混合）
# 运行时将 Reloading 动画的上半身骨骼轨道与行走动画的下半身骨骼轨道合成
# 合成后的动画长度 = Reloading 动画长度，下半身轨道循环填充整个时长
# ============================================================
func _combine_animations():
	var reload_anim: Animation = _get_cached_animation(AnimState.RELOADING)
	if reload_anim == null:
		push_error("Reloading animation not found for combination")
		return

	debug_print("  [合成] Reloading动画长度=" + str(reload_anim.length) + "s 用于合成动画总时长")

	# 循环填充式：[合成状态, 下半身来源状态]
	var looping_combos := [
		[AnimState.RELOAD_WALK_FORWARD, AnimState.WALK_FORWARD],
		[AnimState.RELOAD_WALK_BACKWARD, AnimState.WALK_BACKWARD],
		[AnimState.RELOAD_STRAFE_LEFT, AnimState.STRAFE_LEFT],
		[AnimState.RELOAD_STRAFE_RIGHT, AnimState.STRAFE_RIGHT],
		[AnimState.RELOAD_CROUCH_WALK_FORWARD, AnimState.CROUCH_WALK_FORWARD],
		[AnimState.RELOAD_CROUCH_WALK_BACKWARD, AnimState.CROUCH_WALK_BACKWARD],
		[AnimState.RELOAD_CROUCH_STRAFE_LEFT, AnimState.CROUCH_STRAFE_LEFT],
		[AnimState.RELOAD_CROUCH_STRAFE_RIGHT, AnimState.CROUCH_STRAFE_RIGHT],
		[AnimState.RELOAD_CROUCH_IDLE, AnimState.CROUCH_IDLE_AIM],
	]
	for combo in looping_combos:
		_build_combined_anim(combo[0], reload_anim, combo[1], false)

	# 过渡式：换弹途中蹲下 / 起立
	var transition_combos := [
		[AnimState.RELOAD_STAND_TO_CROUCH, AnimState.STAND_TO_CROUCH],
		[AnimState.RELOAD_CROUCH_TO_STAND, AnimState.CROUCH_TO_STAND],
	]
	for combo in transition_combos:
		_build_combined_anim(combo[0], reload_anim, combo[1], true)

	# 蹲站过渡本体：只替换"持枪手臂"为站姿待机(IDLE_AIM)的持枪姿势，保留
	# Spine/Neck/Head 原动画（蹲站平衡补偿），下半身不变。放在换弹合成之后执行，
	# 确保换弹蹲站变体合成时仍使用原始蹲站过渡动画作下半身来源。
	var stance_transitions := [
		[AnimState.STAND_TO_CROUCH, AnimState.STAND_TO_CROUCH],
		[AnimState.CROUCH_TO_STAND, AnimState.CROUCH_TO_STAND],
	]
	for combo in stance_transitions:
		_build_combined_anim_grip(combo[0], _get_cached_animation(AnimState.IDLE_AIM), combo[1])

	# 蹲姿待机：上半身也用站姿待机（绝对上半身：全局姿态=站姿待机，不随蹲姿 Hips 歪），
	# 下半身保留蹲姿（腿弯曲）。成品长度=蹲姿动画长度。
	_build_combined_anim_grip(AnimState.CROUCH_IDLE_AIM,
		_get_cached_animation(AnimState.IDLE_AIM), AnimState.CROUCH_IDLE_AIM)


# 合成单条动画，注册进 AnimationPlayer 并写入本地缓存
func _build_combined_anim(new_state: AnimState, upper_anim: Animation, lower_state: AnimState, is_transition: bool) -> void:
	var lower_anim: Animation = _get_cached_animation(lower_state)
	if lower_anim == null:
		push_warning("Cannot combine: lower animation missing for " + str(lower_state))
		return

	var new_anim_name: String = _anim_name_for(new_state)
	var combined: Animation
	if is_transition:
		combined = AnimationCombiner.combine_transition(upper_anim, lower_anim, UPPER_BODY_BONES)
	else:
		combined = AnimationCombiner.combine_looping(upper_anim, lower_anim, UPPER_BODY_BONES)

	if not AnimationCombiner.install(anim_player, new_anim_name, combined):
		push_warning("合成动画注册失败（动画名为空）: state=" + str(new_state))
		return

	_anim_cache[new_state] = combined
	debug_print("  [合成%s] %s (length=%ss tracks=%d)" % [
		"-过渡" if is_transition else "",
		new_anim_name, str(combined.length), combined.get_track_count()
	])

# 蹲站过渡专用合成（绝对上半身）：上半身全局姿态恒等于站姿待机，不受蹲站 Hips 旋转影响。
# 原理：Mixamo 蹲站动画的 Hips 在蹲下/起立中大幅旋转；若直接用待机的 Spine 局部值
# （相对父 Hips），上半身会跟随 Hips 歪（"局部轨道合成的物理限制"）。因此对上半身
# 第一根骨骼 Spine（Hips 直接子）逐时刻反推局部旋转 = 蹲站Hips(t)⁻¹ × 待机Spine全局(t)，
# 使 Spine 全局姿态 = 待机全局姿态；其余上半身骨骼（Spine1/2/Neck/Head/手臂）父链已为
# 待机全局，直接用待机局部值。下半身保留原蹲站动画。
func _build_combined_anim_grip(new_state: AnimState, upper_anim: Animation, lower_state: AnimState) -> void:
	var lower_anim: Animation = _get_cached_animation(lower_state)
	if lower_anim == null:
		push_warning("Cannot combine grip: lower animation missing for " + str(lower_state))
		return
	var skel := character_visual.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null:
		return

	var new_anim_name: String = _anim_name_for(new_state)
	var combined := Animation.new()
	combined.length = lower_anim.length
	combined.loop_mode = Animation.LOOP_NONE

	# 1) 非上半身轨道（下半身/脊柱除外的一切）：原蹲站动画原样保留
	for i in lower_anim.get_track_count():
		var sp := str(lower_anim.track_get_path(i))
		if AnimationCombiner.is_upper_body_track(sp, UPPER_BODY_BONES):
			continue
		AnimationCombiner.copy_track(lower_anim, i, combined, -1)

	# 2) 上半身轨道：Spine 绝对反推 + 其余待机局部
	var upper_root_name := "mixamorig_Spine"
	var idle_hips_t := _find_rot_track(upper_anim, "mixamorig_Hips")
	var idle_spine_t := _find_rot_track(upper_anim, upper_root_name)
	var lower_hips_t := _find_rot_track(lower_anim, "mixamorig_Hips")
	for i in upper_anim.get_track_count():
		var sp := str(upper_anim.track_get_path(i))
		if not AnimationCombiner.is_upper_body_track(sp, UPPER_BODY_BONES):
			continue
		var tt: int = upper_anim.track_get_type(i)
		# 注意：必须用"精确路径结尾"匹配 Spine 本体——contains("mixamorig_Spine")
		# 会把 Spine1/Spine2 也误判为 Spine（路径都含该子串），导致它们被写入
		# Spine 的反推值、下游骨骼（Neck/Head/手臂）全局姿态错乱。
		if sp.ends_with(":" + upper_root_name) and tt == Animation.TYPE_ROTATION_3D:
			# Spine：绝对反推轨道（全局=待机 Spine 全局）
			var new_idx := combined.add_track(tt, -1)
			combined.track_set_path(new_idx, upper_anim.track_get_path(i))
			var steps := 40
			for s in range(steps + 1):
				var t: float = lower_anim.length * s / float(steps)
				var lh: Quaternion = _sample_quat(lower_anim, lower_hips_t, t)
				var ih: Quaternion = _sample_quat(upper_anim, idle_hips_t, t)
				var isp: Quaternion = _sample_quat(upper_anim, idle_spine_t, t)
				var spine_global: Quaternion = ih * isp          # 待机 Spine 全局（骨架空间）
				var spine_local: Quaternion = lh.inverse() * spine_global
				combined.track_insert_key(new_idx, t, spine_local)
			combined.track_set_interpolation_type(new_idx, Animation.INTERPOLATION_LINEAR)
		else:
			# 其余上半身骨骼：待机局部（父链已=待机全局）
			AnimationCombiner.copy_track_clipped(upper_anim, i, combined, combined.length)

	if not AnimationCombiner.install(anim_player, new_anim_name, combined):
		push_warning("合成动画注册失败（动画名为空）: state=" + str(new_state))
		return

	_anim_cache[new_state] = combined
	debug_print("  [合成-绝对上半身] %s (length=%ss tracks=%d)" % [
		new_anim_name, str(combined.length), combined.get_track_count()
	])

# 查找动画中指定骨骼的旋转轨道（路径含 bone_substr 且类型为 ROTATION_3D），无则 -1
func _find_rot_track(anim: Animation, bone_substr: String) -> int:
	for t in anim.get_track_count():
		if str(anim.track_get_path(t)).contains(bone_substr) and anim.track_get_type(t) == Animation.TYPE_ROTATION_3D:
			return t
	return -1

# 采样动画旋转轨道在 t 时刻的值（前后关键帧 slerp；t 越界取端点）
func _sample_quat(anim: Animation, track: int, t: float) -> Quaternion:
	if track < 0:
		return Quaternion.IDENTITY
	var kc: int = anim.track_get_key_count(track)
	if kc <= 0:
		return Quaternion.IDENTITY
	if kc == 1 or t <= anim.track_get_key_time(track, 0):
		return anim.track_get_key_value(track, 0)
	if t >= anim.track_get_key_time(track, kc - 1):
		return anim.track_get_key_value(track, kc - 1)
	for k in range(kc - 1):
		var t0: float = anim.track_get_key_time(track, k)
		var t1: float = anim.track_get_key_time(track, k + 1)
		if t >= t0 and t <= t1:
			var f: float = 0.0 if t1 == t0 else (t - t0) / (t1 - t0)
			var q0: Quaternion = anim.track_get_key_value(track, k)
			var q1: Quaternion = anim.track_get_key_value(track, k + 1)
			return q0.slerp(q1, f)
	return anim.track_get_key_value(track, kc - 1)

func _change_state(new_state: AnimState):
	if current_state != new_state:
		previous_state = current_state
		current_state = new_state

# ============================================================
# 循环动画播放辅助：仅在状态变化时播放新动画，否则只更新速度
# 避免 every frame 重复调用 _play_animation 导致动画被反复重置
# ============================================================
func _play_looping(state: AnimState, speed_scale: float):
	if current_state != state:
		_change_state(state)
		_play_animation(state, true, speed_scale)
	else:
		# 同状态，仅更新播放速度（不重启动画）
		anim_player.speed_scale = speed_scale

func _play_animation(state: AnimState, loop: bool, speed_scale: float):
	# 捕获切换前状态（_last_played_state 在下方会被覆盖为当前 state，故先在此记录）
	var prev_state: AnimState = _last_played_state
	var anim_name: String = _anim_name_for(state)
	if anim_name.is_empty() or not anim_player.has_animation(anim_name):
		push_error("动画不存在或未导入: " + anim_name + " (state=" + str(state) + ")")
		return
	
	# 记录本次播放的状态
	_last_played_state = state
	debug_print("  >> _play_animation: 播放动画! state=" + str(state) + " anim=" + anim_name + " loop=" + str(loop) + " speed=" + str(speed_scale) + " is_playing=" + str(anim_player.is_playing()) + " cur=" + anim_player.current_animation)
	
	# 新动画：设置循环模式和播放速度
	var anim = _get_cached_animation(state)
	if anim == null:
		return
	anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	anim_player.speed_scale = speed_scale
	
	# 重置动画位置检测（开始新动画后上一帧位置重置）
	_prev_anim_position = -1.0
	
	# 淡入淡出切换（避免硬切抖动）
	# 自适应混合时长：根据 from->to 的姿态差异/历史跳变量动态决定 blend，
	# 大跳变切换用更长 blend（更多插帧，更丝滑），小跳变保持短响应。
	var blend_time: float = _compute_blend_time(prev_state, state)
	if anim_player.is_playing():
		_anim_op("PLAY@4090_play_anim_fade")
		anim_player.play(anim_name, blend_time)
	else:
		_anim_op("PLAY@4092_play_anim")
		anim_player.play(anim_name)
	# 启动切换混合窗采样：记录切换前手部/根/Y基准，供 _sample_spatial_jump 检测跳变
	_switch_active = true
	_switch_from_state = prev_state
	_switch_to_state = state
	_switch_max_hand_delta = 0.0
	_switch_max_rot_deg = 0.0
	_switch_max_visual_y_delta = 0.0
	if _hand_bone != null:
		_switch_from_hand_pos = _hand_bone.global_position
		_prev_hand_pos = _hand_bone.global_position
	else:
		_prev_hand_pos = Vector3.ZERO
	if character_visual != null:
		_switch_from_visual_quat = character_visual.transform.basis.get_rotation_quaternion()
		_switch_from_visual_y = character_visual.position.y
		_prev_visual_y = character_visual.position.y
	# 站/蹲过渡时长(0.5s)长于普通混合窗，延长采样窗以覆盖整段下沉，避免后段漏监
	if state in _TRANSITION_STATES or \
			prev_state in _TRANSITION_STATES:
		_switch_timer = max(blend_time, CROUCH_TRANSITION_DURATION)
	else:
		_switch_timer = blend_time

# ============================================================
# 受击/投掷一次性动画覆盖播放
# 记录当前状态，播放一次性动画，完成后自动恢复
# ============================================================
# ============================================================
# 丝滑度保障：自适应混合时长 + 空间跳变检测 + 视觉Y平滑
# ============================================================

# 判断某状态是否属于戏剧性/大姿态差异类别（换弹/受击/投掷/跳跃/死亡/蹲姿倒地）
func _is_dramatic(s: AnimState) -> bool:
	return s in [
		AnimState.RELOADING, AnimState.RELOAD_WALK_FORWARD, AnimState.RELOAD_WALK_BACKWARD,
		AnimState.RELOAD_STRAFE_LEFT, AnimState.RELOAD_STRAFE_RIGHT,
		AnimState.RELOAD_CROUCH_WALK_FORWARD, AnimState.RELOAD_CROUCH_WALK_BACKWARD,
		AnimState.RELOAD_CROUCH_STRAFE_LEFT, AnimState.RELOAD_CROUCH_STRAFE_RIGHT,
		AnimState.RELOAD_CROUCH_IDLE, AnimState.RELOAD_STAND_TO_CROUCH, AnimState.RELOAD_CROUCH_TO_STAND,
		AnimState.HIT_REACTION, AnimState.TOSS_GRENADE,
		AnimState.JUMP_UP, AnimState.JUMP_DOWN, AnimState.JUMP_FORWARD,
		AnimState.DEATH, AnimState.CROUCH_HIT_BACK,
	]

# 两状态切换是否属于大姿态差异（需要更长混合）
func _is_big_pose_shift(from: AnimState, to: AnimState) -> bool:
	# 站蹲过渡自身有专门过渡动画，不算大跳变
	if from in _TRANSITION_STATES:
		return false
	if to in _TRANSITION_STATES:
		return false
	return _is_dramatic(from) != _is_dramatic(to)

# 计算切换混合时长：优先用运行时自适应增强值，否则按姿态差异给默认/大值
func _compute_blend_time(from: AnimState, to: AnimState) -> float:
	if from == to:
		return ANIM_FADE_TIME
	# 【修复】跳跃相关切换（起跳↔下落↔落地）用短混合：跳跃动画末帧与下一姿态首帧
	# 差异被 0.35s 大混合放大 → 下落过程"卡顿一下"。跳跃切换应干脆（0.1s 内完成）。
	var jump_states = [AnimState.JUMP_UP, AnimState.JUMP_DOWN, AnimState.JUMP_FORWARD]
	if from in jump_states or to in jump_states:
		return ANIM_FADE_TIME * 0.66   # ≈0.1s
	# 【持刀/挥刀·手部快速回位】挥刀/持刀姿态切到其它状态（挥刀结束恢复、切回步枪）用
	# 短混合（≈0.1s）：否则长混合（0.35~0.5s，含 _auto_blend_boost 自动拉长）会让手
	# 长时间悬在持刀姿势慢慢过渡 → 用户看到"待机手臂/手姿势不对"（实测切回后 1 帧
	# 手部偏差 0.79m、需 ~0.5s 才回持枪位）。攻击结束/换武器语义 = 手快速回目标姿态。
	if from in _NEPAL_ATTACK_STATES \
			or to in _NEPAL_ATTACK_STATES:
		return ANIM_FADE_TIME * 0.66   # ≈0.1s，干脆回位
	# 进入过渡动画(站→蹲/蹲→站/换弹蹲过渡):过渡首帧已对齐当前站/蹲姿态,
	# 用一个很短的交叉淡入(CROUCH_ENTER_BLEND)平滑"待机任意相位→过渡首帧"的snap,
	# 既消除按下Ctrl瞬间姿态硬跳(闪现),又远短于当年0.3s故不会拖影/帧率不均。
	var transition_states = [AnimState.STAND_TO_CROUCH, AnimState.CROUCH_TO_STAND,
			AnimState.RELOAD_STAND_TO_CROUCH, AnimState.RELOAD_CROUCH_TO_STAND]
	if to in transition_states:
		return CROUCH_ENTER_BLEND
	var key: String = str(from) + '->' + str(to)
	if _auto_blend_boost.has(key):
		return _auto_blend_boost[key]
	# 离开过渡动画到稳定姿态(蹲过渡末帧→蹲待机首帧等):两帧姿态可能不对齐,
	# 用较长交叉淡入平滑这段差异,消除'末帧瞬移'。
	if from in transition_states:
		return CROUCH_BLEND_TIME
	if _is_big_pose_shift(from, to):
		return ANIM_FADE_TIME_BIG
	return ANIM_FADE_TIME

# 每帧采样：在切换混合窗内跟踪手部骨骼与视觉根的空间变换，
# 若混合窗内位移/旋转超过阈值，记录跳变事件并自动拉长该切换对的混合时长（自适应插帧）。

func _sample_spatial_jump(delta: float):
	if not _switch_active:
		return
	if character_visual == null:
		return
	# 逐帧瞬时 delta（非"从起点累计"）：平滑下沉每帧≈0.03m 不会被误判，
	# 仅单帧瞬移（>阈值）才记为跳变，避免把"大幅但平滑"的蹲下误报为不丝滑。
	var hand_inst: float = 0.0
	if _hand_bone != null:
		hand_inst = _hand_bone.global_position.distance_to(_prev_hand_pos)
		_prev_hand_pos = _hand_bone.global_position
	var visual_y_inst: float = abs(character_visual.position.y - _prev_visual_y)
	_prev_visual_y = character_visual.position.y
	var visual_rot_deg: float = rad_to_deg(_switch_from_visual_quat.angle_to(character_visual.transform.basis.get_rotation_quaternion()))
	_switch_max_hand_delta = max(_switch_max_hand_delta, hand_inst)
	_switch_max_visual_y_delta = max(_switch_max_visual_y_delta, visual_y_inst)
	_switch_max_rot_deg = max(_switch_max_rot_deg, visual_rot_deg)
	_switch_timer -= delta
	if _switch_timer <= 0.0:
		_switch_active = false
		# 站/蹲过渡现已纳入监控：同样用逐帧瞬时阈值判断是否真有瞬移（平滑下沉不报）
		if _switch_max_hand_delta > SWITCH_HAND_JUMP_THRESHOLD or \
				_switch_max_visual_y_delta > SWITCH_VERTICAL_SNAP_THRESHOLD or \
				_switch_max_rot_deg > SWITCH_ROT_JUMP_THRESHOLD_DEG:
			_spatial_jumps += 1
			# 【修复】明细仅在 DEBUG_MODE 记录且限量 100 条：原先无条件 append
			# 且从不清理 → 长时游玩缓慢内存泄漏（调试数据混入运行时对象）
			if DEBUG_MODE and _spatial_jump_events.size() < 100:
				_spatial_jump_events.append({
					frame = _debug_counter, from = _switch_from_state, to = _switch_to_state,
					hand_delta = _switch_max_hand_delta, visual_y_delta = _switch_max_visual_y_delta,
					rot_deg = _switch_max_rot_deg, anim = anim_player.current_animation,
				})
			# 自适应：把该切换对的混合时长上调，下次切换更丝滑（更多插帧）
			var key2: String = str(_switch_from_state) + "->" + str(_switch_to_state)
			var is_crouch_pair: bool = AnimState.STAND_TO_CROUCH in [_switch_from_state, _switch_to_state] or \
					AnimState.CROUCH_TO_STAND in [_switch_from_state, _switch_to_state]
			var boost_floor: float = CROUCH_BLEND_TIME if is_crouch_pair else ANIM_FADE_TIME_BIG
			var boosted: float = max(boost_floor, _auto_blend_boost.get(key2, ANIM_FADE_TIME) * 1.3)
			_auto_blend_boost[key2] = min(boosted, ANIM_FADE_TIME_MAX)
			if DEBUG_MODE:
				debug_print(">> [SWITCH JUMP] f=%d %s->%s hand=%.3f vy=%.3f rot=%.1f anim=%s" % [_debug_counter, _switch_from_state, _switch_to_state, _switch_max_hand_delta, _switch_max_visual_y_delta, _switch_max_rot_deg, anim_player.current_animation])

# 统一视觉Y偏移平滑（替代各分支散落的 lerp，并修复残留偏移）：
# 非过渡、非换弹覆盖时，每帧把视觉模型Y向目标值收敛；过渡由 _update_transition_visual 处理。
func _update_visual_y_smooth(delta: float):
	if is_transitioning or _is_in_one_shot_override:
		return
	if character_visual == null:
		return
	character_visual.position.y = lerpf(character_visual.position.y, _target_visual_y, clampf(VISUAL_LERP_SPEED * delta, 0.0, 1.0))

# 第三人称刺刀/射击输入（鼠标）：左键=射击(按住连发)，右键=刺刀(单击)。
# 规则（用户定义，全流程）：
#   1) 奔跑(地面)立即打断射击，奔跑中不允许射击（含连发）
#   2) 奔跑中跳跃(空中)允许射击；跳跃落地瞬间停止射击（落地后重新判定状态）
#   3) 换弹中按射击 → 立刻打断换弹并直接恢复待机动画，再开火
#   4) 跳跃中允许刺刀；奔跑(地面)/换弹/射击/刺刀进行中不允许刺刀
#   5) 刺刀进行中不允许打断（射击/换弹/再刺刀均屏蔽）
# 第一人称(V)模式下同一套规则，动作分发到 viewmodel（_fp_vm）。
func _unhandled_input(event: InputEvent) -> void:
	# V 键：第一人称/第三人称切换（任意时刻可切）
	# 【修复】keycode 可能受输入法/键盘布局影响为 0 或变体 → 同时匹配 physical_keycode（物理键位，与布局无关）
	if event is InputEventKey:
		_handle_key_input(event as InputEventKey)
		return
	if event is InputEventMouseButton:
		_handle_mouse_input(event as InputEventMouseButton)

## 键盘输入分发（V 视角切换 / 数字 1-5 武器直选 / Q 上一把 / X 历史逻辑）
func _handle_key_input(k: InputEventKey) -> void:
	if k.pressed and not k.echo and (k.keycode == KEY_V or k.physical_keycode == KEY_V):
		_toggle_view_mode()
		return
	# 【新武器键位】数字键 1-5 直选 / Q 上一把（原 X 循环切换已取消，下方 if false 为历史逻辑，不再触发）
	for _n in [1, 2, 3, 4, 5]:
		if k.pressed and not k.echo and (k.keycode == KEY_1 + (_n - 1) or k.physical_keycode == KEY_1 + (_n - 1)):
			var _wid: String = WEAPON_SLOT_IDS.get(_n, "")
			if _wid != "":
				_select_weapon_by_id(_wid)
			else:
				var _hud := _get_hud()
				if _hud != null and _hud.has_method("show_message"):
					_hud.call("show_message", "该武器槽位暂未开放", 1.0)
			return
	if k.pressed and not k.echo and (k.keycode == KEY_Q or k.physical_keycode == KEY_Q):
		_switch_prev_weapon()
		return
	if false and k.pressed and not k.echo and (k.keycode == KEY_X or k.physical_keycode == KEY_X):
		# 【P3 修复】切枪打断开镜（与换弹/受击/投掷一致）：开镜中按 X → 先关镜再切枪。
		# 否则开镜残留：_enter_scope 隐藏 viewmodel，而切枪重建 viewmodel 时
		# _rebuild_fp_viewmodel 会 set_visible(_fp_mode) 强制显示 → 准镜画面里出现枪/手；
		# 且残留开镜时若 draw 动画在播，_shot_lock(draw锁) 会把整个射击块跳过
		# （连 _exit_scope 都不执行）→ "切枪后枪声消失"。关镜后切枪两者都消除。
		_cancel_scope()
		var _wd: WeaponDef = null   # 函数级声明：下方多个 if 分支共用（switch_next 成功时赋值）
		if _weapon_system != null and _weapon_system.switch_next() != null:
			_wd = _weapon_system.get_current_weapon()
			debug_print("切换武器: %s" % (_wd.id if _wd != null else "?"))
			# 【P3 多武器】把新武器的行为数据(射速/音效/FP视图模型)应用到各子系统。
			# 单武器(AK47)时各字段为空→全部回退原常量，行为零变化；且同武器不重复应用。
		if _wd != null and _wd.id != _applied_weapon_id:
			_apply_weapon_to_subsystems(_wd)
			_applied_weapon_id = _wd.id
			# 【P3 开镜射击】切枪 = 手动干预：中断"射击动画结束后自动重开镜"流程。
			# 切枪会重新播 draw 动画，旧 pending 若不清除会在新武器动画结束后误开镜。
			_scope_shot_cancel = true
			# 【P3 修复】切枪后重算换弹时长：_fp_vm 已换新武器动画库，
			# get_reload_anim_duration 才能读到新 reload 动画时长。
			# 否则 _reload_duration 仍是上一把武器(如 AK47 2.8s)的旧值，
			# M82 的 0.67s 换弹声被 pitch 拉慢 ~4 倍 → 声音低沉怪异。
			# 与角色切换路径(on_character_switched)共用同一算法，两端一致。
			_recompute_reload_duration()
			# 【P3 二期】动态 3P 世界枪同步：切换武器时换 3P 模型。
			# - 切到 AK47：释放动态实例 + 恢复角色内嵌 Weapon_AK47（visible 恢复）。
			# - 切到其它武器（如 M82）：隐藏内嵌 AK47 枪 + 实例化新武器 3P 枪。
			if _wd != null and _wd.weapon_type == "rifle":
				if _dynamic_world_model != null and is_instance_valid(_dynamic_world_model):
					_free_dynamic_world_model()
				# 恢复内嵌 AK47 枪（_ensure_3p_world_model 动态替换时把它隐藏了）
				var _embedded: Node3D = character_visual.find_child("Weapon_AK47", true, false) as Node3D if character_visual != null else null
				if _embedded != null:
					_embedded.visible = true
					_weapon_holder = _embedded
					# 【P3 修复·3P AK 消失/两把 AK】恢复内嵌枪后必须按当前视角模式
					# 重设 cast_shadow：此前 FP 切 M82 时把它设成 SHADOWS_ONLY 遗留，
					# 3P 下恢复 visible 但 cast_shadow 仍是 SHADOWS_ONLY → 实体不渲染
					# → 3P 看不到 AK；反过来 FP 下没设 SHADOWS_ONLY → 3P 枪实体渲染
					# → 与 FP viewmodel 同屏 = 两把 AK。
					_apply_weapon_fp_shadow(_fp_mode)
					if _weapon_rig != null:
						_weapon_rig.skip_follow = false   # AK47 恢复握持跟随
			else:
				_ensure_3p_world_model(_wd)
			# 重新绑定握持（用最新 _weapon_holder：内嵌或动态实例）
			if character_visual != null and _weapon_rig != null and _weapon_skel != null:
				# O2：复用已缓存的 _weapon_holder（角色切换时由 _rebind_weapon_for_visual 刷新），
				# 避免每次按 X 递归 find_child 遍历场景树。握持节点换武器时不变，缓存等价且更快。
				var holder: Node3D = _weapon_holder
				if holder != null:
					var base_cfg: WeaponRigConfig = null
					if char_manager != null and char_manager.get_active_asset() != null:
						base_cfg = char_manager.get_active_asset().weapon_rig_config as WeaponRigConfig
					_weapon_rig.setup(_weapon_skel, holder, _weapon_system.prepare_rig_config(base_cfg))
		return
	# 【P3】能力激活：已改为 InputMap action "ability"（_physics_process 检测，
	# 见 _physics_process 输入区）——比 _unhandled_input 更可靠（绕过 GUI/分发拦截）

## 鼠标输入分发（左键=射击/手雷/尼泊尔轻击，右键=开镜/刺刀/尼泊尔重击）
func _handle_mouse_input(mb: InputEventMouseButton) -> void:
	# 仅死亡时锁输入；站蹲过渡(is_transitioning)期间允许射击/刺刀（用户要求：
	# 蹲下→站立过渡动画中可开枪/刺刀。过渡锁仅用于防蹲伏输入重复触发，
	# 不再拦截武器输入——射击/刺刀是骨骼叠加系统，与过渡动画互不冲突）。
	var base_ok := not is_dead
	# 刺刀进行中：一切输入打断都禁止（规则5）
	var bay_active: bool = _is_bayonet_active()
	# 【P3 多武器】射击锁定：
	# - 切枪后 draw 动画未结束（_fp_vm.is_active）→ 不能立刻射击（等出枪动画播完）
	# - M82 单发：is_shoot()（射击动画播放中）→ 必须等动画结束才能再点
	# - 其他武器（AK）连发时 is_shoot 锁定仅当 _fp_mode 且武器单发
	var _shot_lock: bool = false
	var _cur_w: WeaponDef = null   # 函数级声明：射击锁判定与射击分支（L2681 连发判定）共用
	_cur_w = _weapon_system.get_current_weapon() if _weapon_system != null else null
	if _fp_mode and _fp_vm != null and _fp_vm.is_active():
		# draw/reload/shoot 任一播放中 → 锁射击（切枪 draw 未结束 / 单发射击动画未结束）
		if _fp_vm.is_shoot_locked() and (_cur_w == null or _cur_w.fire_mode != "auto"):
			_shot_lock = true   # 单发锁：射击动画进度未达 fire_rate 间隔；超过即解锁，
			#                    再次点击=新射击硬中断当前动画（中断式连射，非加速）
		elif _fp_vm.is_reload():
			_shot_lock = true   # 换弹中（由 _is_reloading 处理，这里兜底）
		elif _fp_vm.is_active() and _is_draw_anim(_fp_vm):
			_shot_lock = true   # draw 动画未播完：切枪后不能立刻射击
	elif not _fp_mode and _fp_action != null and _fp_action.is_active():
		# 【修复·两人称同步】3P 原先完全没有射击锁：单发武器（狙击/手枪）在 3P 可
		# 无限连点，与 FP 的动画锁节奏完全不同。现与 FP 对齐：单发武器在 3P 射击
		# 包络（时长已注入=fire_rate）期间同样锁射击。
		if _fp_action.is_shoot() and (_cur_w == null or _cur_w.fire_mode != "auto"):
			_shot_lock = true
	if mb.button_index == MOUSE_BUTTON_LEFT:
		_handle_fire_input(mb, base_ok, bay_active, _shot_lock)
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		_handle_aim_input(mb, base_ok, bay_active)

## 左键输入：手雷拉环/投掷 → 尼泊尔轻击 → 射击（含开镜中射击自动关镜）
func _handle_fire_input(mb: InputEventMouseButton, base_ok: bool, bay_active: bool, _shot_lock: bool) -> void:
	# 【手雷投掷手势】当前武器=手雷(gaobao)时，左键不走射击，走：
	#   按下=拉环(plugin)；长按到拉环播完=停末帧(holding)；松开(长按后)=投掷(Throw)；
	#   点按(拉环未播完就松开)=拉环播完自动接待机（4+3 组合）。
	var _is_grenade: bool = false
	if _weapon_system != null and _weapon_system.get_current_weapon() != null:
		_is_grenade = _weapon_system.get_current_weapon().weapon_type == "grenade"
	if _is_grenade:
		if _fp_mode and _fp_vm != null:
			if mb.pressed:
				if base_ok and not bay_active:
					_fp_vm.trigger_pull()
					# 【3P 影子同步】FP 拉环的同时驱动 3P 拉环直驱（影子手臂与 FP 一致）
					_grenade_held = true
					if not _grenade_pulling and not _grenade_throwing:
						_start_grenade_pull()
			else:
				# 【3P 影子同步】松开：FP 持环等待中 → 投掷；拉环进行中（点按）
				# → FP 拉环播完自动 throw_started → _on_fp_throw_started 同步投掷。
				var _was_holding: bool = _fp_vm.is_grenade_holding()
				_fp_vm.release_pull(_was_holding)
				_grenade_held = false
				if _was_holding and not _grenade_throwing:
					_start_grenade_throw()
		else:
			# 【手雷 3P 手势】镜像 FP：按下=拉环；拉环播完仍按住=持环等待（停拉环末帧）；
			# 持环等待中松开=投掷；点按（拉环未完就松开）=拉环播完自动投掷（对齐 FP
			# release_pull 行为）。弃用 _play_one_shot_override(TOSS_GRENADE) 全身动画。
			if mb.pressed and base_ok and not bay_active:
				if not _grenade_held:
					_grenade_held = true
					if not _grenade_pulling and not _grenade_throwing:
						_start_grenade_pull()
			else:
				if _grenade_held:
					_grenade_held = false
					if _grenade_holding and not _grenade_throwing:
						_start_grenade_throw()
		return
	# 【尼泊尔】左键=轻击（FP shoot2=midslash1 由 fp_anim_map 正常播；
	# 3P 播合成挥砍：手臂=轻击挥砍，身体=挥刀那一刻的移动状态 → 腿继续走/跑/跳）。
	# FP 模式下也必播 3P 合成动画：3P 角色 SHADOW_ONLY 投地影子，影子随动画挥砍。
	if _is_nepal_weapon():
		if mb.pressed and base_ok and not bay_active and not _shot_lock \
				and not _nepal_attacking and not _weapon_fire_blocked():
			# 【修复】蹲/站过渡中挥刀：先【真正完成过渡】（更新 is_crouching/碰撞体/
			# 视觉偏移，而非只改 state），再挥刀。否则打断过渡动画致 is_transitioning
			# 永久卡死；静默拒绝则"蹲+挥同时按无反应"。
			if is_transitioning:
				_finish_crouch_transition_now()
			if _is_reloading:
				_finish_reload_flexible()
				_restore_idle_after_reload()
			if _fp_mode and _fp_vm != null:
				_fp_vm.interrupt_shoot()
				_fp_vm.trigger_shoot()
			# 【方案C】手臂直驱挥砍（不烤动画、不进独占状态，下半身继续走状态机）
			_start_nepal_attack(AnimState.NEPAL_ATTACK_LIGHT)
		return
	# 尼泊尔左键=轻击（FP shoot2=midslash1 由 fp_anim_map 正常播；3P 沿用步枪射击/刺刀逻辑）。
	if mb.pressed:
		if base_ok and not bay_active and not _shot_lock:
			# 换弹中射击：先立刻打断换弹并直接恢复待机动画（规则3）
			if _is_reloading:
				_finish_reload_flexible()
				_restore_idle_after_reload()
			# 地面奔跑封锁中（is_fire_blocked）不触发也不记录连发；
			# 奔跑中跳跃(空中)时封锁已解除，可正常射击。
			if not _is_in_one_shot_override and not _weapon_fire_blocked():
				# 【P3 多武器】开镜中射击：M82 射击后立刻自动关镜（动画在后台播），
				# 动画结束由 _process 检测后自动重新开镜（见 _maybe_rescope_after_shot）。
				# 置 pending 的同时清 cancel：cancel 只对"本次"自动重开镜生效。
				if _scoping:
					_cancel_scope()
					_scope_shot_pending = true
					_scope_shot_cancel = false
				if _fp_mode:
					_fp_vm.trigger_shoot()
					if _fp_action != null:
						_fp_action.trigger_shoot_shadow()   # 同步 3P 影子后坐（无音效）
						_fp_action.set_hold(true)
					# 【P3 单发】单发武器不保持连发（松手即停）；连发武器保持。
					# 注意不能用 _cur_w（函数级变量只在 is_active 分支内赋值，idle 时恒 null），
					# 直接用武器系统查询，保证连发武器在 idle 时也能正确开连发。
					var _is_auto: bool = false
					if _weapon_system != null and _weapon_system.get_current_weapon() != null:
						_is_auto = _weapon_system.get_current_weapon().fire_mode == "auto"
					_fp_hold = _is_auto
					_fp_vm.set_hold(_is_auto)
					if _fp_action != null:
						_fp_action.set_hold(_is_auto)
				elif _fp_action != null:
					_fp_action.trigger_shoot()
					# 【修复·两人称同步】3P 原先无条件 set_hold(true)（连发保持）——单发武器
					# （狙击/手枪）在 3P 按住左键变成连发，与 FP 单发语义冲突。现与 FP 一致
					# 按 fire_mode 决定是否保持连发。
					var _is_auto3: bool = false
					if _weapon_system != null and _weapon_system.get_current_weapon() != null:
						_is_auto3 = _weapon_system.get_current_weapon().fire_mode == "auto"
					_fp_hold = _is_auto3
					_fp_action.set_hold(_is_auto3)
	else:
		_fp_hold = false
		if _fp_mode:
			if _fp_vm != null:
				_fp_vm.set_hold(false)
			if _fp_action != null:
				_fp_action.set_hold(false)   # 同步影子后坐的连发保持
		elif _fp_action != null:
			_fp_action.set_hold(false)

## 右键输入：M82 开镜切换 → 尼泊尔重击 → 刺刀
func _handle_aim_input(mb: InputEventMouseButton, base_ok: bool, bay_active: bool) -> void:
	# 【P3 多武器】右键 = 开镜切换（M82 专属，单击 toggle）：
	# 按下时若未开镜 → 开镜；若已开镜 → 关镜。其他武器仍走刺刀（单击）。
	if _weapon_system != null and _weapon_system.get_current_weapon() != null \
			and _weapon_system.get_current_weapon().scopable:
		if mb.pressed and not is_dead:
			# 【P3 修复】切枪动画（draw）播放中不允许开镜：出枪动画还没播完，
			# 此刻开镜会与视图模型/出枪动画竞争（准镜画面异常），等 draw 播完再开镜。
			if _fp_mode and _fp_vm != null and _fp_vm.is_draw():
				return
			# 【P3 开镜射击】手动按右键 = 手动干预：中断自动重开镜流程。
			# （自动关镜路径在左键射击分支内直接调 _exit_scope，不走这里，不受影响）
			_scope_shot_cancel = true
			if _scoping:
				_cancel_scope()
			else:
				_enter_scope()
		return
	elif not mb.pressed:
		return   # M82 release 时已 return，避免后续刺刀逻辑误触发
	# 奔跑(地面)/换弹/刺刀进行中不允许刺刀；射击中允许刺刀（刺刀立即打断射击，
	# 无需等射击动作播完）；跳跃中允许刺刀；受击/投掷等其他一次性覆盖同样不响应。
	# 【尼泊尔】右键=重击（FP cidao1=stab 由 fp_anim_map 正常播；
	# 3P 播合成挥砍：手臂=重击挥砍，身体=挥刀那一刻的移动状态 → 腿继续走/跑/跳）。
	# FP 模式下也必播 3P 合成动画：3P 角色 SHADOW_ONLY 投地影子，影子随动画挥砍。
	if _is_nepal_weapon():
		if mb.pressed and base_ok and not bay_active \
				and not _weapon_fire_blocked() \
				and not _is_reloading and not _nepal_attacking:
			# 【修复】蹲/站过渡中挥刀：先【真正完成过渡】再挥刀（同轻击分支）
			if is_transitioning:
				_finish_crouch_transition_now()
			if _fp_mode and _fp_vm != null:
				_fp_vm.interrupt_shoot()
				_fp_vm.trigger_bayonet()
			# 【方案C】手臂直驱重击挥砍（同轻击）
			_start_nepal_attack(AnimState.NEPAL_ATTACK_HEAVY)
		return
	# 尼泊尔右键=重击（FP cidao1=stab 由 fp_anim_map 正常播；3P 沿用步枪刺刀处理）。
	var can_bayonet: bool = base_ok and not bay_active \
		and not _weapon_fire_blocked() \
		and not _is_reloading and not _is_in_one_shot_override
	if can_bayonet:
		if _fp_mode:
			if _fp_vm != null:
				_fp_vm.interrupt_shoot()  # 正在射击/连发则先停（火光停、动画复位）
				_fp_vm.trigger_bayonet()
			# 同步 3P 影子刺刀（无音效）：FP 下 3P 角色为 SHADOW_ONLY，
			# 其手臂前刺会被投影到地面，使影子随刺刀动作抖动（与射击影子同理）。
			if _fp_action != null:
				_fp_action.interrupt_shoot()
				_fp_action.trigger_bayonet_shadow()
		elif _fp_action != null:
			_fp_action.interrupt_shoot()
			_fp_action.trigger_bayonet()

## FP 手雷投掷开始（FPViewmodelPlayer.throw_started）：同步播 3P 投掷动画。
## FP 视角下 3P 角色 SHADOWS_ONLY → 地上影子做投掷；3P 视角直接由左键松开触发（不走信号）。
func _on_fp_throw_started() -> void:
	if not is_dead and not _is_in_one_shot_override:
		_start_grenade_throw()

# 当前武器子系统是否处于"地面奔跑封锁"（FP/3P 共用同一套奔跑禁射规则）
func _weapon_fire_blocked() -> bool:
	if _fp_mode:
		return _fp_vm != null and _fp_vm.is_fire_blocked()
	return _fp_action != null and _fp_action.is_fire_blocked()

# 【P3 射击锁】当前 FP 视图模型是否正在播"出枪/切枪"动画（draw_preview）。
# 用途：_fp_vm.is_active() 涵盖所有非待机动画（draw/reload/shoot/刺刀），
# 必须单独识别 draw 才能实现"切枪后必须等出枪动画播完才能射击"；
# 而 is_shoot()（单发锁）与 is_reload()（换弹锁）是另一层，勿混淆。
func _is_draw_anim(fp_vm: FPViewmodelPlayer) -> bool:
	return fp_vm != null and fp_vm.is_draw()

# ============================================================
# 【P3 多武器】M82 开镜（右键）：FOV 缩放到 1/4 + PNG 前景覆盖 + 隐藏角色/枪/影子。
# 与 FP/3P 无关（PNG 自带瞄准镜框，画面只看准镜）。
# ============================================================
func _enter_scope() -> void:
	if _scoping:
		return
	_scoping = true
	# 加载 ScopeOverlay（一次性，从 ui/scope_overlay.tscn 实例化）
	if _scope_overlay == null or not is_instance_valid(_scope_overlay):
		var ps: PackedScene = load("res://ui/scope_overlay.tscn")
		if ps == null:
			push_warning("ScopeOverlay: 加载失败 ui/scope_overlay.tscn")
			_scoping = false
			return
		_scope_overlay = ps.instantiate() as CanvasLayer
		add_child(_scope_overlay)
	var cam: Camera3D = camera_controller.camera if camera_controller != null else null
	if cam == null:
		_scoping = false
		return
	# 保存并隐藏 FP/3P 视觉（PNG 前景全屏覆盖，不需要枪/角色/影子）
	_scope_saved_fov = cam.fov
	var _fp_model := _fp_vm.get_model() if _fp_vm != null else null
	if _fp_model != null:
		_scope_saved_fp_visible = _fp_model.visible
	# 1) 隐藏 3P 世界枪（内嵌 Weapon_AK47 / 动态 world_model）——开镜画面里不能出现 3P 枪/手
	if _weapon_holder != null:
		_scope_saved_holder_visible = _weapon_holder.visible
		_weapon_holder.visible = false
	# 【P3 修复·影子丢失】dyn 与 holder 常是同一节点（M82 动态枪两者都指向它）：
	# 若 holder 分支已保存/隐藏，dyn 分支再读 visible 会读到刚设的 false 并保存
	# → 关镜恢复时 dyn 分支用 false 覆盖 holder 的 true 恢复 → 枪被隐藏、影子消失。
	# 同一节点时跳过 dyn 分支（保存/隐藏/恢复都交给 holder）。
	if _dynamic_world_model != null and is_instance_valid(_dynamic_world_model) and _dynamic_world_model != _weapon_holder:
		_scope_saved_dyn_visible = _dynamic_world_model.visible
		_dynamic_world_model.visible = false
	# 2) 关闭阴影投射（避免地面影子干扰开镜画面），必须在隐藏角色之前调用，
	#    否则它内部会强制 character_visual.visible = true 覆盖我们的隐藏。
	_set_character_visual_fp_shadow_only(true)
	# 3) 隐藏 FP/3P 视觉（角色实体、FP viewmodel、火光）
	if _fp_vm != null:
		_fp_vm.set_visible(false)
	if character_visual != null:
		character_visual.visible = false
	if _fp_action != null and _fp_action.muzzle_flash != null:
		_fp_action.muzzle_flash.visible = false
	# 4) 进入 ScopeOverlay（FOV 缩放 + 显示 PNG）
	if _scope_overlay.has_method("enter"):
		_scope_overlay.call("enter", cam, SCOPE_ZOOM_FACTOR)
	else:
		cam.fov = _scope_saved_fov / SCOPE_ZOOM_FACTOR
		_scope_overlay.visible = true
	# 5) 开镜隐藏屏幕中心红点（准镜 PNG 自带十字线，避免双准星）
	var hud := _get_hud()
	if hud != null and hud.has_method("set_crosshair_visible"):
		hud.call("set_crosshair_visible", false)

func _exit_scope() -> void:
	if not _scoping:
		return
	_scoping = false
	var cam: Camera3D = camera_controller.camera if camera_controller != null else null
	# 恢复 FOV（ScopeOverlay.exit 内部已处理）
	if _scope_overlay != null and is_instance_valid(_scope_overlay):
		_scope_overlay.call("exit", cam)
	# 恢复 FP viewmodel 可见性（按开镜前状态恢复，注意 _fp_mode 下 viewmodel 是可见的）
	if _fp_vm != null:
		_fp_vm.set_visible(_scope_saved_fp_visible)
	# 【修复】恢复 3P 角色显隐必须按当前视角模式：
	#   FP 模式 → SHADOWS_ONLY（实体不渲染、只投阴影——这是 FP 下 3P 角色的正确状态）
	#   3P 模式 → ON（正常渲染）
	# 之前无条件 _set_character_visual_fp_shadow_only(false) 把 FP 下的角色恢复成 ON，
	# 导致 FP 开镜→关镜后 3P 角色实体突然出现。
	if _fp_mode:
		_set_character_visual_fp_shadow_only(true)
	else:
		_set_character_visual_fp_shadow_only(false)
	# 恢复 3P 世界枪 / 动态 world_model 可见性（FP 下用 SHADOWS_ONLY，3P 用 ON）
	if _weapon_holder != null:
		_weapon_holder.visible = _scope_saved_holder_visible
		_apply_weapon_fp_shadow(_fp_mode)
	# 【P3 修复·影子丢失】与 _enter_scope 对称：dyn==holder 时跳过，避免用误保存的
	# false 覆盖 holder 的恢复结果（否则关镜后动态枪被隐藏 → 地上枪影消失）。
	if _dynamic_world_model != null and is_instance_valid(_dynamic_world_model) and _dynamic_world_model != _weapon_holder:
		_dynamic_world_model.visible = _scope_saved_dyn_visible
	# 关镜恢复屏幕中心红点
	var hud := _get_hud()
	if hud != null and hud.has_method("set_crosshair_visible"):
		hud.call("set_crosshair_visible", true)
	if cam != null and (not (_scope_overlay != null and is_instance_valid(_scope_overlay) and _scope_overlay.has_method("exit"))):
		cam.fov = _scope_saved_fov

## 【F-02 统一出口】所有"打断开镜"输入（换弹/受击/投掷/跳跃/切角色/切枪/切视角/死亡/射击）
## 统一经本函数退镜，消除散落各处的 if _scoping: _exit_scope() 遗漏/漂移风险。
## 纯转发 + 守卫（_exit_scope 已有 if not _scoping: return），与原本逐点写法行为完全一致，零回归。
func _cancel_scope() -> void:
	_exit_scope()

# 【P3 开镜射击·自动重开镜】每帧检测一次：
# 开镜中按左键 → 立即关镜（_exit_scope）+ 置 _scope_shot_pending=true，
# FP/3P 射击动画在后台播完（is_active() 由 true → false 回待机）后，
# 本函数检测到结束 → _enter_scope() 自动重新开镜。
# 期间切枪/换弹/手动 toggle 开镜/角色切换等手动干预会置 _scope_shot_cancel=true 中断本流程。
# 判定依据"回待机"而非"is_shoot() 下降沿"：shoot_preview 播完会自动回 idle
# （_on_anim_finished → _play_named(idle)），is_active() 随之变 false，二者等价且更稳
# （3P 侧 FPActionRetarget 同样由动作时间轴播完自动 _active=false）。
func _maybe_rescope_after_shot() -> void:
	if not _scope_shot_pending:
		return
	if _scope_shot_cancel:
		_scope_shot_pending = false   # 已被手动干预中断，丢弃本次自动重开镜
		return
	if _scoping or is_dead:
		return
	# 射击动作是否已播完：FP 看视图模型（reload/bayonet/draw 均视为未结束，防误重开镜）
	var _shot_done: bool = false
	if _fp_mode:
		_shot_done = _fp_vm == null or not _fp_vm.is_active()
	else:
		_shot_done = _fp_action == null or not _fp_action.is_active()
	if _shot_done:
		_scope_shot_pending = false
		_enter_scope()

# 把节点下所有 MeshInstance3D 的材质强制为无光照模式（clone 后设置，保留原贴图/颜色），
# 用于枪口火光：任何场景光照/阴影下都恒亮，不受全局光照影响。
func _force_unshaded_recursive(n: Node) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			if mi.mesh != null:
				for s in range(mi.mesh.get_surface_count()):
					var mat: Material = mi.get_active_material(s)
					if mat is StandardMaterial3D:
						var sm: StandardMaterial3D = (mat as StandardMaterial3D).duplicate()
						sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
						mi.set_surface_override_material(s, sm)
		_force_unshaded_recursive(c)

# 第一人称：把 3P 角色实体设为仅投影（SHADOW_ONLY），相机下看不到模型但能见到脚下影子；
# 回到第三人称(enabled=false)恢复为正常投影（ON）。
func _set_character_visual_fp_shadow_only(enabled: bool) -> void:
	character_visual.visible = true
	for mi in character_visual.find_children("*", "GeometryInstance3D", true, false):
		var m := mi as GeometryInstance3D
		if m == null or not (m is MeshInstance3D):
			continue
		# 仅处理蒙皮身体网格；3P 世界枪（skin==null）由 _apply_weapon_fp_shadow 单独处理，避免被这里覆盖
		if (m as MeshInstance3D).skin == null:
			continue
		# enabled=true（FP）：身体只投影不渲染；enabled=false（3P）：恢复正常渲染+投影
		if enabled:
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		else:
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

# 3P 世界枪（Weapon_AK47，skin==null、不在上面蒙皮循环内）的 FP 显隐：
# FP 下用 SHADOWS_ONLY（实体不渲染→抬头不会看到 3P 枪漂浮，但仍投射阴影→地上有枪影）；
# 3P 下恢复 ON（正常渲染+投影）。注意必须保持节点 visible=true，否则连阴影一起消失。
func _apply_weapon_fp_shadow(enabled: bool) -> void:
	if _weapon_holder == null:
		# 【P3 防御】holder 为空时若存在动态 3P 枪，也恢复其 shadow（防止切换视角时漏恢复）
		if _dynamic_world_model != null and is_instance_valid(_dynamic_world_model):
			for mi in _dynamic_world_model.find_children("*", "MeshInstance3D", true, false):
				var m := mi as MeshInstance3D
				if m == null:
					continue
				m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if not enabled else GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		return
	for mi in _weapon_holder.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m == null:
			continue
		if enabled:
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		else:
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

# V 键切换第一人称/第三人称：相机切换 + 3P 角色显隐 + viewmodel 显隐/出枪。
# 逻辑匹配：3P 的换弹/奔跑/跳跃/刺刀状态保持（切换不打断），
# 仅视觉与相机视角切换；下一帧起输入规则自动分发到对应子系统。
func _toggle_view_mode() -> void:
	# 【P3 修复·同屏 bug】切视角打断开镜（与切枪/换弹/受击/投掷一致）：
	# 开镜中按 V → 先关镜再切视角。否则切到 FP 时下方 _fp_vm.set_visible(true)
	# 会强制显示 viewmodel → "第一人称枪/手 与 开镜准镜 同屏"（3P 开镜→V→FP 必现）。
	# 同时中断"开镜射击自动重开镜"流程（手动干预）。
	_cancel_scope()
	_scope_shot_cancel = true
	_fp_mode = not _fp_mode
	if _fp_mode:
		# 隐藏 3P 角色实体但保留阴影投射（SHADOW_ONLY），
		# 使第一人称下仍能看到自己脚下的影子（Bug: FP 看不到 3P 影子）。
		_set_character_visual_fp_shadow_only(true)
		# 3P 世界枪（Weapon_AK47，skin==null）FP 下用 SHADOWS_ONLY：实体不渲染（不挡视野）、仍投影（地上有枪影）。
		_apply_weapon_fp_shadow(true)
		if _fp_vm != null:
			_fp_vm.set_visible(true)
		if _is_reloading:
			# 切进 FP 中途换弹：第一人称【续播】动画到当前进度（不再从 0 重播），
			# 与 3P 保持同一相位；主时钟 _reload_elapsed 继续走到 _reload_duration 收尾。
			# 【关键】3P 换弹声由 _fp_action 的 _sfx_player_reload 播放，该播放器独立于 3P
			# 角色是否可见（FP 下角色仅 SHADOW_ONLY，但音频节点常驻、照常发声）。因此切进 FP
			# 【不停止】3P 换弹声——让它按原 pitch 一路播到换弹结束，切视角时声音完全连续，
			# 既无突兀变调、也无"从头重播"。FP viewmodel 只续播动画(_play_named+seek 到 _prog)，
			# 不另起换弹声(play_sfx=false)，避免与仍在播的 3P 声叠加成双声。
			# 换弹被打断/自然结束统一由 _finish_reload_flexible 调 _fp_action.stop_reload() 收尾。
			# （反向 FP→3P 同理：FP 声由 _fp_vm._sfx 播放，切回 3P 也不停，声音连续。）
			var _remain := _reload_duration - _reload_elapsed
			if _remain < 0.0:
				_remain = 0.0
			var _prog := 0.0
			if _reload_duration > 0.01:
				_prog = clampf(_reload_elapsed / _reload_duration, 0.0, 0.999)
			else:
				_remain = 2.2   # 兜底：换弹时长未取到，按默认整段播
			# play_sfx=false：FP 不重播换弹声（3P 声仍在连续播放，避免双声/变调）
			_fp_vm.trigger_reload_duration(_remain, _prog, false)
		else:
			_fp_vm.trigger_draw()          # 出枪动画
		if _camera_ctrl != null:
			# 【P3 多武器 FOV】传入当前武器 FP 摆放配置的 fov（预览场景调的 fov=60，
			# 否则 set_first_person 走默认 70 → 枪在画面里大小/位置观感与预览不一致）。
			var _fpv: float = _fp_vm.get_fov() if _fp_vm != null else 70.0
			_camera_ctrl.set_first_person(true, _fpv)
		# 3P 叠加动作若在播（刺刀/射击），立即收尾，避免切回时残留
		if _fp_action != null:
			_fp_action.interrupt_shoot()
			_fp_action.set_hold(false)   # 清掉 3P 残留的连发保持，FP 由自身输入管理
	else:
		# 回到第三人称：恢复 3P 角色实体可见 + 正常投射阴影
		_set_character_visual_fp_shadow_only(false)
		character_visual.visible = true
		# 恢复 3P 世界枪正常渲染+投影
		_apply_weapon_fp_shadow(false)
		# 【P3 防御】动态 3P 枪（M82）：确保切回 3P 后可见（防止 FP 切换时 visible 被误改）
		if _dynamic_world_model != null and is_instance_valid(_dynamic_world_model):
			_dynamic_world_model.visible = true
		if _fp_vm != null:
			_fp_vm.set_visible(false)
		if _camera_ctrl != null:
			_camera_ctrl.set_first_person(false)

# 【修复】按当前视角模式（_fp_mode）重设 3P 角色与武器的显隐状态。
# 用于角色切换后：FP 下切换角色 → 新角色必须同样 SHADOWS_ONLY（否则与
# FP viewmodel 穿模）；3P 下切换 → 保持正常渲染 ON。与 _toggle_view_mode
# 的 FP/3P 分支逻辑一致，保证切换角色后状态不回退。
func _apply_view_mode_to_visual() -> void:
	if character_visual == null:
		return
	if _fp_mode:
		_set_character_visual_fp_shadow_only(true)
		_apply_weapon_fp_shadow(true)
	else:
		_set_character_visual_fp_shadow_only(false)
		_apply_weapon_fp_shadow(false)

# 换弹被射击打断后：直接恢复对应姿态的待机动画（站/蹲），
# 不等状态机下一帧自然切换，保证"打断干脆"。
func _restore_idle_after_reload() -> void:
	var idle_state: AnimState = AnimState.CROUCH_IDLE_AIM if is_crouching else AnimState.IDLE_AIM
	_change_state(idle_state)
	_play_animation(idle_state, true, 1.0)

func _play_one_shot_override(state: AnimState):
	# 记录当前状态，用于动画结束后恢复
	# 如果已经在一次性动画覆盖中（如换弹中再按R），保持原有状态记录，不覆盖
	if not _is_in_one_shot_override:
		_state_before_one_shot = current_state
	_is_in_one_shot_override = true
	
	# 如果是换弹，根据当前状态选择合成动画（行走+换弹或蹲姿+换弹）
	if state == AnimState.RELOADING:
		var reload_state = _get_reload_state_for_current()
		if reload_state != state and _get_cached_animation(reload_state) != null:
			state = reload_state
			debug_print("换弹: 使用合成动画 " + str(state))
	# 【尼泊尔】轻击/重击：先按「挥刀那一刻的移动状态」合成一次性动画（手臂=挥砍，
	# 身体=base_state 原动画循环铺满），再走通用播放；_state_before_one_shot 上面刚记录。
	# 【挥刀兼容·起手即锁定移动意图】点按移动键同时挥刀时，current_state 可能仍是待机
	# （input 刚按下、状态机尚未切换），若用 current_state 作下半身基础，挥刀起手会合成成
	# 待机，随后 _nepal_maybe_follow_lower 立刻重合成一次（stop+install+play+seek）→ 挥刀迟钝。
	# 改为直接用「挥刀那一刻的输入意图」（_nepal_lower_state_now）。
	if state == AnimState.NEPAL_ATTACK_LIGHT or state == AnimState.NEPAL_ATTACK_HEAVY:
		if not _is_in_one_shot_override:
			_state_before_one_shot = _nepal_lower_state_now(_is_on_floor())
		# 记录挥刀起手时刻（供 _nepal_maybe_follow_lower 起手保护/限频使用）
		_nepal_atk_start_ms = Time.get_ticks_msec()
		_nepal_last_follow_ms = -1
		if NEPAL_LOG:
			print("[NEPAL] 挥刀起手 %s: base=%s crouch=%s run=%s on_floor=%s input=%s" % [
				"轻击" if state == AnimState.NEPAL_ATTACK_LIGHT else "重击",
				_anim_state_str(_state_before_one_shot), str(is_crouching), str(is_running),
				str(_is_on_floor()), str(input_dir)])
	if state == AnimState.NEPAL_ATTACK_LIGHT:
		_install_nepal_attack(state, _nepal_light_arms)
	elif state == AnimState.NEPAL_ATTACK_HEAVY:
		_install_nepal_attack(state, _nepal_heavy_arms)
	_change_state(state)
	# 换弹时长以第一人称 reload 动画为基准：3P 换弹动画（各变体长度不一，Reloading
	# 本体含回位尾巴）按 speed_scale 适配，保证恰好 _reload_duration(=FP时长) 秒播完。
	var _spd := 1.0
	if _is_reload_state(state):
		var _ran: Animation = _get_cached_animation(state)
		if _ran != null:
			_spd = _reload_speed_scale(_ran.length)
	_play_animation(state, false, _spd)
	if _is_reload_state(state):
		_is_reloading = true
		if _reload_duration <= 0.01:
			_reload_duration = RELOAD_DEFAULT_DURATION
		_reload_elapsed = 0.0
	debug_print("一次性动画覆盖: " + str(state) + " (之前状态: " + str(_state_before_one_shot) + ")")

# ============================================================
# 根据当前状态选择对应的换弹合成动画
# ============================================================
func _get_reload_state_for_current() -> AnimState:
	# 根据当前状态选择对应的换弹合成动画
	# 优先使用 current_state 判断
	if current_state == AnimState.WALK_FORWARD:
		return AnimState.RELOAD_WALK_FORWARD
	elif current_state == AnimState.WALK_BACKWARD:
		return AnimState.RELOAD_WALK_BACKWARD
	elif current_state == AnimState.STRAFE_LEFT:
		return AnimState.RELOAD_STRAFE_LEFT
	elif current_state == AnimState.STRAFE_RIGHT:
		return AnimState.RELOAD_STRAFE_RIGHT
	# 蹲姿状态
	elif current_state == AnimState.CROUCH_WALK_FORWARD:
		return AnimState.RELOAD_CROUCH_WALK_FORWARD
	elif current_state == AnimState.CROUCH_WALK_BACKWARD:
		return AnimState.RELOAD_CROUCH_WALK_BACKWARD
	elif current_state == AnimState.CROUCH_STRAFE_LEFT:
		return AnimState.RELOAD_CROUCH_STRAFE_LEFT
	elif current_state == AnimState.CROUCH_STRAFE_RIGHT:
		return AnimState.RELOAD_CROUCH_STRAFE_RIGHT
	# 如果 current_state 是待机，但玩家正在移动，使用 input_dir 推断
	if is_crouching:
		if input_dir.y > 0.1:
			return AnimState.RELOAD_CROUCH_WALK_FORWARD
		elif input_dir.y < -0.1:
			return AnimState.RELOAD_CROUCH_WALK_BACKWARD
		elif input_dir.x < -0.1:
			return AnimState.RELOAD_CROUCH_STRAFE_LEFT
		elif input_dir.x > 0.1:
			return AnimState.RELOAD_CROUCH_STRAFE_RIGHT
		else:
			# 蹲姿待机：使用蹲姿待机换弹合成动画
			return AnimState.RELOAD_CROUCH_IDLE
	else:
		if input_dir.y > 0.1:
			return AnimState.RELOAD_WALK_FORWARD
		elif input_dir.y < -0.1:
			return AnimState.RELOAD_WALK_BACKWARD
		elif input_dir.x < -0.1:
			return AnimState.RELOAD_STRAFE_LEFT
		elif input_dir.x > 0.1:
			return AnimState.RELOAD_STRAFE_RIGHT
	# 默认：使用原始换弹动画
	return AnimState.RELOADING

# ============================================================
# 恢复一次性动画结束后回到之前的状态
# ============================================================
func _restore_state_after_one_shot():
	# 恢复到之前的状态
	var restore_state = _state_before_one_shot
	# 如果之前的状态是不可恢复的（如过渡、死亡），回退到待机
	if restore_state in [AnimState.DEATH, AnimState.STAND_TO_CROUCH, AnimState.CROUCH_TO_STAND, AnimState.CROUCH_HIT_BACK]:
		restore_state = AnimState.IDLE_AIM
	# 【修复】空中挥刀（轻击/重击）结束落地：之前是跳跃状态但已落地 → 直接回待机，
	# 否则恢复 JUMP_DOWN 会重复播下落动画 → 观感"多次落地"。
	if restore_state in _AIR_STATES:
		if _is_on_floor():
			restore_state = AnimState.IDLE_AIM
		elif restore_state == AnimState.JUMP_UP:
			# 【挥刀兼容】空中挥刀结束仍滞空：直接切下落（跳过 JUMP_UP 重播，
			# 否则升空动画又播一遍 → 观感"下落前先顿一下/多次落地"）。
			restore_state = AnimState.JUMP_DOWN
	# 如果之前在蹲下，恢复到蹲姿待机
	if is_crouching and restore_state == AnimState.IDLE_AIM:
		restore_state = AnimState.CROUCH_IDLE_AIM
	# 【蹲+挥刀·peek 起立】点按蹲(peek)被挥刀打断后：挥刀结束时键已松开 → 不能停在蹲姿
	# （否则"蹲下自动起立失效"）——直接完成起立（碰撞体/视觉/相机全部恢复站立）。
	# ⚠️ 判定用【restore_state】而非 is_crouching：挥刀期间松蹲走"即时路径"已把
	# is_crouching 改成 false（此时 restore 仍是起手锁定的 CROUCH_IDLE_AIM），
	# 若用 is_crouching 判定会漏判 → 恢复成"蹲动画+站碰撞体+相机已起立"错乱
	# （正是用户看到的"腿弹起蹲姿浮空/自动起立失效"）。
	if restore_state == AnimState.CROUCH_IDLE_AIM \
			and (not Input.is_action_pressed("crouch") or not is_crouching):
		restore_state = AnimState.IDLE_AIM
		if is_crouching:
			is_crouching = false
			_update_collision_height(_standing_height())
			_target_visual_y = 0.0
			character_visual.position.y = 0.0
			camera_controller.set_crouch(false, CROUCH_TRANSITION_DURATION)
	if NEPAL_LOG:
		print("[NEPAL] 挥刀结束恢复: base=%s → restore=%s on_floor=%s crouch=%s" % [
			_anim_state_str(_state_before_one_shot), _anim_state_str(restore_state),
			str(_is_on_floor()), str(is_crouching)])
	# 【落地防抖】恢复为地面状态时置 cooldown：否则 _handle_air_animation 下一帧
	# 检测落地又切一次 IDLE + _play_animation → 动画重启 = 卡顿/多次落地观感。
	if restore_state not in _AIR_STATES:
		landing_cooldown_timer = LANDING_COOLDOWN
	_change_state(restore_state)
	var is_loop: bool = restore_state not in ONE_SHOT_STATES
	_play_animation(restore_state, is_loop, 1.0)
	debug_print("一次性动画结束，恢复到: " + str(restore_state))

# ============================================================
# 判断指定状态是否为换弹相关状态
# ============================================================
func _is_reload_state(state: AnimState) -> bool:
	return state in [
		AnimState.RELOADING,
		AnimState.RELOAD_WALK_FORWARD, AnimState.RELOAD_WALK_BACKWARD,
		AnimState.RELOAD_STRAFE_LEFT, AnimState.RELOAD_STRAFE_RIGHT,
		AnimState.RELOAD_CROUCH_WALK_FORWARD, AnimState.RELOAD_CROUCH_WALK_BACKWARD,
		AnimState.RELOAD_CROUCH_STRAFE_LEFT, AnimState.RELOAD_CROUCH_STRAFE_RIGHT,
		AnimState.RELOAD_CROUCH_IDLE,
		AnimState.RELOAD_STAND_TO_CROUCH, AnimState.RELOAD_CROUCH_TO_STAND,
	]

# 是否跳跃状态（跳跃时枪口固定端枪方向，不跟手臂挥动）
func _is_jump_state() -> bool:
	return current_state in _AIR_STATES

# 递归查找 CameraController 节点（相机俯仰驱动器），与场景节点命名解耦。
func _find_camera_controller() -> CameraController:
	var stack: Array[Node] = [self]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is CameraController:
			return n as CameraController
		for ch in n.get_children():
			stack.push_back(ch)
	return null

# ============================================================
# 换弹过程中切换动画（保持进度比例）
# 从当前换弹动画切换到另一个换弹合成动画，保持进度比例一致
# ============================================================
func _switch_reload_animation(new_state: AnimState):
	var new_anim = _get_cached_animation(new_state)
	if new_anim == null:
		return

	# 用统一的换弹进度（_reload_elapsed / _reload_duration）对齐到新变体，
	# 而非依赖当前变体自身播放位置——避免不同长度变体间换算错位导致重播。
	var progress: float = _reload_progress()

	# 切换到新动画，使用淡入淡出过渡
	_change_state(new_state)
	new_anim.loop_mode = Animation.LOOP_NONE
	# 重算 speed_scale 使新变体恰好在 _reload_duration 内播完（与 _play_one_shot_override 一致）：
	# 变体长 = 3P Reloading 原长(reload_anim.length)，而 _reload_duration 是 FP/3P 均值，
	# 二者不等时需按比例缩放，否则新变体以自然速播放会与固定换弹计时脱节（提前定格/中途被切走）。
	anim_player.speed_scale = _reload_speed_scale(new_anim.length)
	_anim_op("PLAY@5014_reload_switch")
	anim_player.play(_anim_name_for(new_state), ANIM_FADE_TIME)

	# 保持换弹进度
	var new_pos = progress * new_anim.length
	if new_pos > 0.01:
		_anim_op("SEEK@5019_reload_switch")
		anim_player.seek(new_pos, true)
	debug_print("换弹动画切换: " + str(previous_state) + " -> " + str(new_state) + " 进度=" + str(snapped(progress, 0.01)))

# ============================================================
# 换弹期间根据移动方向动态切换合成动画
# 每帧检测输入方向，如果当前动画与输入不匹配，切换到对应合成动画
# ============================================================
func _update_reload_animation_for_movement():
	var target_state = _get_reload_state_for_current()
	if target_state != current_state and _get_cached_animation(target_state) != null:
		_switch_reload_animation(target_state)

# 换弹统一进度：已进行时长方 / 总时长，范围 [0,1]。
# 所有换弹变体（含蹲/站/移动）长度均等于 3P Reloading 原长(reload_anim.length)，
# 经由 speed_scale 适配到 _reload_duration，因此该比例可直接映射到任意变体的播放位置，实现无缝切换。
func _reload_progress() -> float:
	if _reload_duration <= 0.01:
		return 0.0
	return clamp(_reload_elapsed / _reload_duration, 0.0, 1.0)

# ============================================================
# 换弹固定时长结束：结束覆盖状态，下一帧由状态机根据当前
# 输入 / 蹲姿 / 奔跑灵活切换到应处的动画（而非僵硬地回到换弹前状态）
# ============================================================
func _finish_reload_flexible():
	if not _is_reloading:
		return
	_is_reloading = false
	_is_in_one_shot_override = false
	# 【修复】换弹被打断（射击等）或自然结束时，统一停掉换弹音：
	# 3P(_fp_action) 与 FP(_fp_vm) 各自播放器都停，避免"动作已收尾但换弹声还在响"。
	# 自然结束时声音已按 _reload_duration 拉伸到尾，此处 stop 仅切掉<1帧尾音，无感。
	if _fp_action != null:
		_fp_action.stop_reload()
	if _fp_vm != null:
		_fp_vm.stop_reload_sound()
	debug_print("换弹固定时长结束，灵活切换动画")

## 【P3】能力注册：把新 Ability 子类实例加入 _abilities（每帧可激活/更新）
func _register_abilities() -> void:
	var sb := SprintBurst.new()
	# 参数用类内 export 默认（burst 1.2s / 倍率 2.0 / 冷却 1.5s）——不要硬编码覆盖，
	# 否则改 export 默认不生效（曾踩坑：旧 0.8/1.8/3.0 被写死）
	_abilities.append(sb)
	debug_print("能力注册: %d 个" % _abilities.size())

## 【P3】尝试激活能力（G 键/输入入口）：依次问 can_activate，首个可用者激活
func _try_activate_ability() -> void:
	if _active_ability != null:
		return
	for ab in _abilities:
		var a: Ability = ab as Ability
		if a != null and a.can_activate(self):
			a.activate(self)
			_active_ability = a
			debug_print("能力激活: %s" % a.id)
			# 【修复】激活反馈：HUD 弹提示（否则冲刺爆发这种无动画能力"看不出反应"，
			# 用户以为没生效。冷却中连按 Q 也会沉默 → 一并提示冷却状态）
			var hud := _get_hud()
			if hud != null and hud.has_method("show_message"):
				hud.call("show_message", "冲刺爆发！", 1.0)
			return
	# 所有能力都在冷却/不可用：给个"冷却中"反馈，避免连按 Q 无反应被误解为没绑键
	var hud2 := _get_hud()
	if hud2 != null and hud2.has_method("show_message"):
		hud2.call("show_message", "能力冷却中", 0.8)

## 【P3】每帧推进：冷却 + 激活中能力 update（返回 false → finish）
func _update_abilities(delta: float) -> void:
	for ab in _abilities:
		var a: Ability = ab as Ability
		if a != null:
			a.tick(self, delta)   # 【修复】虚方法推进冷却，消除 is SprintBurst 类型特判
	if _active_ability != null:
		if not _active_ability.update(self, delta):
			var fin: Ability = _active_ability
			_active_ability = null
			fin.finish(self)
			debug_print("能力结束: %s" % fin.id)

## 【封装】供 Ability 子类查询一次性覆盖状态（替代字符串反射 get("_is_in_one_shot_override")，
## 私有成员改名后 get() 会静默返回 null 而非报错）
func is_in_one_shot_override() -> bool:
	return _is_in_one_shot_override

## 【封装】能力速度倍率读写（替代 Ability 里的 player.set("_ability_speed_mult", ...)）
func set_ability_speed_mult(v: float) -> void:
	_ability_speed_mult = v

## 【P3】强制结束激活中的能力（角色切换/死亡时调用，防止残留加速）
func _force_finish_ability() -> void:
	if _active_ability != null:
		var ab := _active_ability
		_active_ability = null
		ab.finish(self)
		debug_print("能力强制结束: %s" % ab.id)

# ============================================================
# 动画完成信号回调
# ============================================================
func _on_animation_finished(anim_name: String):
	# 仅处理当前状态对应的动画完成
	debug_print("  >> 动画完成信号! anim=" + anim_name + " 当前状态=" + str(current_state) + " _last_played=" + str(_last_played_state))
	match current_state:
		AnimState.STAND_TO_CROUCH, AnimState.CROUCH_TO_STAND:
			debug_print("过渡动画完成，调用 _on_transition_done()")
			_on_transition_done()
		
		AnimState.JUMP_UP:
			# 跳跃动画结束，检查是否已落地
			if is_on_floor():
				_jump_from_run = false
				# 【落地防抖】这里已切回待机，必须置 landing_cooldown_timer，
				# 否则 _handle_air_animation 下一帧检测到落地又切一次 IDLE_AIM +
				# _play_animation → 动画重启 = "跳跃下落卡顿一下"（任何武器）。
				landing_cooldown_timer = LANDING_COOLDOWN
				_change_state(AnimState.IDLE_AIM)
				_play_animation(AnimState.IDLE_AIM, true, 1.0)
			else:
				# 还在空中，切为下落
				_change_state(AnimState.JUMP_DOWN)
				_play_animation(AnimState.JUMP_DOWN, false, 1.0)
		
		AnimState.JUMP_FORWARD:
			# 跑步跳跃动画自然完成落地，不切换到JUMP_DOWN
			# 不论是否落地，都不添加下落动画，让动画自然完成
			_jump_from_run = false
			if is_on_floor():
				landing_cooldown_timer = LANDING_COOLDOWN   # 落地防抖（同上）
				_change_state(AnimState.IDLE_AIM)
				_play_animation(AnimState.IDLE_AIM, true, 1.0)
			# 如果还在空中，不做任何切换，保持JUMP_FORWARD最终帧
			# _handle_air_animation 会在落地时处理
		
		AnimState.JUMP_DOWN:
			# 下落动画结束，如果已落地就切回待机
			if is_on_floor():
				_jump_from_run = false
				landing_cooldown_timer = LANDING_COOLDOWN   # 落地防抖（同上）
				_change_state(AnimState.IDLE_AIM)
				_play_animation(AnimState.IDLE_AIM, true, 1.0)
		
		AnimState.HIT_REACTION, AnimState.TOSS_GRENADE:
			# 受击/投掷结束，回到之前的状态
			_is_in_one_shot_override = false
			_restore_state_after_one_shot()

		AnimState.NEPAL_ATTACK_LIGHT, AnimState.NEPAL_ATTACK_HEAVY:
			# 尼泊尔轻击/重击结束：复位 one-shot 覆盖，回到之前的状态
			if NEPAL_LOG:
				print("[NEPAL] 挥刀动画播完: anim=%s state=%s on_floor=%s" % [
					anim_name, _anim_state_str(current_state), str(_is_on_floor())])
			_is_in_one_shot_override = false
			_restore_state_after_one_shot()

		AnimState.DEATH:
			# 死亡动画结束：保持旋转锁定，开始自动复活倒计时。
			# 注意：旋转锁定必须持续到 _resurrect() 真正起身时才解除
			# （_resurrect 内已 set_rotation_locked(false)），否则在倒计时躺地窗口内
			# 鼠标水平移动会转动尸体朝向（见 bug 反馈：K 倒地后仍能通过视角转角色）。
			_death_await_revive = true
			_death_revive_timer = DEATH_REVIVE_DELAY
		
		AnimState.CROUCH_HIT_BACK:
			# 蹲姿受击倒地结束：与 K 键死亡一致，起身恢复到站立待机。
			# （此前恢复到 CROUCH_IDLE_AIM 会保持蹲姿，与 K 死亡逻辑不一致，用户反馈为 bug）
			_is_in_crouch_hit_back = false
			is_crouching = false
			_crouch_hold = false
			_crouch_press_time = 0.0
			camera_controller.set_crouch(false, CROUCH_TRANSITION_DURATION)
			_update_collision_height(_standing_height())
			# 视觉模型 Y 偏移必须复位到站立（0）：蹲姿时 character_visual.position.y
			# 为负值 _crouch_visual_offset()（下沉），站立行走分支不会自动 lerp 回 0，
			# 漏掉这一步会导致起身站立后双腿仍陷在地面里。
			_target_visual_y = 0.0
			character_visual.position.y = 0.0
			camera_controller.set_rotation_locked(false)
			_change_state(AnimState.IDLE_AIM)
			_play_animation(AnimState.IDLE_AIM, true, 1.0)
		
		AnimState.RELOADING, AnimState.RELOAD_WALK_FORWARD, AnimState.RELOAD_WALK_BACKWARD, AnimState.RELOAD_STRAFE_LEFT, AnimState.RELOAD_STRAFE_RIGHT, AnimState.RELOAD_CROUCH_WALK_FORWARD, AnimState.RELOAD_CROUCH_WALK_BACKWARD, AnimState.RELOAD_CROUCH_STRAFE_LEFT, AnimState.RELOAD_CROUCH_STRAFE_RIGHT, AnimState.RELOAD_CROUCH_IDLE:
			# 换弹动画自然结束：若固定时长计时仍在跑则以计时到期为准；
			# 否则（动画比固定时长短）在此结束，并交由状态机灵活切换
			if _is_reloading:
				_finish_reload_flexible()
		

# ============================================================
# 死亡处理
# ============================================================
# 统一清 FP 子系统：停 3P 刺刀/射击/换弹、清连发保持、FP 视图模型强制回 idle。
# 死亡/复活/切换角色共用，避免"死亡中换弹/连发残留、复活续发"或卡在一次性动画分支。
func _reset_fp_state() -> void:
	if _fp_action != null:
		_fp_action.stop_reload()     # 停 3P 换弹音/影子换弹动作
		_fp_action.interrupt_shoot() # 停射击后坐
		_fp_action.set_hold(false)   # 清连发保持
	if _fp_vm != null:
		_fp_vm.set_hold(false)
		_fp_vm.stop_reload_sound()   # 停 FP 换弹音（通用 _sfx 播放器，reset_to_idle 不会停它）
		_fp_vm.reset_to_idle()       # 清残留换弹/出枪动画，回 idle

func _die():
	is_dead = true
	# 【P3 多武器】死亡打断开镜（避免准镜残留）
	_cancel_scope()
	# 【修复】统一走 _reset_all_locks 集中复位：原先手抄子集遗漏了 _nepal_attacking/
	# _nepal_atk_arms/_ability_speed_mult 等 → 挥刀瞬间死亡后 _drive_nepal_arms 仍
	# 每帧驱动手臂骨骼、冲刺倍率残留到复活。本函数与 _resurrect/on_character_switched
	# 共用同一复位入口，杜绝"散落复制导致遗漏"。
	_reset_all_locks()
	_death_await_revive = false
	_death_revive_timer = 0.0
	_k_was_pressed = true  # 标记K键已按下，防止下一帧立即复活；松开后再按K才触发复活
	velocity = Vector3.ZERO
	_reset_fp_state()  # 死亡时清 FP 子系统（停换弹/连发/后坐、视图模型回 idle）
	# 【修复】能力收尾：死亡时若冲刺爆发激活中，强制结束并复位速度倍率
	_force_finish_ability()
	_ability_speed_mult = 1.0
	character_visual.position.y = 0.0  # 死亡时视觉模型恢复到站立位置
	camera_controller.set_crouch(false, 0.5)  # 死亡时相机恢复站立高度（0.5s快速过渡）
	camera_controller.set_rotation_locked(true)
	_change_state(AnimState.DEATH)
	_play_animation(AnimState.DEATH, false, 1.0)
	# 重新设置碰撞体为站立高度（死亡时角色站姿倒下）
	_update_collision_height(_standing_height())

func _resurrect():
	# 重置位置到出生点（_ready 记录的实际出生位置，替代原硬编码 (0,0,0)）
	global_position = _spawn_point
	# 【Q键】复活后视为"未换过枪"：Q 切到第二把武器（用户规则）
	_prev_weapon_id = ""
	# 重置所有状态变量
	is_dead = false
	_reset_all_locks()  # 与 on_character_switched 共用，避免遗漏状态锁导致卡死
	_death_await_revive = false
	_death_revive_timer = 0.0
	_k_was_pressed = false
	velocity = Vector3.ZERO
	# 【修复】复活时 FP 子系统复位（与死亡/切换共用 _reset_fp_state，清换弹/连发/后坐 + 回 idle）
	_reset_fp_state()
	_force_finish_ability()
	_ability_speed_mult = 1.0
	# 重置视觉模型位置
	_target_visual_y = 0.0
	character_visual.position.y = 0.0
	# 重置相机
	camera_controller.set_crouch(false, 0.5)
	camera_controller.set_rotation_locked(false)
	camera_controller.pitch = 0.0
	# 重置碰撞体为站立高度
	_update_collision_height(_standing_height())
	# 重置动画到待机状态
	_change_state(AnimState.IDLE_AIM)
	_play_animation(AnimState.IDLE_AIM, true, 1.0)
	debug_print("复活: 重置到出生点")

# ============================================================
# 蹲姿受击倒地逻辑
# ============================================================
func _start_crouch_hit_back():
	_is_in_crouch_hit_back = true
	camera_controller.set_rotation_locked(true)
	_change_state(AnimState.CROUCH_HIT_BACK)
	_play_animation(AnimState.CROUCH_HIT_BACK, false, 1.0)
	debug_print("蹲姿受击倒地: " + str(AnimState.CROUCH_HIT_BACK))

# ============================================================
# 带容错的地面检测
# ============================================================
func _is_on_floor() -> bool:
	return is_on_floor()

# ============================================================
# 工具方法：获取当前正在播放的动画名
# ============================================================
func get_current_animation_name() -> String:
	return anim_player.current_animation if anim_player.is_playing() else ""

# ============================================================
# 工具方法：检查是否处于可移动状态
# ============================================================
func can_move() -> bool:
	return not is_dead

# ============================================================
# 武器/FP 子系统创建与绑定（抽取自 _ready，供初始与切换复用）
# ============================================================
func _setup_weapon_and_fp() -> void:
		# 解析采样骨骼（右手优先，退化到左手），用于空间跳变检测
		_hand_bone = character_visual.find_child("RightHand", true, false)
		if _hand_bone == null:
			_hand_bone = character_visual.find_child("LeftHand", true, false)
		if _hand_bone == null:
			push_warning("丝滑度检测：未找到手部骨骼节点（RightHand/LeftHand），空间跳变检测将仅用根旋转")
	
		# 武器握持系统（P0-1）：WeaponRig 节点封装双手握持/枪身对齐/跳跃换弹分支。
		# 标定常量来自 WeaponRigConfig 资源（P0-2，见 resources/weapon_rig_config.tres）。
		_weapon_skel = character_visual.find_child("Skeleton3D", true, false) as Skeleton3D
		if _weapon_skel != null:
			_weapon_bone_idx = _weapon_skel.find_bone("mixamorig_RightHand")
			_lhand_bone_idx = _weapon_skel.find_bone("mixamorig_LeftHand")
			_torso_bone_idx = _weapon_skel.find_bone(TORSO_BONE)
			if _torso_bone_idx >= 0:
				_torso_parent_idx = _weapon_skel.get_bone_parent(_torso_bone_idx)
			if _torso_bone_idx < 0:
				push_warning("上半身俯仰：未找到腰部骨 %s，俯仰功能不生效" % TORSO_BONE)
		# 武器握持交由 WeaponRig：双手皮肤点连线定位 + 枪身轴线对齐 + 跳跃/换弹分支。
		_weapon_rig = WeaponRig.new()
		add_child(_weapon_rig)
		var _weapon_holder_node: Node3D = character_visual.find_child("Weapon_AK47", true, false) as Node3D
		_weapon_holder = _weapon_holder_node
		if _weapon_holder_node == null:
			push_warning("武器挂载：未找到 Weapon_AK47 节点（character.tscn），AK47 未挂载")
		else:
			# 【修复·多角色】初始握持必须用【当前角色】的 WeaponRigConfig（含其骨架缩放），
			# 否则复用默认配置（飞虎队 0.00026 缩放）套到 SWAT(0.0138) 等大缩角色 →
			# 握持偏移算错空间 → AK 枪漂到天上/极远坐标（部分 GPU 驱动直接崩溃）。
			# 与切枪路径(_switch_to_weapon)一致：走 prepare_rig_config 把 skeleton_space_scale
			# 覆写为当前角色缩放，保证初始与切换两端行为一致。
			var _base_cfg: WeaponRigConfig = null
			if char_manager != null and char_manager.get_active_asset() != null:
				_base_cfg = char_manager.get_active_asset().weapon_rig_config as WeaponRigConfig
			# 【修复】与下方音效调用一致的守卫：weapon_system 仅在 char_manager 存在时创建
			# （player_preview 等预览场景无 CharacterManager → _weapon_system 为 null），
			# 此处若直接调用会崩（Nil.prepare_rig_config），用默认 config 兜底。
			var _rig_cfg: WeaponRigConfig = WeaponRigConfig.new()
			if _weapon_system != null:
				_rig_cfg = _weapon_system.prepare_rig_config(_base_cfg)
			_weapon_rig.setup(_weapon_skel, _weapon_holder_node, _rig_cfg)
		# 第三人称刺刀/射击动作叠加系统：复用第一人称动作形态，驱动双臂+世界枪。
		var _muzzle_flash := character_visual.find_child("MuzzleFlash", true, false) as Node3D
		if _muzzle_flash == null and _weapon_holder_node != null:
			# 程序化创建枪口火光（避免改动 character.tscn 资源 ID）：自发光球置于枪口（作近距离亮芯）。
			_muzzle_flash = MeshInstance3D.new()
			_muzzle_flash.name = "MuzzleFlash"
			var sm := SphereMesh.new()
			sm.radius = 0.035
			sm.height = 0.07
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED  # 不受全局光照/阴影影响，纯色常亮
			mat.albedo_color = Color(1.0, 0.9, 0.5)
			sm.material = mat
			_muzzle_flash.mesh = sm
			_muzzle_flash.visible = false
			# 优先挂到场景内可编辑的 MuzzleMarker 标注球（红色球，编辑器拖动它=绑定真实枪口，
			# 火光自动跟随，无需改代码）；无标注球时回退：挂 Weapon_AK47 下、对齐 GripPoint_Muzzle 估算位。
			var marker: Node3D = _weapon_holder_node.find_child("MuzzleMarker", true, false) as Node3D
			if marker != null:
				marker.add_child(_muzzle_flash)
				# 运行时隐藏标定球（仅编辑器标定时可见），火光挂在 MuzzleMarker 挂点上不受影响
				var ball := marker.find_child("MarkerBall", true, false) as Node3D
				if ball != null:
					ball.visible = false
				# 强制 MuzzleMarker 下所有网格材质为无光照（含用户自挂的火光贴图）：
				# 保证枪口火光在任何光照/阴影下恒亮，不受全局光照影响。
				_force_unshaded_recursive(marker)
			else:
				_muzzle_flash.position = Vector3(-0.02, 0.229, -1.0)  # 对齐 GripPoint_Muzzle（枪口）
				_weapon_holder_node.add_child(_muzzle_flash)
	
		_fp_action = FPActionRetarget.new()
		add_child(_fp_action)
		# 【P3】音效从 WeaponSystem 当前武器读取（默认 AK47 路径兜底）
		var _fire_sfx: String = _weapon_system.get_fire_sfx() if _weapon_system != null else "res://audio/ak47hql_shoot2.dat"
		var _bay_sfx: String = _weapon_system.get_bayonet_sfx() if _weapon_system != null else "res://audio/AK47-HQL_KNIFE-ATTACK.dat"
		_fp_action.setup(_weapon_skel, _weapon_rig, _weapon_holder_node, _muzzle_flash,
			_fire_sfx, _bay_sfx)
		# 上半身俯仰：取相机控制器（读取 pitch）并提升 process_priority，
		# 确保本节点 _process 在 AnimationPlayer 之后执行（骨骼俯仰改写不被动画覆盖）。
		_camera_ctrl = _find_camera_controller()
		if _camera_ctrl == null:
			push_warning("上半身俯仰：未找到 CameraController，相机俯仰将无法驱动上半身")
		# 第一人称视图模型（V 键切换）：挂到主相机下，默认隐藏；初始 idle 就绪。
		# 【100%换皮】FP 手臂默认全局共享一套（两角色同 Mixamo 骨架，视觉正确）。
		# 若角色资产配置了专属 fp_viewmodel_scene（非空）→ 用专属场景构建视图模型；
		# 空 → 共享默认 ak47_viewmodel.gltf。切换角色时若新角色场景不同则重建（见切换处）。
		var _fp_scene: PackedScene = null
		if char_manager != null and char_manager.get_active_asset() != null:
			_fp_scene = char_manager.get_active_asset().fp_viewmodel_scene
		_fp_vm = FPViewmodelPlayer.new()
		add_child(_fp_vm)
		if _fp_scene != null and _fp_scene.resource_path != "":
			_fp_vm.vm_scene_path = _fp_scene.resource_path
			debug_print("角色 %s 使用专属 FP 场景 %s" % [char_manager.active_id, _fp_scene.resource_path])
		if _camera_ctrl != null:
			_fp_vm.setup(_camera_ctrl.camera)
		# 换弹时长取 FP reload 动画时长与 3P Reloading 动画时长的中间值（用户要求）：
		# 3P 动画在 _play_one_shot_override 按 _reload_duration 加速，FP 动画由
		# trigger_reload_duration 按 _reload_duration 放慢，两侧节奏一致。
		# 统一走 _recompute_reload_duration()，与角色切换路径算法完全一致。
		_recompute_reload_duration()
		# 【P3 多武器】初始即把当前武器(AK47)行为数据应用到子系统（数据驱动；
		# AK47 字段为空→走默认常量，行为与原硬编码一致）。
		_apply_weapon_to_subsystems(_weapon_system.get_current_weapon() if _weapon_system != null else null)
		# 枪身轴线提前匹配窗口：FP 实装前原始值 0.4s + 用户追加提前 0.5s + 0.1s = 1.0s
		# （换弹结束前 1.0s 转回待机方向）。绝对提前量，与换弹总时长无关。
		if _weapon_rig != null:
			_weapon_rig.one_shot_prelead = 1.0
		# 【时序硬依赖 / process_priority=10】本节点 _process 必须在 AnimationPlayer(默认 priority=0)
		# 之后执行：躯干俯仰叠加与 WeaponRig 握持都依赖「本帧已更新的动画骨骼姿态」。
		# 若该优先级被调低（或 AnimationPlayer 被调到 >10），叠加/握持会读到上一帧姿态→枪与上半身滞后/脱手。
		# 切勿在无对应调整时改动此值。
		# 【默认第一人称】进游戏直接 FP 视角：复用完整切换流程（相机/3P 显隐/FOV/viewmodel 出枪）。
		# 放在 _ready 最末尾——所有子系统（相机/FOV/viewmodel/武器）均已就绪。
		if not _fp_mode:
			_toggle_view_mode()
		debug_print("[默认视角] _fp_mode=" + str(_fp_mode))
