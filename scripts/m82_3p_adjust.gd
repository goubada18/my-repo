@tool
extends Node3D
## M82 3P 枪调整工作区（真实角色 + 双手球 + 枪口/枪托球）
## 打开 scenes/m82_3p_adjust.tscn：
##   场景：真实角色(待机) + 红球(右手) + 蓝球(左手) + M82枪 + 红球(枪口) + 蓝球(枪托)
##   1) 双手球自动对齐角色骨骼（mixamorig_RightHand/LeftHand）——不用动
##   2) 把 M82MuzzleBall(红,挂枪下) 拖到枪口、M82ButtBall(蓝) 拖到枪托
##   3) 调 gun_pos_offset（枪相对右手的偏移）让枪握在手里
##   4) 点 ApplyAxis 或关场景 → 写入 weapon_rig_config_m82.tres

@export var gun_pos_offset: Vector3 = Vector3.ZERO   # 枪相对角色右手的偏移（米）
@export var apply_axis: bool = false:
	set(v):
		if v and Engine.is_editor_hint():
			_apply_axis()
		apply_axis = false

var _skel: Skeleton3D = null

func _ready() -> void:
	if Engine.is_editor_hint():
		_align_hand_balls()
		_print_axis()

func _align_hand_balls() -> void:
	_skel = find_child("Skeleton3D", true, false) as Skeleton3D
	# 隐藏角色内嵌 AK47 枪（避免干扰）
	var ak := find_child("Weapon_AK47", true, false) as Node3D
	if ak != null:
		ak.visible = false
	# 双手球对齐角色骨骼世界位置
	if _skel == null:
		return
	for bone_name in ["mixamorig_RightHand", "mixamorig_LeftHand"]:
		var bi: int = _skel.find_bone(bone_name)
		if bi < 0:
			continue
		var wp: Vector3 = _skel.global_transform * _skel.get_bone_global_pose(bi).origin
		var ball: Node3D = find_child("RightHandBall" if "Right" in bone_name else "LeftHandBall", true, false) as Node3D
		if ball != null:
			ball.global_position = wp
			print("手球对齐: ", bone_name, " -> ", wp)

func _print_axis() -> void:
	var muzzle := get_node_or_null("M82WorldGun/M82MuzzleBall") as Node3D
	var butt := get_node_or_null("M82WorldGun/M82ButtBall") as Node3D
	if muzzle == null or butt == null:
		return
	var axis: Vector3 = (muzzle.position - butt.position).normalized()
	print("=== M82 枪身轴线 ===")
	print("Muzzle:", muzzle.position, "  Butt:", butt.position)
	print("gun_axis_local =", axis)

func _process(_delta: float) -> void:
	# 不做强制定位——让用户在编辑器里自由拖动枪/球（_process 每帧覆盖会锁死拖动）
	pass

func _apply_axis() -> void:
	var muzzle := get_node_or_null("M82WorldGun/M82MuzzleBall") as Node3D
	var butt := get_node_or_null("M82WorldGun/M82ButtBall") as Node3D
	if muzzle == null or butt == null:
		push_warning("找不到标注球")
		return
	var axis: Vector3 = (muzzle.position - butt.position).normalized()
	var cfg: Resource = load("res://resources/weapons/weapon_rig_config_m82.tres")
	if cfg == null:
		push_warning("无法加载 weapon_rig_config_m82.tres")
		return
	cfg.set("gun_axis_local", axis)
	cfg.set("grip_real_local", butt.position)
	var err := ResourceSaver.save(cfg, "res://resources/weapons/weapon_rig_config_m82.tres")
	if err == OK:
		print("已写 gun_axis_local =", axis, " grip_real_local =", butt.position)
	else:
		push_warning("保存失败 err=" + str(err))
