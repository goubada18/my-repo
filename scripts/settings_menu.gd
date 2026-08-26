class_name SettingsMenu
extends Control

## 游戏内暂停菜单（ESC 开关）
## - ESC 打开：暂停游戏（get_tree().paused）、唤出鼠标、显示半透明遮罩 + 面板
## - ESC 再次按下：关闭界面、恢复鼠标捕获、继续游戏
## - 提供「继续游戏」「返回主菜单」「退出游戏」
##
## 整棵 UI 子树在 _ready 中用代码构建，避免手写 tscn 的锚点/层级出错。
## 本场景根即为 Control（挂在游戏场景根 Node3D 下 → 锚点回退到视口，PRESET_FULL_RECT 即全屏）。
## 关键：process_mode 设为 ALWAYS，保证游戏暂停时本节点仍能接收输入以关闭界面。
##
## 【自适应】以 720p 为基准按视口高度缩放（0.85~2.6 倍），窗口尺寸变化时重建。
## 【关键坑·勿改回】面板必须用 PanelContainer 而非 Panel：Panel 不是容器、不给子节点布局，
## 里面的 MarginContainer 只会拿到最小尺寸并钉在左上角 → 界面又小又不居中。

const BG_COLOR := Color(0.0, 0.0, 0.0, 0.6)
const PANEL_BG := Color(0.16, 0.16, 0.19, 0.96)
const BTN_COLOR := Color(0.28, 0.30, 0.34, 1.0)
const QUIT_COLOR := Color(0.58, 0.18, 0.18, 1.0)
const BASE_H := 720.0

func _ready() -> void:
	# 暂停时本节点仍需处理输入（否则无法用 ESC 关闭界面）
	process_mode = Node.PROCESS_MODE_ALWAYS
	if get_viewport() != null:
		get_viewport().size_changed.connect(_rebuild)
	_build_ui()
	# 初始隐藏
	visible = false

## 窗口尺寸变化：摘除旧 UI 并按新尺寸重建（visible 状态由外部维持，不在此改动）
func _rebuild() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_build_ui()

## 自适应缩放因子（以 720p 高度为基准）
func _ui_scale() -> float:
	var sz := get_viewport_rect().size
	if sz.y <= 0.0:
		return 1.0
	return clampf(sz.y / BASE_H, 0.85, 2.6)

## 构建界面：半透明背景 + 居中自适应面板 + 标题 + 三个按钮
func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var s := _ui_scale()

	# 半透明背景：拦截鼠标，点击空白不穿透到游戏
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = BG_COLOR
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	# 居中容器，铺满（CenterContainer 会把子节点按其最小尺寸居中摆放）
	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	# 面板：宽度随屏，高度由内容决定
	var card := PanelContainer.new()
	card.name = "Panel"
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.set_corner_radius_all(int(12 * s))
	sb.set_border_width_all(maxi(1, int(2 * s)))
	sb.border_color = Color(0.32, 0.35, 0.42, 1.0)
	card.add_theme_stylebox_override("panel", sb)
	var vw := get_viewport_rect().size.x
	card.custom_minimum_size = Vector2(clampf(vw * 0.30, 340.0, 620.0 * s), 0.0)
	center.add_child(card)

	# 内边距
	var pad := MarginContainer.new()
	pad.name = "Pad"
	var p := int(34 * s)
	pad.add_theme_constant_override("margin_left", p)
	pad.add_theme_constant_override("margin_top", p)
	pad.add_theme_constant_override("margin_right", p)
	pad.add_theme_constant_override("margin_bottom", p)
	card.add_child(pad)

	# 纵向排布（标题 + 按钮）
	var inner := VBoxContainer.new()
	inner.name = "Inner"
	inner.add_theme_constant_override("separation", int(16 * s))
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	pad.add_child(inner)

	var title := Label.new()
	title.name = "Title"
	title.text = "暂停"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", int(34 * s))
	title.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	inner.add_child(title)

	_add_btn(inner, "ResumeButton", "继续游戏", BTN_COLOR, _on_resume_pressed)
	_add_btn(inner, "MainMenuButton", "返回主菜单", BTN_COLOR, _on_main_menu_pressed)
	_add_btn(inner, "QuitButton", "退出游戏", QUIT_COLOR, _on_quit_pressed)

## 生成一个自适应按钮（横向铺满面板内容宽、高度随屏缩放）
func _add_btn(parent: VBoxContainer, node_name: String, text: String, color: Color, cb: Callable) -> Button:
	var s := _ui_scale()
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, int(56 * s))
	b.add_theme_font_size_override("font_size", int(24 * s))
	b.add_theme_stylebox_override("normal", _make_btn_style(color))
	b.add_theme_stylebox_override("hover", _make_btn_style(color.lightened(0.12)))
	b.add_theme_stylebox_override("pressed", _make_btn_style(color.darkened(0.15)))
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

## 生成按钮样式
func _make_btn_style(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(int(6 * _ui_scale()))
	return sb

## ESC 开关：界面开着就关，关着就开
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if visible:
			close()
		else:
			open()

## 打开设置：暂停 + 唤出鼠标
func open() -> void:
	if visible:
		return
	visible = true
	(Engine.get_main_loop() as SceneTree).paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## 关闭设置：继续 + 重新捕获鼠标
func close() -> void:
	if not visible:
		return
	visible = false
	# 【修复】关闭时释放按钮焦点：否则焦点残留在按钮上，
	# 键盘事件（Q 等）可能被焦点按钮的 GUI 路径抢先消费 → 游戏键失效。
	release_focus()
	(Engine.get_main_loop() as SceneTree).paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## "继续游戏"按钮
func _on_resume_pressed() -> void:
	close()

## "退出游戏"按钮
func _on_quit_pressed() -> void:
	get_tree().quit()

## "返回主菜单"按钮：先解除暂停并重捕获鼠标，再切回主菜单
func _on_main_menu_pressed() -> void:
	close()
	# 主菜单需要可见鼠标（close() 会重新捕获，这里覆盖回来）
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
