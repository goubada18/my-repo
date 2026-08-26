extends "res://scripts/menu_base.gd"
## 地图选择界面：列表展示地图，双击或选中后点「进入游戏」进入（默认地图即 main_multichar）。

const DEFAULT_MAP_NAME := "默认地图"
const DEFAULT_MAP_PATH := "res://scenes/main_multichar.tscn"

var _list: ItemList = null
var _hint: Label = null
var _selected: int = 0

func _build() -> void:
	var v := _make_panel("选择地图")
	_hint = _add_hint(v)
	_list = _make_list(v)
	_list.add_item(DEFAULT_MAP_NAME)
	# 双击 = item_activated；单击 = item_selected（高亮 + 更新提示）
	_list.item_selected.connect(_on_select)
	_list.item_activated.connect(_on_activate)
	_add_btn(v, "进入游戏", _on_enter)
	_add_btn(v, "返回主菜单", _on_back)
	# 默认预选第一项，保证一进来就有明确选中态
	_selected = clampi(_selected, 0, maxi(_list.item_count - 1, 0))
	if _list.item_count > 0:
		_list.select(_selected)
	_refresh_hint()

func _on_select(index: int) -> void:
	_selected = index
	_refresh_hint()

func _on_activate(index: int) -> void:
	_selected = index
	_enter()

func _on_enter() -> void:
	_enter()

func _enter() -> void:
	if _list == null or _list.item_count <= 0:
		return
	var map_name: String = _list.get_item_text(_selected)
	if map_name == DEFAULT_MAP_NAME:
		GameState.selected_map_path = DEFAULT_MAP_PATH
		get_tree().change_scene_to_file(DEFAULT_MAP_PATH)

func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _refresh_hint() -> void:
	if _hint == null or _list == null or _list.item_count <= 0:
		return
	_hint.text = "当前选择：%s　（双击列表项或点「进入游戏」）" % _list.get_item_text(_selected)
