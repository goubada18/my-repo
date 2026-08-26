class_name CharacterHUD
extends CanvasLayer
## 角色切换 HUD（P3）：屏幕左上角显示当前角色名。
##
## 挂在 Main 下（与 CharacterManager 同级），订阅 character_switched 信号更新文本。
## UI 用代码构建（避免 tscn 嵌套父路径坑：Control 直接当 CanvasLayer 子节点）。

var _label: Label = null
var _manager: CharacterManager = null
var _crosshair: ColorRect = null   # 屏幕中心红点（准星；开镜时隐藏）
## 临时提示 Label（能力激活/事件反馈用，显示一段时间后自动隐藏）
var _msg: Label = null
var _msg_timer: float = 0.0
var _msg_dur: float = 0.0

func _process(delta: float) -> void:
	if _msg != null and _msg.visible and _msg_timer > 0.0:
		_msg_timer -= delta
		if _msg_timer <= 0.0:
			_msg.visible = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 代码构建 UI（Label 直接挂 CanvasLayer 下，无 parent 嵌套）
	_label = Label.new()
	_label.name = "RoleLabel"
	_label.position = Vector2(20, 16)
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("shadow_offset_x", 2)
	_label.add_theme_constant_override("shadow_offset_y", 2)
	_label.text = ""
	add_child(_label)
	# 临时提示 Label（居中偏下，能力激活等事件反馈）
	_msg = Label.new()
	_msg.name = "MsgLabel"
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# 临时提示 Label：预设"底部居中"，再整体上移 140px（【修复】之前 position=(0,-80)
	# 从左上角往上偏移 = 屏幕外，headless 只看 visible=true 验不出 → 用户看不到提示）
	_msg.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_msg.offset_left = -400
	_msg.offset_right = 400
	_msg.offset_top = -140
	_msg.offset_bottom = -80
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg.add_theme_font_size_override("font_size", 30)
	_msg.add_theme_color_override("font_color", Color(1, 0.9, 0.3, 1))
	_msg.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	_msg.add_theme_constant_override("shadow_offset_x", 3)
	_msg.add_theme_constant_override("shadow_offset_y", 3)
	_msg.visible = false
	add_child(_msg)
	# 屏幕正中心红点（准星）：除开镜外始终显示。
	# 开镜时 player.gd 调 set_crosshair_visible(false)，准镜 PNG 自带十字线。
	_crosshair = ColorRect.new()
	_crosshair.name = "CrosshairDot"
	_crosshair.color = Color(1, 0, 0, 0.95)   # 红色圆点
	_crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_crosshair.offset_left = -4
	_crosshair.offset_right = 4
	_crosshair.offset_top = -4
	_crosshair.offset_bottom = 4
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_crosshair)
	# 订阅角色切换信号（HUD 与 CharacterManager 同级，都是 Main 的子节点）
	var cm := get_parent().get_node_or_null("CharacterManager") as CharacterManager
	if cm != null:
		_manager = cm
		if not cm.character_switched.is_connected(_on_character_switched):
			cm.character_switched.connect(_on_character_switched)
		_refresh()

## 屏幕中心红点显隐（开镜时隐藏，由 player.gd 调用）
func set_crosshair_visible(v: bool) -> void:
	if _crosshair != null:
		_crosshair.visible = v

## 显示临时提示（能力激活/事件反馈；如 "冲刺爆发！"）
func show_message(text: String, dur: float = 1.2) -> void:
	if _msg == null:
		return
	_msg.text = text
	_msg.visible = true
	_msg_timer = dur
	_msg_dur = dur

## 角色切换回调：更新显示名
func _on_character_switched(_char_id: String) -> void:
	_refresh()

## 从当前激活角色资产读取显示名并刷新文本
func _refresh() -> void:
	if _label == null:
		return
	if _manager == null:
		_label.text = ""
		return
	var asset: CharacterAsset = _manager.get_active_asset()
	if asset == null or asset.id.is_empty():
		_label.text = ""
		return
	_label.text = "当前角色：%s" % asset.display_name
