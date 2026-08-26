extends Control
## 菜单 UI 基类：提供「随窗口/分辨率自适应缩放」的响应式布局与常用控件工厂。
## 子类只需重写 _build()，在其中调用 _make_panel() 拿到居中内容容器并往里加控件。
##
## 自适应策略：以 720p 为基准，按视口高度线性缩放并夹紧（0.85~2.6 倍）；
## 外层卡片铺满屏幕（留边距），内容列限宽并水平居中；窗口尺寸变化时整体重建。
##
## 【关键坑·勿改回】节点层级必须用 PanelContainer 而不是 Panel：
## Panel 是普通 Control **不是容器**，不会给子节点做布局 → 塞进去的 MarginContainer
## 只能拿到「最小尺寸」并钉在左上角 → 内容不居中、ItemList 高度塌成 0（列表条完全看不见）。
## PanelContainer 才会把子节点拉满自身区域。

const BTN_COLOR := Color(0.28, 0.30, 0.34, 1.0)
const QUIT_COLOR := Color(0.58, 0.18, 0.18, 1.0)
const BASE_H := 720.0                                  ## 缩放基准分辨率高度

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if get_viewport() != null:
		get_viewport().size_changed.connect(_on_resize)
	_build()

## 窗口尺寸变化：清空子节点并按新尺寸重建，保证始终适配屏幕。
## 先 remove_child 再 queue_free：queue_free 到帧末才真正删除，
## 若不先摘除，新旧两套 UI 会在同一帧重叠显示。
func _on_resize() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_build()

## 子类重写：构建菜单内容
func _build() -> void:
	pass

## 自适应缩放因子：以 720p 高度为基准
func _ui_scale() -> float:
	var sz := get_viewport_rect().size
	if sz.y <= 0.0:
		return 1.0
	return clampf(sz.y / BASE_H, 0.85, 2.6)

## 内容列宽度：屏宽的 55%，但不超过 760*缩放，也不低于 320
func _content_width() -> float:
	var vw := get_viewport_rect().size.x
	if vw <= 0.0:
		return 640.0
	return maxf(minf(vw * 0.55, 760.0 * _ui_scale()), 320.0)

## 创建背景 + 全屏自适应卡片 + 水平居中限宽内容列，返回 VBoxContainer 供子类填充
func _make_panel(title_text: String) -> VBoxContainer:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var s := _ui_scale()

	# 背景铺满并拦截鼠标
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.11, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	# 外边距 → 卡片（PanelContainer 会把子节点拉满，见文件头注释）
	var outer := MarginContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var m := int(40 * s)
	outer.add_theme_constant_override("margin_left", m)
	outer.add_theme_constant_override("margin_top", m)
	outer.add_theme_constant_override("margin_right", m)
	outer.add_theme_constant_override("margin_bottom", m)
	add_child(outer)

	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.14, 0.15, 0.18, 0.97)
	sb.set_corner_radius_all(int(14 * s))
	sb.set_border_width_all(maxi(1, int(2 * s)))
	sb.border_color = Color(0.30, 0.33, 0.40, 1.0)
	card.add_theme_stylebox_override("panel", sb)
	outer.add_child(card)

	# 卡片内边距
	var pad := MarginContainer.new()
	var p := int(36 * s)
	pad.add_theme_constant_override("margin_left", p)
	pad.add_theme_constant_override("margin_top", p)
	pad.add_theme_constant_override("margin_right", p)
	pad.add_theme_constant_override("margin_bottom", p)
	card.add_child(pad)

	# 卡片主列：标题在上，下方为水平居中的内容区
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", int(20 * s))
	pad.add_child(col)

	if title_text != "":
		var t := Label.new()
		t.text = title_text
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		t.add_theme_font_size_override("font_size", int(42 * s))
		t.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		col.add_child(t)

	# 水平居中：左右弹性空白夹住限宽内容列
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(row)

	var left := Control.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)

	var content := VBoxContainer.new()
	content.custom_minimum_size = Vector2(_content_width(), 0)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", int(18 * s))
	row.add_child(content)

	var right := Control.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)

	return content

## 往内容容器 v 加一个按钮（横向铺满、高度随屏缩放），点击触发 cb
func _add_btn(v: VBoxContainer, text: String, cb: Callable, color: Color = BTN_COLOR) -> Button:
	var s := _ui_scale()
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, int(60 * s))
	b.add_theme_font_size_override("font_size", int(26 * s))
	b.add_theme_stylebox_override("normal", _style(color))
	b.add_theme_stylebox_override("hover", _style(color.lightened(0.12)))
	b.add_theme_stylebox_override("pressed", _style(color.darkened(0.15)))
	b.pressed.connect(cb)
	v.add_child(b)
	return b

## 往内容容器加一行居中提示文字，返回 Label 供后续刷新
func _add_hint(v: VBoxContainer, text: String = "") -> Label:
	var s := _ui_scale()
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", int(21 * s))
	l.add_theme_color_override("font_color", Color(0.85, 0.86, 0.92, 1.0))
	v.add_child(l)
	return l

## 往内容容器加一个自适应选项列表。
## 【关键】必须给 custom_minimum_size.y：ItemList 自身最小高度为 0，
## 只靠 SIZE_EXPAND_FILL 在某些父布局下会塌成 0 高 → 选项条完全不可见。
func _make_list(v: VBoxContainer) -> ItemList:
	var s := _ui_scale()
	var vh := get_viewport_rect().size.y
	var lst := ItemList.new()
	lst.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lst.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lst.custom_minimum_size = Vector2(0, maxf(vh * 0.30, 170.0 * s))
	lst.add_theme_font_size_override("font_size", int(26 * s))
	lst.add_theme_constant_override("v_separation", int(12 * s))
	lst.add_theme_constant_override("h_separation", int(10 * s))
	lst.add_theme_color_override("font_color", Color(0.92, 0.93, 0.97, 1.0))
	lst.add_theme_color_override("font_selected_color", Color(1, 1, 1, 1))
	var bgs := StyleBoxFlat.new()
	bgs.bg_color = Color(0.09, 0.10, 0.13, 1.0)
	bgs.set_corner_radius_all(int(8 * s))
	bgs.set_border_width_all(maxi(1, int(2 * s)))
	bgs.border_color = Color(0.26, 0.29, 0.35, 1.0)
	lst.add_theme_stylebox_override("panel", bgs)
	var sel := StyleBoxFlat.new()
	sel.bg_color = Color(0.20, 0.44, 0.74, 1.0)
	sel.set_corner_radius_all(int(6 * s))
	lst.add_theme_stylebox_override("selected", sel)
	lst.add_theme_stylebox_override("selected_focus", sel)
	v.add_child(lst)
	return lst

func _style(c: Color) -> StyleBoxFlat:
	var s := _ui_scale()
	var st := StyleBoxFlat.new()
	st.bg_color = c
	st.set_corner_radius_all(int(8 * s))
	return st
