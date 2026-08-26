class_name CharacterSwitchController
extends Node
## P2 角色切换控制：监听数字键 1/2/3... 切换角色。
## 依赖 Main 下的 CharacterManager；切换时通知 player 重绑定。
## 设计：_ready 自动发现 manager/player，无需场景预配置。

var char_manager: CharacterManager = null
var _player: Node = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 自动发现 CharacterManager（挂在 Main 下）
	var main_node: Node = get_tree().current_scene
	if main_node != null:
		char_manager = main_node.get_node_or_null("CharacterManager") as CharacterManager
	if char_manager == null:
		char_manager = get_tree().root.find_child("CharacterManager", true, false) as CharacterManager
	# 自动发现 Player
	_player = get_tree().root.find_child("Player", true, false)

func _unhandled_input(event: InputEvent) -> void:
	if char_manager == null or char_manager.registry == null:
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed or k.echo:
			return
		# 数字键 1-9 → 切换到对应角色（按注册表顺序）
		for i in range(1, 10):
			if k.keycode == KEY_1 + (i - 1):
				if i <= char_manager.count():
					var target_id: String = char_manager.registry.characters[i - 1].id
					if target_id != char_manager.active_id:
						char_manager.switch_to(target_id)
						_notify_player(target_id)
				break

func _notify_player(target_id: String) -> void:
	if _player == null:
		_player = get_tree().root.find_child("Player", true, false)
	if _player != null and _player.has_method("on_character_switched"):
		_player.call("on_character_switched", target_id)
