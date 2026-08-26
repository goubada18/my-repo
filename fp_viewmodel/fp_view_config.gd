@tool
class_name FPViewConfig
extends Resource

# 任一场景拖拽相机写回后广播，让其它已打开的场景实时同步相机。
signal camera_changed()

# 第一人称/转盘 相机共享配置。
# 7 个动作场景都引用同一个 .tres 实例 => 改这里一处，全部场景生效。
# 在编辑器里：打开任一个 fp_*.tscn，选中根节点，检视面板里找到 "Config"，
# 展开即可改 fp_gun_pos / fp_gun_rot / fp_fov（第一人称）或 tt_fov（转盘）。

@export var fp_gun_pos: Vector3 = Vector3(0.10, -0.20, -0.70)
@export var fp_gun_rot: Vector3 = Vector3(0.0, 1.5708, 0.04)
@export var fp_fov: float = 70.0

# 摆放几何中心覆盖：Vector3.ZERO=运行时自动计算（默认）；非零=强制用该值。
# 适用：bind pose 顶点分散很大的模型（如手雷：顶点散布 23m，自动算出的 center
#       会被骨架姿势污染），改用预览场景里量的静止姿势中心，保证实机=预览。
@export var fp_center_override: Vector3 = Vector3.ZERO

# 第一人称“眼睛”相机的位置/旋转（所有场景 + 运行时 FP 都从这儿读 => 改一处全生效）
@export var fp_cam_pos: Vector3 = Vector3(0, 0, 0)
@export var fp_cam_rot: Vector3 = Vector3(0, 0, 0)

@export var tt_fov: float = 50.0
@export var tt_dist: float = 2.4
@export var tt_pitch: float = 0.18
