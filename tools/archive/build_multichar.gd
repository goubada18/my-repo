extends SceneTree
## P2 融合场景生成器 v2：文本拼接法（避免 pack owner 坑）
## = main.tscn（完整复制） + CharacterManager + CharacterSwitchController
## 切换键：1=飞虎队 2=SWAT
func _log(s: String) -> void:
	print(s)

func _initialize() -> void:
	var src := FileAccess.open("res://scenes/main.tscn", FileAccess.READ)
	if src == null:
		_log("!! 无法读取 main.tscn")
		quit(1)
	var text: String = src.get_as_text()
	src.close()
	# 更换 UID 避免与 main.tscn 冲突（uid 唯一性由引擎强制）
	var ts: String = str(Time.get_unix_time_from_system())
	ts = ts.replace(".", "")
	var new_uid: String = "uid://mch" + ts
	text = text.replace("uid=\"uid://bv248ppau0rw7\"", "uid=\"%s\"" % new_uid)

	# 追加 ext_resource（CharacterManager 脚本、注册表、HUD）
	# 必须插到第一个 [sub_resource 之前（Godot 要求 ext_resource 全部在前）
	# 注：character_switch_controller.gd 已删除（数字键切角色由 player.gd 接管）
	var add_ext := """
[ext_resource type="Script" path="res://scripts/character_manager.gd" id="cm_script"]
[ext_resource type="Script" path="res://scripts/character_hud.gd" id="hud_script"]
"""
	var first_sub := text.find("\n[sub_resource ")
	if first_sub < 0:
		_log("!! main.tscn 无 sub_resource 块")
		quit(1)
	text = text.substr(0, first_sub) + add_ext + text.substr(first_sub)

	# 追加节点定义（Main 根下）
	var add_nodes := """
[node name="CharacterManager" type="Node" parent="."]
script = ExtResource("cm_script")
process_mode = 3

[node name="CharacterHUD" type="CanvasLayer" parent="."]
script = ExtResource("hud_script")
"""
	# 替换 Player 场景引用为 player_multichar.tscn（空挂载点，角色由 CharacterManager 提供）
	text = text.replace('"res://scenes/player.tscn"', '"res://scenes/player_multichar.tscn"')
	text += add_nodes

	var out := FileAccess.open("res://scenes/main_multichar.tscn", FileAccess.WRITE)
	if out == null:
		_log("!! 无法写入 main_multichar.tscn")
		quit(1)
	out.store_string(text)
	out.close()
	_log("已生成 main_multichar.tscn（文本拼接法）")
	_log("DONE")
	quit(0)
