class_name WeaponDef
extends Resource
## 武器资产（P3）：一个 .tres = 一把武器。
## 角色资产 CharacterAsset.weapons 列出可装备武器清单 → WeaponSystem 装备当前武器。
## 目标：加新武器 = 放一个 WeaponDef 资产 + 角色 weapons 列表加一项，所有角色自动可装备
## （握持配置按角色骨架换算由 weapon_rig 的 skeleton_space_scale 机制保证）。

## 武器唯一标识（如 "ak47"）
@export var id: String = ""
## 显示名（UI 用）
@export var display_name: String = ""

## 【数据驱动】武器类型：决定 3P 摆位/挂载方式与输入分支，
## 替代 player.gd 中散落的 id 字符串硬编码（加新连发枪/新狙击枪不再被 id 判错）。
## "rifle"=使用角色内嵌枪模型的步枪 "pistol"=手枪 "sniper"=狙击
## "knife"=近战(骨骼挂载) "grenade"=投掷(持雷手势)
@export_enum("rifle", "pistol", "sniper", "knife", "grenade") var weapon_type: String = "rifle"
## 【数据驱动】射击模式："auto"=按住连发（射击动画不打断连发）"single"=单发锁。
## 原逻辑硬编码 id=="ak47" 判定连发；新默认 single，ak47.tres 显式配 auto。
@export_enum("auto", "single") var fire_mode: String = "single"
## 【数据驱动】是否可开镜（右键 toggle 瞄准镜）。替代 player.gd 的 SCOPE_WEAPON_ID 常量。
@export var scopable: bool = false

## 3P 世界枪模型场景（含 Weapon_AK47 完整子树：Adjust 缩放 + Model + GripPoint + MuzzleMarker）。
## 预留：当前角色场景内嵌武器（character.tscn 的 Weapon_AK47），WeaponSystem 优先复用内嵌节点；
## 后续支持角色不内嵌、由 WeaponSystem 动态实例化此模型（P3 二期）。
@export var world_model: PackedScene = null

## 【P3 手动标定】3P 动态世界枪摆位（位置/旋转/缩放）。
## 当 world_model 非空且本武器为【动态实例化】（非内嵌 AK47）时使用——
## 直接设置 inst.transform = T(pos) * R(rot) * S(scale)，不再做任何自动对齐。
## 用编辑器调整场景（scenes/m82_3p_adjust.tscn）拖好数值后抄到这里即可。
@export var world_3p_pos: Vector3 = Vector3.ZERO
@export var world_3p_rot: Vector3 = Vector3.ZERO   # 欧拉角（弧度）
@export var world_3p_scale: float = 1.0
## 是否启用手动标定（true = 用 world_3p_* 摆位；false = 走旧自动逻辑）
@export var use_world_3p_pose: bool = false

## 本武器握持标定（飞虎队 A 空间；weapon_rig 按当前角色骨架缩放换算，
## 由 WeaponSystem 装备时把角色缩放写入副本的 skeleton_space_scale）
@export var weapon_rig_config: WeaponRigConfig = null

## 音效路径（复用 fp_action_retarget / fp_viewmodel 的 .dat WAV 解析）。
## 【修复】默认改为空 = 不发声：原先默认借用 AK47 音效，新武器忘设 silent
## 会莫名响起 AK47 枪声。设计原则"宁可无声也不借用"现在由默认值兜底；
## AK47 自身音效已在 ak47.tres 中显式声明。
@export var fire_sfx: String = ""
@export var bayonet_sfx: String = ""

## 数值（Demo 无敌人，预留供将来伤害系统使用）
@export var damage: float = 25.0
## 连发间隔（秒/发）。>0 时覆盖各子系统硬编码的 AUTO_FIRE_INTERVAL；0 或留空 → 回退默认 0.15。
## 加新武器设此即改射速，无需动代码（get_fire_interval 在 WeaponSystem 取用）。
@export var fire_rate: float = 0.15
@export var muzzle_flash_scale: float = 1.0

## 换弹音效（与 FP 共用同一份 .dat）。空 → 不发声（不借用其它武器音效）。
@export var reload_sfx: String = ""

## 本武器换弹总时长（秒）；<=0 → 自动算法（FP reload 动画时长 与 3P Reloading 动画
## 时长取均值）。狙击枪等换弹节奏特殊的武器可显式覆盖：如 M82 设为自身 reload
## 动画时长（2.305s），避免被 3P Mixamo Reloading(3.85s) 均值拖长 → 换弹声 pitch
## 过度拉伸变调（M82 reload.wav 仅 0.67s，拉到 3.1s 会低沉怪异）。
@export var reload_duration: float = 0.0

## 第一人称视图模型场景（res 路径）；空 → 走角色资产 fp_viewmodel_scene / 默认 ak47_viewmodel。
## 多武器时不同枪可带不同 FP 手臂模型，切换武器即换 FP 视图模型。
@export var fp_viewmodel_scene: String = ""
## 第一人称视图模型摆放配置（fp_view_config.tres 风格）；空 → 默认 CFG_PATH。
@export var fp_viewmodel_cfg: String = ""
## 第一人称换弹动画（烘焙回位版）；空 → 默认 reload_fixed.tres。
@export var fp_reload_anim: String = ""

## 【P3 多武器动画名映射】系统期望动作名 → 本武器实际动画名。
## 例：v_deagle 动画叫 idle1（非 idle）→ {"idle": "idle1"}；
##     尼泊尔无 shoot2/reload/cidao1 → {"shoot2": "midslash1", "reload": "draw", "cidao1": "stab"}。
## 空字典 = 全部用系统默认名（AK47 零变化）。
@export var fp_anim_map: Dictionary = {}

## 【P3 近战交替】射击动作的交替动画名（与 fp_anim_map 的 shoot2 映射成对）：
## 尼泊尔左键挥砍 = midslash1/midslash2 交替。触发射击时自动在"shoot2 映射动画"与
## 本动画间来回切换（单击=第1个，连点/长按=交替），实现连击不重复。
## 空 = 不交替（AK47/M82 零变化）。
@export var fp_alt_shoot_anim: String = ""

## 【P3 静音开关】本武器无专属音效时置 true：FP/3P 射击/换弹/刺刀全部不发声。
## 不套用其它武器音效（宁可无声也不借用 AK47）。默认 false（AK47 用自带音效，零变化）。
@export var silent: bool = false

## 【P3 镜像开关】FP 视图模型是否左右镜像（左手动画→右手持枪）。
## 默认 true（v_* 源动画是左手持枪，AK47/M82 都镜像）；个别武器源就是右手（如尼泊尔
## 持刀）置 false 保持原样。仅影响 FP 视图模型 scale.z，3P 不受影响。
@export var fp_mirror: bool = true
