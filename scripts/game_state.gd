extends Node
## 全局游戏状态（Autoload）：跨场景持久化"菜单里选择的内容"。
##
## - selected_character_id：主菜单「设置」里选中的角色，进入游戏（默认地图）时全地图生效；
##   游戏内不可再切换（CharacterSwitchController 已移除），只能回到菜单改。
## - selected_map_path：地图选择界面选中的地图场景路径。
##
## 通过 /root/GameState 访问，autoload 在任意场景之前加载，standalone(F6) 运行时也为默认值。

var selected_character_id: String = ""
var selected_map_path: String = ""
