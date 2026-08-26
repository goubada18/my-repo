extends SceneTree
## 从新导出 glb 提取尼泊尔 3P 手臂动画资源（只取 8 骨 rotation 轨迹，跳过 position）
## 输出：
##   nepal_idle_arms.tres   = 重击末帧静态姿态（待机持刀）
##   nepal_light_arms.tres  = 轻击挥砍（0.633s）
##   nepal_heavy_arms.tres  = 重击挥砍（1.5s）

const ARMS_BONES := [
	"LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
	"RightShoulder", "RightArm", "RightForeArm", "RightHand",
]
const OUT_DIR := "res://resources/animations/nepal3p/"

func _init() -> void:
	# 1) 加载 glb：Blender glb 导出只完整 bake「激活的 action」，
	#    故轻击必须从 nepal_light.glb 取、重击/待机从 nepal_heavy.glb 取。
	var light: PackedScene = load("res://resources/animations/nepal3p/nepal_light.glb")
	var heavy: PackedScene = load("res://resources/animations/nepal3p/nepal_heavy.glb")
	if light == null or heavy == null:
		printerr("FAIL: 无法加载 glb light=", light != null, " heavy=", heavy != null)
		quit()
		return
	# 轻击：从 nepal_light.glb 找「轻击」动画
	var light_anim: Animation = _find_anim(light, "轻击")
	# 重击：从 nepal_heavy.glb 找「重击」动画
	var heavy_anim: Animation = _find_anim(heavy, "重击")
	if light_anim == null or heavy_anim == null:
		printerr("FAIL: 找不到动画 light=", light_anim != null, " heavy=", heavy_anim != null)
		quit()
		return
	print("轻击 len=", light_anim.length, " 重击 len=", heavy_anim.length)

	# 2) 提取手臂 rotation 轨迹
	var light_arms: Animation = _extract_arms(light_anim)
	var heavy_arms: Animation = _extract_arms(heavy_anim)
	# 3) 待机 = 重击末帧静态姿态
	var idle_arms: Animation = _extract_idle_from_end(heavy_anim)
	print("提取完成: light_tracks=", light_arms.get_track_count(),
		" heavy_tracks=", heavy_arms.get_track_count(),
		" idle_tracks=", idle_arms.get_track_count())

	# 4) 保存
	for pair in [["nepal_idle_arms.tres", idle_arms], ["nepal_light_arms.tres", light_arms], ["nepal_heavy_arms.tres", heavy_arms]]:
		var err := ResourceSaver.save(pair[1], OUT_DIR + pair[0])
		print("SAVE ", pair[0], " -> ", err, " (0=OK)")
	quit()

## 从 PackedScene 实例的动画库中按名字片段找动画
func _find_anim(sc: PackedScene, name_part: String) -> Animation:
	var inst = sc.instantiate()
	get_root().add_child(inst)
	var ap: AnimationPlayer = null
	for n in inst.get_children():
		if n is AnimationPlayer:
			ap = n
			break
	if ap == null:
		inst.queue_free()
		return null
	var lib = ap.get_animation_library("")
	for an in lib.get_animation_list():
		if String(an).contains(name_part):
			var a: Animation = lib.get_animation(an)
			inst.queue_free()
			return a
	inst.queue_free()
	return null

## 提取 8 骨 rotation 轨迹（跳过 position），长度与原动画一致
func _extract_arms(src: Animation) -> Animation:
	var dst := Animation.new()
	dst.length = src.length
	dst.loop_mode = src.loop_mode
	for ti in src.get_track_count():
		if src.track_get_type(ti) != Animation.TYPE_ROTATION_3D:
			continue
		var p := String(src.track_get_path(ti))
		var bone := _bone_of(p)
		if bone == "" or not ARMS_BONES.has(bone):
			continue
		var nt := dst.add_track(Animation.TYPE_ROTATION_3D)
		dst.track_set_path(nt, NodePath(p))
		dst.track_set_interpolation_type(nt, Animation.INTERPOLATION_LINEAR)
		var kc := src.track_get_key_count(ti)
		for k in kc:
			dst.track_insert_key(nt, src.track_get_key_time(ti, k), src.track_get_key_value(ti, k))
	return dst

## 提取重击末帧 8 骨静态姿态（每个骨 1 个关键帧，长度 0.01）
func _extract_idle_from_end(src: Animation) -> Animation:
	var dst := Animation.new()
	dst.length = 0.0166667
	dst.loop_mode = Animation.LOOP_LINEAR
	var t_end := src.length
	for ti in src.get_track_count():
		if src.track_get_type(ti) != Animation.TYPE_ROTATION_3D:
			continue
		var p := String(src.track_get_path(ti))
		var bone := _bone_of(p)
		if bone == "" or not ARMS_BONES.has(bone):
			continue
		var kc := src.track_get_key_count(ti)
		var val: Quaternion = src.track_get_key_value(ti, kc - 1)
		var nt := dst.add_track(Animation.TYPE_ROTATION_3D)
		dst.track_set_path(nt, NodePath(p))
		dst.track_set_interpolation_type(nt, Animation.INTERPOLATION_LINEAR)
		dst.track_insert_key(nt, 0.0, val)
	return dst

func _bone_of(p: String) -> String:
	# 路径形如 Armature/Skeleton3D:mixamorig_LeftShoulder → 去前缀取纯骨名
	var idx := p.rfind(":")
	if idx < 0:
		return ""
	var b := p.substr(idx + 1)
	return b.replace("mixamorig_", "")
