extends "res://scripts/menu_base.gd"
## 设置界面（主菜单内）：角色选择（迁移自原游戏内 1/2 键）。
## 选中写入 GameState（Autoload 跨场景持久），进入游戏后全地图生效；游戏内不可再切换。

const REGISTRY_PATH := "res://resources/characters/character_registry.tres"

var _list: ItemList = null
var _hint: Label = null
var _ids: Array[String] = []          ## 列表行索引 → 角色 id（与 _list 行一一对应）
var _selected: int = -1

func _build() -> void:
	var v := _make_panel("设置 - 选择角色")
	_hint = _add_hint(v)
	_list = _make_list(v)
	_ids.clear()
	var reg := load(REGISTRY_PATH) as CharacterRegistry
	if reg != null:
		for asset in reg.characters:
			var ca := asset as CharacterAsset
			if ca != null and ca.id != "":
				_list.add_item(ca.display_name if ca.display_name != "" else ca.id)
				_ids.append(ca.id)
	if _list.item_count <= 0:
		_list.add_item("（未找到角色注册表）")
	_list.item_selected.connect(_on_select)
	_add_btn(v, "返回主菜单", _on_back)
	# 预选当前 GameState 已选角色（进入设置时保持上次选择）
	_selected = _ids.find(GameState.selected_character_id)
	if _selected < 0 and _ids.size() > 0:
		_selected = 0                  # 未选过 → 默认高亮首个角色，避免"看不出选了谁"
	if _selected >= 0:
		_list.select(_selected)
	_refresh_hint()

## 选中角色：立即写入 GameState 并刷新提示（无需额外确认）
func _on_select(index: int) -> void:
	_selected = index
	if index >= 0 and index < _ids.size():
		GameState.selected_character_id = _ids[index]
	_refresh_hint()

func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _refresh_hint() -> void:
	if _hint == null or _list == null:
		return
	if _selected >= 0 and _selected < _ids.size():
		_hint.text = "已选择：%s　（进入游戏即生效，全地图通用；游戏内不可再切换）" % _list.get_item_text(_selected)
	else:
		_hint.text = "未选择（将使用默认角色）"
