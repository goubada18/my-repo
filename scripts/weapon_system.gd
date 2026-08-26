class_name WeaponSystem
extends Node
## 武器系统（P3 v1）：管理"当前武器数据"，让武器差异进入 WeaponDef 资产。
##
## v1 职责（先复制后删原则下的最小闭环）：
## - 从当前角色资产 .weapons 取武器清单，默认装备第一个
## - 装备时把武器握持配置的 skeleton_space_scale 覆盖为【当前角色骨架缩放】
##   （多武器 × 多角色：同一把武器在不同角色手上按各自骨架换算握持偏移）
## - 音效/数值：player.gd 开火/换弹/刺刀从 get_current_weapon() 读取
## - 3P 模型：当前复用角色场景内嵌的 Weapon_AK47 节点；WeaponDef.world_model
##   动态实例化（角色不内嵌武器）留 P3 二期
##
## 用法：player 创建 WeaponSystem 并 bind(char_manager)，_rebind_weapon_for_visual
## 里用 prepare_rig_config() 拿握持配置、get_fire_sfx() 拿音效。

var char_manager: CharacterManager = null
## 当前装备的武器定义
var current_def: WeaponDef = null

func bind(cm: CharacterManager) -> void:
	char_manager = cm
	_refresh_current()

## 重新拉取当前武器（角色切换/初始化时序后调用，确保 current_def 跟随激活角色）
func refresh() -> void:
	_refresh_current()

## 当前角色可装备武器清单（资产未配 → 空）
func get_weapons() -> Array:
	if char_manager == null or char_manager.get_active_asset() == null:
		return []
	return char_manager.get_active_asset().weapons

## 当前武器定义（无清单/无资产 → null，调用方降级用默认 AK47 参数）
func get_current_weapon() -> WeaponDef:
	return current_def

## 装备指定武器（按 id；找不到则保持当前）
func equip(weapon_id: String) -> bool:
	for w in get_weapons():
		var def: WeaponDef = w as WeaponDef
		if def != null and def.id == weapon_id:
			current_def = def
			return true
	return false

## 切换到清单中的下一把武器（循环；供 X 键切换）
func switch_next() -> WeaponDef:
	var list := get_weapons()
	if list.is_empty():
		return null
	var idx := 0
	if current_def != null:
		for i in range(list.size()):
			var d: WeaponDef = list[i] as WeaponDef
			if d != null and d.id == current_def.id:
				idx = (i + 1) % list.size()
				break
	current_def = list[idx] as WeaponDef
	return current_def

## 角色骨架缩放（从角色专属握持配置读 skeleton_space_scale；无则默认飞虎队 A 空间）
func get_role_skeleton_scale() -> float:
	if char_manager != null and char_manager.get_active_asset() != null:
		var cfg: Resource = char_manager.get_active_asset().weapon_rig_config
		if cfg is WeaponRigConfig:
			return (cfg as WeaponRigConfig).skeleton_space_scale
	return 0.00026

## 生成传给 weapon_rig 的握持配置副本：武器握持标定(A空间) + 当前角色骨架缩放
## → weapon_rig 用 k=0.00026/scale 换算到本角色空间（多武器×多角色正确）。
## base 参数：可传角色现有 config（无武器 config 时用）
func prepare_rig_config(base: WeaponRigConfig = null) -> WeaponRigConfig:
	var src: WeaponRigConfig = null
	if current_def != null and current_def.weapon_rig_config != null:
		src = current_def.weapon_rig_config
	elif base != null:
		src = base
	else:
		src = WeaponRigConfig.new()
	var out: WeaponRigConfig = src.duplicate(true) as WeaponRigConfig
	out.skeleton_space_scale = get_role_skeleton_scale()
	return out

func get_fire_sfx() -> String:
	return current_def.fire_sfx if current_def != null else "res://audio/ak47hql_shoot2.dat"

func get_bayonet_sfx() -> String:
	return current_def.bayonet_sfx if current_def != null else "res://audio/AK47-HQL_KNIFE-ATTACK.dat"

func get_damage() -> float:
	return current_def.damage if current_def != null else 25.0

func get_fire_rate() -> float:
	return current_def.fire_rate if current_def != null else 0.12

## 连发间隔（秒/发）：武器 fire_rate>0 即用武器值，否则回退默认 0.15（与原硬编码一致）。
func get_fire_interval() -> float:
	return current_def.fire_rate if (current_def != null and current_def.fire_rate > 0.0) else 0.15

## 换弹音效路径：武器有配则用，否则回退 AK47 默认。
func get_reload_sfx() -> String:
	return current_def.reload_sfx if (current_def != null and current_def.reload_sfx != "") else "res://audio/AK47-HQL_RELOAD.dat"

## 第一人称视图模型场景路径（空=不覆盖，走角色/默认）。
func get_fp_viewmodel_scene() -> String:
	return current_def.fp_viewmodel_scene if (current_def != null and current_def.fp_viewmodel_scene != "") else ""

## 第一人称视图模型摆放配置路径（空=默认 CFG_PATH）。
func get_fp_viewmodel_cfg() -> String:
	return current_def.fp_viewmodel_cfg if (current_def != null and current_def.fp_viewmodel_cfg != "") else ""

## 第一人称换弹动画路径（空=默认 reload_fixed.tres）。
func get_fp_reload_anim() -> String:
	return current_def.fp_reload_anim if (current_def != null and current_def.fp_reload_anim != "") else ""

func _refresh_current() -> void:
	var list := get_weapons()
	if list.is_empty():
		current_def = null
		return
	# 保持当前武器（若还在清单里）
	if current_def != null:
		for w in list:
			var d: WeaponDef = w as WeaponDef
			if d != null and d.id == current_def.id:
				return
	current_def = list[0] as WeaponDef
