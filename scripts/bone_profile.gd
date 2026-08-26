class_name BoneProfile
extends Resource
## 骨骼映射配置：把代码里的"逻辑骨骼名"映射到角色的实际骨骼名。
## 现状：飞虎队/SWAT 都是 Mixamo 骨架（mixamorig_*），映射为恒等；
## 未来接非 Mixamo 骨架时，只需改这个表的映射，代码零改动。
## 注意：命名避开引擎内置 SkeletonProfile* 系列类（SkeletonProfileHumanoid 等）。

## 逻辑骨骼名 → 实际骨骼名（空字符串 = 用逻辑名本身）
@export var bone_map: Dictionary = {}

## 逻辑名称解析：传入逻辑名（如 "RightHand"），返回角色实际骨骼名
func resolve(logical: String) -> String:
	var v = bone_map.get(logical, "")
	if v is String and not (v as String).is_empty():
		return v
	return logical
