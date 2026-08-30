class_name NepalKnifeCalib
extends Resource
## 尼泊尔刀 3P 挂点标定资源（每角色一份）。
##
## 内容 = 刀模型相对【右手骨骼(mixamorig_RightHand)局部系】的 transform，
## 在标定场景 scenes/nepal_knife_calib.tscn 中拖拽刀模型后一键保存。
##
## 【为什么每角色一份】旧方案是"飞虎队标定一份全局常量 + 运行时 k=0.00026/角色
## 骨架缩放 换算"，但 k 假设两骨架"纯缩放"——实测 SWAT/飞虎骨骼姿态有旋转差
## （Hips 差 ~86°），纯 k 换算导致 SWAT 刀位偏移（用户实测，见 player.gd 尼泊尔注释）。
## 每角色直接标定自己的骨骼局部系 → 无换算、无跨角色耦合。
##
## 【BoneAttachment3D 铁律】挂点(BA)每帧被引擎覆盖为骨骼姿态，偏移/旋转必须
## 存在【刀节点本身】的 transform 上——本资源存的就是刀节点的局部 transform。

@export var local_pos: Vector3 = Vector3.ZERO
@export var local_rot: Quaternion = Quaternion.IDENTITY
@export var local_scale: Vector3 = Vector3.ONE
@export var bone_name: String = "mixamorig_RightHand"
@export_multiline var note: String = ""

func make_transform() -> Transform3D:
	return Transform3D(Basis(local_rot).scaled(local_scale), local_pos)
