extends CanvasLayer
## M82 右键开镜前景：全屏 PNG（瞄准镜框）+ FOV 缩放控制
## 由 player.gd 调用 enter() / exit()（toggle：单击开镜，再单击关镜）
##
## 【十字对齐 + 屏幕铺满】原理（适配所有显示器分辨率）：
##   设图片 w×h，十字交点 (cx,cy) 在图片像素坐标。视口 VW×VH。
##   让图片均匀缩放 s 后绘制到 rect=(pos, pos+(w·s, h·s))，十字对屏幕中心：
##     pos = (VW/2 - cx·s, VH/2 - cy·s)
##   "四周铺满不留空"要求 rect 完全包含视口：
##     pos.x ≤ 0 ∧ pos.x + w·s ≥ VW  →  s ≥ VW/(2·cx) 且 s ≥ VW/(2·(w−cx))
##     pos.y ≤ 0 ∧ pos.y + h·s ≥ VH  →  s ≥ VH/(2·cy) 且 s ≥ VH/(2·(h−cy))
##   故 s_min = max(VW/(2·cx), VW/(2·(w−cx)), VH/(2·cy), VH/(2·(h−cy)))
##   STRETCH_KEEP_ASPECT_COVERED 模式：rect 与图同比例 → 恰好填满，viewport 裁掉超出。
##   不修改 PNG（透明通道原样保留），不变形。

@export var scope_texture_path: String = "res://ui/m82_scope.png"
@export var default_zoom_factor: float = 4.0   # 4 倍放大（FOV = 当前FOV / 4）

## 十字架交点（PNG 像素坐标）。tools/probe_scope_center.gd 镜头暗区窄峰实测：
## 图 1607×1158，竖线窄峰 x=801（宽 5px）、横线窄峰 y=613（宽 3px）→ 交点 (801,613)。
## 【F-03 资产校准值】运行时以此 @export 值为准（不做像素级自动检测，避免每次加载引入回归风险）。
## 替换开镜图后须用 `godot --headless --path . -s tools/probe_scope_center.gd` 重新测量并改此值，否则十字错位。
## 【F-10 资产约束】本 PNG 四角须保持透明（ui/m82_scope.png.import 的 fix_alpha_border=false），否则屏幕边缘漏图。
@export var crosshair_px: Vector2 = Vector2(801, 613)

var _tex_rect: TextureRect = null
var _base_fov: float = 70.0
var _zoom_fov: float = 17.5
var _scoping: bool = false

func _ready() -> void:
	layer = 100  # 最高层（覆盖 HUD）
	visible = false
	_tex_rect = TextureRect.new()
	_tex_rect.name = "ScopeTex"
	_tex_rect.anchor_left = 0.0
	_tex_rect.anchor_top = 0.0
	_tex_rect.anchor_right = 1.0
	_tex_rect.anchor_bottom = 1.0
	_tex_rect.offset_left = 0.0
	_tex_rect.offset_top = 0.0
	_tex_rect.offset_right = 0.0
	_tex_rect.offset_bottom = 0.0
	_tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# 均匀缩放、rect 与图同比例 → 恰好填满，超出视口被裁；不变形，PNG 透明通道保留
	_tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 穿透点击
	var tex: Texture2D = load(scope_texture_path) as Texture2D
	if tex != null:
		_tex_rect.texture = tex
		_apply_centering(tex)
	else:
		push_warning("ScopeOverlay: 无法加载 " + scope_texture_path)
	add_child(_tex_rect)
	if get_viewport() != null:
		get_viewport().size_changed.connect(_on_viewport_resized)

## 视口尺寸变化（显示器/窗口改分辨率）：重算偏移，十字保持对准屏幕中心、铺满保持
func _on_viewport_resized() -> void:
	if _tex_rect != null and _tex_rect.texture != null:
		_apply_centering(_tex_rect.texture)

func _apply_centering(tex: Texture2D) -> void:
	if get_viewport() == null:
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_apply_centering_to(tex, vp)

## 核心纯函数：根据图片尺寸 + 视口尺寸计算矩形参数（pos、size、scale）
## 公式见文件头推导；返回 Dictionary 便于测试
static func compute_centering(tex_size: Vector2, crosshair_px: Vector2, vp: Vector2) -> Dictionary:
	if tex_size.x <= 0.0 or tex_size.y <= 0.0 or vp.x <= 0.0 or vp.y <= 0.0:
		return {}
	var w: float = tex_size.x; var h: float = tex_size.y
	var cx: float = clampf(crosshair_px.x, 1.0, w - 1.0)
	var cy: float = clampf(crosshair_px.y, 1.0, h - 1.0)
	var scale: float = maxf(
		maxf(vp.x / (2.0 * cx), vp.x / (2.0 * (w - cx))),
		maxf(vp.y / (2.0 * cy), vp.y / (2.0 * (h - cy)))
	)
	var pos_x: float = vp.x / 2.0 - cx * scale
	var pos_y: float = vp.y / 2.0 - cy * scale
	return {"pos": Vector2(pos_x, pos_y), "size": Vector2(w * scale, h * scale), "scale": scale}

## 核心：根据图片尺寸 + 视口尺寸计算矩形参数并应用到 TextureRect
## 返回 {pos, size, scale} 便于测试
func _apply_centering_to(tex: Texture2D, vp: Vector2) -> Dictionary:
	var ts: Vector2 = tex.get_size()
	var r: Dictionary = compute_centering(ts, crosshair_px, vp)
	if r.is_empty() or _tex_rect == null:
		return r
	var pos: Vector2 = r.pos
	var sz: Vector2 = r.size
	# TextureRect (anchors 0..1): rect.position = (offset_left, offset_top)
	#   rect.size = (vp + offset_right - offset_left, vp + offset_bottom - offset_top)
	# 要 rect = (pos, sz)
	_tex_rect.offset_left = pos.x
	_tex_rect.offset_right = pos.x + sz.x - vp.x
	_tex_rect.offset_top = pos.y
	_tex_rect.offset_bottom = pos.y + sz.y - vp.y
	return r

## 进入开镜：记录基线 FOV + 立即把 FOV 设为放大值（无过渡，瞬间稳定 4x）
## 【F-01 重入守卫】已在开镜时直接 return，防止任何绕过 player._enter_scope 的路径
## 重复调用 enter() 把 _base_fov 写成已缩放值（17.5）→ exit 时恢复成缩放值 → 永久 4× 锁定。
## 正常流程下 player._enter_scope 已先守卫，本守卫为纯防御、零行为变化；
## re-scope 流程在调用 enter() 前已先 exit()（overlay._scoping=false），不会被误挡。
func enter(camera: Camera3D, zoom_factor: float = 4.0) -> void:
	if _scoping:
		return
	if camera == null:
		return
	_scoping = true
	_base_fov = camera.fov
	_zoom_fov = maxf(camera.fov / zoom_factor, 5.0)  # 防过小
	camera.fov = _zoom_fov
	visible = true

## 退出开镜：立即恢复基线 FOV + 隐藏前景
## 【修复】camera 为 null 时改从视口取当前相机兜底恢复 FOV：原先只复位 _scoping
## 而 FOV 停在放大值（永久 4×），且下次 enter 的重入守卫还会把坏值记成新 base。
func exit(camera: Camera3D) -> void:
	if not _scoping:
		return
	var cam: Camera3D = camera
	if cam == null and get_viewport() != null:
		cam = get_viewport().get_camera_3d()
	if cam != null:
		cam.fov = _base_fov
	else:
		push_warning("ScopeOverlay.exit: 无法定位相机恢复 FOV")
	_scoping = false
	visible = false

## 【F-06】CanvasLayer 释放时断开 size_changed 信号，避免悬挂回调（当前单实例/生命周期=角色，低风险，仍补防御）
func _exit_tree() -> void:
	if get_viewport() != null and get_viewport().size_changed.is_connected(_on_viewport_resized):
		get_viewport().size_changed.disconnect(_on_viewport_resized)

func is_active() -> bool:
	return _scoping
