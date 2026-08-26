extends Node

## M82A1 真实渲染验证（v2）：加载多角色场景 → V 切 FP → X 切 M82A1 →
## 用相机 unproject 把每个网格世界 AABB 角点投影到屏幕，量化"屏幕可见性"。

const SHOT_AK := "C:/Users/93343/Desktop/demo/tools/m82_verify_ak.png"
const SHOT_M82 := "C:/Users/93343/Desktop/demo/tools/m82_verify_m82.png"

func _key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	ev.echo = false
	Input.parse_input_event(ev)

func _screen_dump(tag: String) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		print("[%s] no camera" % tag)
		return
	var vp := get_viewport()
	var w: int = vp.get_visible_rect().size.x
	var h: int = vp.get_visible_rect().size.y
	print("[%s] screen=%dx%d cam_fov=%s near=%s far=%s cam_pos=%s" % [tag, w, h, cam.fov, cam.near, cam.far, cam.global_position])
	var player := get_tree().root.find_child("Player", true, false)
	if player == null:
		return
	var fp_vm = player.get("_fp_vm")
	var model = fp_vm.get("_model") if fp_vm != null else null
	if model == null:
		print("[%s] no model" % tag)
		return
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		if not mi.visible:
			continue
		var la: AABB = mi.get_aabb()
		var gt: Transform3D = mi.global_transform
		var mn := Vector2(1e9, 1e9)
		var mx := Vector2(-1e9, -1e9)
		var in_front := 0
		var total := 0
		for xi in [0, 1]:
			for yi in [0, 1]:
				for zi in [0, 1]:
					var wp := gt * (la.position + Vector3(la.size.x * xi, la.size.y * yi, la.size.z * zi))
					var sp: Vector2 = cam.unproject_position(wp)
					mn = Vector2(min(mn.x, sp.x), min(mn.y, sp.y))
					mx = Vector2(max(mx.x, sp.x), max(mx.y, sp.y))
					# 相机前方判断
					var cam_fwd: Vector3 = -cam.global_transform.basis.z
					if cam_fwd.dot(wp - cam.global_position) > 0.0:
						in_front += 1
					total += 1
		var onscreen: int = 0
		if mx.x > 0 and mn.x < w and mx.y > 0 and mn.y < h:
			onscreen = 1
		print("[%s] '%s' screen_px=(%.0f,%.0f)-(%.0f,%.0f) size=(%.0f,%.0f) onscreen=%d front=%d/%d" % [
			tag, mi.name, mn.x, mn.y, mx.x, mx.y, mx.x - mn.x, mx.y - mn.y, onscreen, in_front, total])

func _snap(path: String, tag: String) -> void:
	for i in range(8):
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("[%s] 截图 %s (%dx%d)" % [tag, path, img.get_width(), img.get_height()])

func _ready() -> void:
	print("=== M82A1 真实渲染验证 v2 开始 ===")
	var main = load("res://scenes/main_multichar.tscn").instantiate()
	add_child(main)
	var player: Node = null
	for i in range(180):
		player = main.get_node_or_null("Player")
		if player != null:
			break
		await get_tree().process_frame
	if player == null:
		print("FAIL 找不到 Player")
		get_tree().quit(1)
		return
	for i in range(40):
		await get_tree().process_frame
	_key(KEY_V)   # FP
	for i in range(60):
		await get_tree().process_frame
	_screen_dump("AK47")
	await _snap(SHOT_AK, "AK47")
	_key(KEY_X)   # 切 M82A1
	for i in range(90):
		await get_tree().process_frame
	_screen_dump("M82A1")
	await _snap(SHOT_M82, "M82A1")
	print("=== 验证完成 ===")
	get_tree().quit(0)
