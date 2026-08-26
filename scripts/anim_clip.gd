class_name AnimClip
extends Resource
## 动作片段资产（P3/P4）：声明"逻辑状态 → 源动画"，构建时自动换算进每角色库。
##
## 运行时时 AnimationDirector 已通过 anim_map 按角色查询动画名；本资产是"声明层"，
## 供 build_character_asset.gd 读取后把新动画（source_fbx）换算进每个角色的动画库
## （P4 流水线：放一个 AnimClip → 跑工具 → 所有角色自动获得该动作）。
## 空 source_fbx 表示动画已存在于各角色库（只需声明映射，供文档/自检）。

## 唯一标识（如 "dodge_roll"）
@export var id: String = ""
## 逻辑状态键（同 player.gd AnimState 键名，如 "IDLE_AIM" / "WALK_FORWARD"）
@export var logical_state: String = ""
## 库内动画名（换算后各角色库中使用的名字，通常与源动画同名）
@export var anim_name: String = ""
## 源动画 FBX 路径（P4 build 工具换算用；空 = 动画已在库内）
@export var source_fbx: String = ""
## 循环播放（默认）
@export var loop: bool = true
