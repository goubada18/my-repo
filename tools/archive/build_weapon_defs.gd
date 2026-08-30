extends SceneTree
## P3 武器资产生成：生成 resources/weapons/ak47.tres（WeaponDef）
## 用法：godot --headless --path <proj> --script tools/build_weapon_defs.gd
func _initialize() -> void:
	var out_dir := "res://resources/weapons"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var def := WeaponDef.new()
	def.id = "ak47"
	def.display_name = "AK47"
	# 3P 世界枪模型（当前角色场景内嵌复用；动态实例化留 P3 二期）
	def.world_model = load("res://actor/ak47_world/ak47_beast_world.gltf") as PackedScene
	# 握持标定：飞虎队 A 空间原版（装备时 WeaponSystem 按当前角色骨架缩放换算）
	def.weapon_rig_config = load("res://resources/weapon_rig_config.tres") as WeaponRigConfig
	def.fire_sfx = "res://audio/ak47hql_shoot2.dat"
	def.bayonet_sfx = "res://audio/AK47-HQL_KNIFE-ATTACK.dat"
	def.damage = 25.0
	def.fire_rate = 0.12
	var err: int = ResourceSaver.save(def, out_dir + "/ak47.tres")
	print("ak47 WeaponDef 保存 err=%d" % err)
	# 回读验证
	var back: WeaponDef = load(out_dir + "/ak47.tres")
	print("回读: id=%s cfg=%s sfx=%s" % [
		back.id, str(back.weapon_rig_config != null), back.fire_sfx])
	print("DONE")
	quit(0)
