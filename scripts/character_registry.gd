class_name CharacterRegistry
extends Resource
## 角色注册表：所有角色的资产清单（P1 数据化）。
## 运行时由 CharacterManager 读取：加载每个角色资产 → 实例化槽位。
## 加新角色 = build 工具把资产 .tres 加进这里（或自动扫描 characters/ 目录）。

## 已注册角色资产（顺序 = 默认切换键顺序：1,2,3...）
@export var characters: Array[CharacterAsset] = []

## 按 id 查角色资产；找不到返回 null
func get_asset(char_id: String) -> CharacterAsset:
	for c in characters:
		if c != null and c.id == char_id:
			return c
	return null

## 当前注册角色数
func count() -> int:
	return characters.size()
