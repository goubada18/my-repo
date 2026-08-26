extends "res://scripts/menu_base.gd"
## 主菜单：单机模式 / 联机模式（后期设计）/ 设置（选择角色）/ 退出游戏

func _build() -> void:
	var v := _make_panel("主菜单")
	_add_btn(v, "单机模式", _on_single_player)
	_add_btn(v, "联机模式（敬请期待）", _on_multiplayer)
	_add_btn(v, "设置（选择角色）", _on_settings)
	_add_btn(v, "退出游戏", _on_quit, QUIT_COLOR)

func _on_single_player() -> void:
	get_tree().change_scene_to_file("res://scenes/map_select.tscn")

func _on_multiplayer() -> void:
	# 联机模式：后期设计，暂未开放
	pass

func _on_settings() -> void:
	get_tree().change_scene_to_file("res://scenes/settings_screen.tscn")

func _on_quit() -> void:
	get_tree().quit()
