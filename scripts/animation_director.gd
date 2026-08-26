class_name AnimationDirector
extends RefCounted
## 动画导演（P2）：把"逻辑状态 → 动画名"的查询从 player.gd 的 ANIM_NAMES
## 全局表，改为"按当前角色资产查询"。
##
## 设计：
## - player.gd 状态机逻辑不动，只把 `ANIM_NAMES.get(state)` 换成 `director.anim_name(state)`
## - 查询顺序：当前角色资产.anim_map → 缺失返回 ""（调用方降级：跳过该动画/动作）
## - 与 CharacterManager 联动：角色切换后自动查新角色的动画库
##
## 用法：
##   director = AnimationDirector.new()
##   director.bind(character_manager)
##   var name: String = director.anim_name("IDLE_AIM")

## 角色管理器引用（切换后自动读新角色资产）
var char_manager: CharacterManager = null

func bind(cm: CharacterManager) -> void:
	char_manager = cm

## 逻辑状态 → 动画名（缺失返回空字符串）
func anim_name(logical_state: String) -> String:
	if char_manager == null:
		return ""
	var asset: CharacterAsset = char_manager.get_active_asset()
	if asset == null:
		return ""
	return asset.anim_name(logical_state)
