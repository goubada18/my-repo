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

## 【设置界面崩溃修复】角色注册表缓存。
## 背景：settings_screen 每次进入都 load(character_registry.tres)，而该文件级联引用
## character_preview.tscn（内嵌 SWAT 完整网格+骨架 1.08MB）等大资源。进过游戏场景后
## （SWAT 被 mount 使用过），再次 load 同一批资源会触发 Godot 4.7 资源缓存 bug →
## C++ SIGSEGV（用户实测：主菜单→设置即崩）。
## 方案：boot 首次加载 registry 后缓存到这里，settings_screen 一律读缓存，永不重复 load。
var character_registry: Resource = null

