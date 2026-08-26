class_name WeaponRigConfig
extends Resource

# ============================================================================
# WeaponRigConfig — 第三人称武器握持标定资源（P0-2）
# 把原写在 player.gd 里的「经验标定常量」抽到资源，使其与 AK47 模型 / Mixamo 骨骼
# 解耦：换枪或换骨骼时，美术/策划只改这份 .tres，无需触碰代码。
# 生成方式：tools/make_weapon_rig_config.gd 依据本脚本的默认值写出
#          res://resources/weapon_rig_config.tres。
# ============================================================================

# GLB 原始单位→米（已含在 AK47Adjust 缩放）
@export var ak47_scale: float = 0.0706

# 枪身轴线（模型局部系，枪口方向）。AK47 = (0,0,-1)（模型 -Z = 枪口）；
# M82 等其它武器枪身轴线不同（M82 flash 骨骼实测 = (0.154, 0.480, -0.864)）。
# WeaponRig 每帧把此方向对齐到目标枪口方向（双手连线/跳跃方向）→ 轴线匹配跟手。
@export var gun_axis_local: Vector3 = Vector3(0, 0, -1)

# 握把点（Weapon_AK47 局部系，重标定值）：从"游戏完美握持位"反算的真实握把局部坐标。
# 任何 basis 下 basis×该点+anchor 恒=右手球，GunGrip 归零时枪位仍=完美位。
@export var grip_real_local: Vector3 = Vector3(-0.134841, 0.022478, -0.115572)

# 手点 = 骨骼 × 固化 offset（由原 GripPoint 球标注反算，拖球不再影响枪）
@export var grip_rh_offset: Vector3 = Vector3(-89.13281, 451.4172, 71.25647)     # 右手球相对 RightHand 骨骼
@export var grip_lh_offset: Vector3 = Vector3(104.7581, 585.998, 63.58203)       # 左手球相对 LeftHand 骨骼
@export var grip_elbow_offset: Vector3 = Vector3(103.0625, -531.6064, 258.6724)  # 肘球相对 RightForeArm 骨骼

# 斜率差：待机完美状态下 骨骼双手直线 → 枪口方向 的最短旋转，固化。
# 运行时 枪口方向 = SLOPE_R × 双手直线（球/骨骼均被 offset 吸收，只随动画相对变化）。
@export var slope_r: Basis = Basis(
	Vector3(0.998614, 0.001285, 0.052608),
	Vector3(-0.009733, 0.986962, 0.160659),
	Vector3(-0.051716, -0.160949, 0.985607))

# 【100%换皮】骨架空间缩放标定：grip_*_offset 是【飞虎队 A 空间】标定的
# （Armature scale=0.00026，骨骼坐标千位级）。此字段记录本角色骨架的 Armature scale
# （SWAT=0.013795 等），weapon_rig 用 k=0.00026/此值 换算 offset 到本角色空间。
# 飞虎队原值 0.00026 → k=1 不换算；新角色在资产生成时写入各自 scale，运行时不再
# 用骨架测量推断（测量依赖骨架结构，换特殊骨架会误判）。
@export var skeleton_space_scale: float = 0.00026

# 【P3 用户微调】在 WeaponRig 跟手摆位【之后】叠加的相对偏移（米/欧拉角弧度）。
# 用途：跟手（轴线匹配）保证枪随角色动；此偏移让用户微调枪相对手的位置/朝向
# （如 M82 想高一点/偏右/旋转）。编辑器在 scenes/m82_3p_adjust.tscn 里调好后抄回。
@export var user_offset_pos: Vector3 = Vector3.ZERO
@export var user_offset_rot: Vector3 = Vector3.ZERO

# 【手枪等横握武器】正常持枪时 WeaponRig 用「双手连线(左手-右手)」做枪口方向——
# 步枪双手连线≈前向所以正常；但手枪横握双手连线≈横向（实测相对前向 -81°），
# 枪会被转横（枪口歪向侧方）。true = 枪口方向改用角色前向 char_basis.z。
# 步枪等默认 false，行为零变化。
@export var dir_use_forward: bool = false

# 【手枪枪口水平修正】dir_use_forward 时，枪口方向在角色前向上再绕世界 UP 旋转
# 该弧度（正=右转，负=左转）。手枪待机前臂方向实测偏左 ~10°，用户可在编辑器
# 改此值（0.175≈10°）让枪口正对前方，F6 实机直接生效。
@export var dir_yaw_offset: float = 0.0

# 【手枪枪口俯仰修正】绕右轴附加俯仰（弧度，正=枪口上抬）。与 dir_yaw_offset 一起
# 描述「枪轴(枪托→枪口) 相对 手腕→手连线」的偏转（编辑器 Muzzle2-Butt vs Hand-Elbow）。
@export var dir_pitch_offset: float = 0.0

# 【手枪与步枪同高度】手臂抬升角（度）：手枪待机右手比步枪低 ~0.14m，
# 合成时给 Shoulder rotation 左乘绕 rest x 轴的抬臂旋转（肩骨位置不动=不耸肩）。
# 编辑器改此值可调抬升量，F6 生效。步枪等默认 0（不抬）。
@export var arm_lift_deg: float = 0.0
