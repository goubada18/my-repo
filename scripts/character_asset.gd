class_name CharacterAsset
extends Resource
## 角色资产包：一个角色自包含的全部数据（P1 数据化核心）。
## 目的：把角色差异（坐标系/动画/握持/骨骼/FP 模型/物理参数）收进 .tres 资产，
## 代码只剩一份，加新角色 = 加一个资产条目。
##
## 设计要点：
## - 角色【引用】共享能力资产（动画库/武器），而非复制 → 加新能力自动全角色生效
## - 动画映射 anim_map：逻辑状态 → 动画名（替代 player.gd 里硬编码的 ANIM_NAMES）
## - 运行时零换算：坐标系/握持偏移在资产生成时已换算好（build_character_asset.gd）

## 角色唯一标识（如 "feihu" / "swat"）
@export var id: String = ""
## 显示名（UI 用）
@export var display_name: String = ""

## 角色视觉场景：Armature → Skeleton3D → MeshInstance3D + 武器挂点
@export var character_scene: PackedScene = null

## 换算到本角色空间的动画库（运行时直接 load，零换算）
@export var anim_lib: AnimationLibrary = null

## 【P4】额外动画库（AnimClip 管线产物）：只含 build 时换算好的新动作动画。
## 运行时 AnimationPlayer 挂主库 + 本扩展库（存在时），新动画名可直接播。
@export var extra_anim_lib: AnimationLibrary = null

## 逻辑状态 → 动画名 映射（状态名同 player.gd 的 AnimState 语义，
## 用字符串键如 "IDLE_AIM" 便于 .tres 序列化）
@export var anim_map: Dictionary = {}

## 本角色标定的握持配置（weapon_rig 用；已在生成时按骨架换算）
@export var weapon_rig_config: Resource = null

## 第一人称视图模型场景（枪+手臂；可为空=用全局共享 FP）
@export var fp_viewmodel_scene: PackedScene = null

## 骨骼映射（默认 Mixamo 恒等；非 Mixamo 骨架时配置）
@export var skeleton_profile: BoneProfile = null

## 可装备武器清单（WeaponDef 资源数组；P3 启用）
@export var weapons: Array[Resource] = []

## 物理参数（切换角色时适配碰撞体/相机高度）
@export var eye_height: float = 1.7
@export var standing_height: float = 1.8
@export var crouching_height: float = 1.1
@export var capsule_radius: float = 0.45

## 蹲伏视觉偏移（player.gd 蹲下时视觉模型下压量）：
## 蹲姿高度 = 视觉模型整体下移 offset，配合蹲姿动画的腿弯曲使脚贴地。
## 是【角色特有标定】（取决于 rest 骨架身高与腿长比例），必须按角色配。
@export var crouch_visual_offset: float = -1.0    # 蹲下待机
@export var crouch_walk_visual_offset: float = -0.45  # 蹲下移动

## 骨架空间缩放标定（weapon_rig 握持偏移换算用）：
## 飞虎队 A 空间 Armature scale≈0.00026（骨骼千位级）；SWAT N 空间≈0.013795。
## weapon_rig 读此值换算握持偏移，不再运行时用骨架测量推断。
@export var skeleton_space_scale: float = 0.00026

## 便捷：取逻辑状态对应的动画名（缺失返回空 = 调用方降级）
func anim_name(logical_state: String) -> String:
	var n = anim_map.get(logical_state, "")
	return n if n is String else ""
