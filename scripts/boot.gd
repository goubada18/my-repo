extends Control
## 启动预加载场景（项目主场景 run/main_scene）。
## F5 启动即进入此处：线程化预加载全部游戏资源并显示进度条，加载完毕后进入主菜单。
## 资源清单来自角色注册表（角色场景 + 各武器 FP 视图模型/配置）与主游戏场景本身。

var _queue: Array = []
var _idx: int = 0
var _progress := []

@onready var _bar: ProgressBar
@onready var _pct: Label
@onready var _status: Label

func _ready() -> void:
	_build_ui()
	_gather()
	if _queue.is_empty():
		_goto_menu()
		return
	_start_next()

## 自适应缩放因子（以 720p 为基准）
func _ui_scale() -> float:
	var sz := get_viewport_rect().size
	if sz.y <= 0:
		return 1.0
	return clamp(sz.y / 720.0, 0.85, 2.6)

## 构建进度条 UI（代码构建，随屏缩放）
func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var s := _ui_scale()
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.11, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(20 * s))
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.custom_minimum_size = Vector2(int(660 * s), 0)
	center.add_child(vbox)
	var title := Label.new()
	title.text = "TPP_FPS_Action_Demo"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", int(36 * s))
	title.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	vbox.add_child(title)
	_bar = ProgressBar.new()
	_bar.name = "ProgressBar"
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar.custom_minimum_size = Vector2(0, int(30 * s))
	_bar.max_value = 1.0
	_bar.value = 0.0
	_bar.show_percentage = false
	vbox.add_child(_bar)
	_pct = Label.new()
	_pct.text = "0%"
	_pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pct.add_theme_font_size_override("font_size", int(20 * s))
	vbox.add_child(_pct)
	_status = Label.new()
	_status.text = "准备加载..."
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", int(18 * s))
	_status.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85, 1))
	vbox.add_child(_status)

## 收集需要预加载的资源路径（去重）
func _gather() -> void:
	var reg := load("res://resources/characters/character_registry.tres") as CharacterRegistry
	# 【设置界面崩溃修复】首次加载后缓存到 GameState，settings_screen 不再重复 load
	# （进过游戏后二次 load 会触发 Godot 4.7 资源缓存 bug 崩溃）。
	if reg != null:
		GameState.character_registry = reg
	if reg != null:
		for asset in reg.characters:
			var ca := asset as CharacterAsset
			if ca == null:
				continue
			if ca.character_scene != null and ca.character_scene.resource_path != "":
				_queue.append(ca.character_scene.resource_path)
			for w in ca.weapons:
				var d := w as WeaponDef
				if d == null:
					continue
				if d.fp_viewmodel_scene != "":
					_queue.append(d.fp_viewmodel_scene)
				if d.fp_viewmodel_cfg != "":
					_queue.append(d.fp_viewmodel_cfg)
	# 主游戏地图场景（含其全部依赖，由 Godot 自动递归加载）
	_queue.append("res://scenes/main_multichar.tscn")
	var seen := {}
	var uniq := []
	for p in _queue:
		if p != "" and not seen.has(p):
			seen[p] = true
			uniq.append(p)
	_queue = uniq

func _start_next() -> void:
	if _idx >= _queue.size():
		_goto_menu()
		return
	var p: String = _queue[_idx]
	if ResourceLoader.exists(p):
		ResourceLoader.load_threaded_request(p, "", true)
	_status.text = "加载资源 %d / %d" % [_idx + 1, _queue.size()]

func _process(_d: float) -> void:
	if _idx >= _queue.size():
		return
	var p: String = _queue[_idx]
	var st: int = ResourceLoader.load_threaded_get_status(p, _progress)
	if st == ResourceLoader.THREAD_LOAD_LOADED:
		_idx += 1
		_update(1.0)
		_start_next()
	elif st == ResourceLoader.THREAD_LOAD_FAILED:
		_idx += 1
		_start_next()
	elif st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		if _progress.size() > 0:
			_update(_progress[0])

func _update(local: float) -> void:
	if _bar == null:
		return
	var v := (_idx + local) / float(maxi(_queue.size(), 1))
	_bar.value = v
	_pct.text = "%d%%" % int(v * 100.0)

func _goto_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
