extends SceneTree
## grenade3p_kit.gd —— 手雷 3P 手臂动画管线工具包（效仿尼泊尔 nepal3p 流程）
##
## 模式一（默认）：--export-ref  生成 Blender 参考包
##   输出 resources/animations/grenade3p/ref/：
##   - pistol_idle_swat_ref.gltf   SWAT手枪待机全身旋转轨道 → Blender 可直接导入的
##                                 节点动画（对照手臂基础姿态用）
##   - 骨骼姿态对照表.txt          8 臂骨+脊柱的四元数→欧拉角对照（辅助参考）
##   FP 参考无需转换：直接在 Blender 里导入 fp_viewmodel/gaobao/v_gaobao_viewmodel.gltf
##   （含 idle / plugin拉环 / Throw投掷 / draw 四段动画）
##
## 模式二：--build pull=<glb> throw=<glb>   导入手工动画（Blender 完成后）
##   要求（与尼泊尔同款铁律，详见 docs/尼泊尔3P动画管线完整手册.md）：
##   - Blender 骨架命名必须为 Armature，骨骼名 mixamorig_*（轨迹前缀自动对齐）
##   - 只 K 8 臂骨的【旋转】轨道（位置轨道一律不要）
##   - 每 action 导出一个 glb（Blender 只 bake 激活 action）：
##       grenade_pull.glb（拉环，末帧=持环等待姿态）
##       grenade_throw.glb（投掷）
##   输出：
##   - resources/animations/grenade3p/grenade_pull_arms.tres   （拉环全程）
##   - resources/animations/grenade3p/grenade_hold_arms.tres   （拉环末帧静态=持环等待）
##   - resources/animations/grenade3p/grenade_throw_arms.tres  （投掷全程）

const ARMS_BONES := [
	"LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
	"RightShoulder", "RightArm", "RightForeArm", "RightHand",
]
const OUT_DIR := "res://resources/animations/grenade3p/"
const REF_DIR := "res://resources/animations/grenade3p/ref/"
const PISTOL_IDLE := "res://resources/animations/pistol_idle_swat.tres"

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var pull := ""
	var throw := ""
	for a in args:
		if a.begins_with("--pull="):
			pull = a.substr(7)
		elif a.begins_with("--throw="):
			throw = a.substr(8)
		elif a == "--export-ref":
			_export_ref()
			quit(0)
			return
	if pull != "" or throw != "":
		_build(pull, throw)
		var rc := 0 if (pull != "" and throw != "") else 1
		quit(rc)
		return
	print("grenade3p_kit 用法：")
	print("  参考包: godot --headless --path . --script res://tools/grenade3p_kit.gd -- --export-ref")
	print("  导入:   godot --headless --path . --script res://tools/grenade3p_kit.gd -- --build pull=<grenade_pull.glb> throw=<grenade_throw.glb>")
	quit(0)

# ================= 模式一：Blender 参考包 =================
func _export_ref() -> void:
	DirAccess.make_dir_recursive_absolute(REF_DIR.replace("res://", "C:/Users/93343/Desktop/demo/"))
	var anim: Animation = load(PISTOL_IDLE) as Animation
	if anim == null:
		printerr("FAIL: 无法加载 " + PISTOL_IDLE)
		quit(1)
		return
	var gltf_path := REF_DIR + "pistol_idle_swat_ref.gltf"
	var err := _write_ref_gltf(anim, gltf_path)
	print(("OK: " if err == OK else "FAIL: ") + gltf_path)
	_write_euler_table(anim, REF_DIR + "骨骼姿态对照表.txt")
	print("FP 参考（无需转换，Blender 直接导入）：fp_viewmodel/gaobao/v_gaobao_viewmodel.gltf")
	print("  动画名：idle=持枪待机 / plugin=拉环 / Throw=投掷 / draw=出枪")

## 把 Animation 的全部 rotation 轨道写成 glTF 节点动画（每轨道一个同名节点）
func _write_ref_gltf(anim: Animation, out_path: String) -> int:
	var tracks := []
	var seen := {}
	for i in anim.get_track_count():
		if anim.track_get_type(i) != Animation.TYPE_ROTATION_3D:
			continue
		var p := String(anim.track_get_path(i))
		var bone := p.substr(p.rfind(":") + 1)
		if bone == "" or seen.has(bone):
			continue
		seen[bone] = true
		var kc := anim.track_get_key_count(i)
		var times := PackedFloat32Array()
		var vals := PackedFloat32Array()
		for k in kc:
			times.append(anim.track_get_key_time(i, k))
			var q: Quaternion = anim.track_get_key_value(i, k)
			vals.append(q.x)
			vals.append(q.y)
			vals.append(q.z)
			vals.append(q.w)
		tracks.append({"bone": bone, "times": times, "vals": vals})
	if tracks.is_empty():
		printerr("FAIL: 无旋转轨道")
		return ERR_DOES_NOT_EXIST
	# 组装二进制 buffer（times f32 + vals f32 逐采样器拼接）
	var blob := PackedByteArray()
	var buffer_views := []
	var accessors := []
	var samplers := []
	var channels := []
	var nodes := []
	for t_i in tracks.size():
		var tr = tracks[t_i]
		nodes.append({"name": tr.bone})
		var t_bytes: PackedByteArray = tr.times.to_byte_array()
		var v_bytes: PackedByteArray = tr.vals.to_byte_array()
		var t_off := blob.size()
		blob.append_array(t_bytes)
		var v_off := blob.size()
		blob.append_array(v_bytes)
		buffer_views.append({"buffer": 0, "byteOffset": t_off, "byteLength": t_bytes.size()})
		buffer_views.append({"buffer": 0, "byteOffset": v_off, "byteLength": v_bytes.size()})
		var mn: float = INF
		var mx: float = -INF
		for v in tr.times:
			mn = minf(mn, v)
			mx = maxf(mx, v)
		accessors.append({"bufferView": buffer_views.size() - 2, "componentType": 5126,
			"count": tr.times.size(), "type": "SCALAR", "min": [mn], "max": [mx]})
		accessors.append({"bufferView": buffer_views.size() - 1, "componentType": 5126,
			"count": tr.vals.size() / 4, "type": "VEC4"})
		samplers.append({"input": accessors.size() - 2, "output": accessors.size() - 1,
			"interpolation": "LINEAR"})
		channels.append({"sampler": t_i, "target": {"node": t_i, "path": "rotation"}})
	var b64 := Marshalls.raw_to_base64(blob)
	var doc := {
		"asset": {"version": "2.0", "generator": "rushfire grenade3p_kit"},
		"scene": 0,
		"scenes": [{"nodes": range(nodes.size())}],
		"nodes": nodes,
		"animations": [{"name": "pistol_idle_swat", "samplers": samplers, "channels": channels}],
		"buffers": [{"byteLength": blob.size(), "uri": "data:application/octet-stream;base64," + b64}],
		"bufferViews": buffer_views,
		"accessors": accessors,
	}
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		printerr("FAIL: 无法写入 " + out_path)
		return ERR_CANT_OPEN
	f.store_string(JSON.stringify(doc, "  "))
	f.close()
	return OK

## 四元数 → 欧拉角对照表（辅助参考；精调以动画可视化对照为准）
func _write_euler_table(anim: Animation, out_path: String) -> void:
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string("手雷 3P 手臂姿态对照表（SWAT 手枪待机首帧，Godot YXZ 欧拉·度）\n")
	f.store_string("（Blender 导入 ref gltf 可视化对照为准；本表仅作数值参考）\n\n")
	for i in anim.get_track_count():
		if anim.track_get_type(i) != Animation.TYPE_ROTATION_3D:
			continue
		var p := String(anim.track_get_path(i))
		var bone := p.substr(p.rfind(":") + 1)
		var q: Quaternion = anim.track_get_key_value(i, 0)
		var e: Vector3 = Basis(q).get_euler()
		f.store_string("%s: (%.1f°, %.1f°, %.1f°)  q=(%.4f, %.4f, %.4f, %.4f)\n" % [
			bone, rad_to_deg(e.x), rad_to_deg(e.y), rad_to_deg(e.z), q.x, q.y, q.z, q.w])
	f.close()

# ================= 模式二：导入手工动画 =================
func _build(pull_path: String, throw_path: String) -> void:
	if pull_path == "" or throw_path == "":
		printerr("FAIL: --build 需要 pull= 与 throw= 两个 glb 路径")
		return
	DirAccess.make_dir_recursive_absolute(OUT_DIR.replace("res://", "C:/Users/93343/Desktop/demo/"))
	var pull_anim: Animation = _load_first_anim(pull_path)
	var throw_anim: Animation = _load_first_anim(throw_path)
	if pull_anim == null or throw_anim == null:
		printerr("FAIL: glb 中找不到动画 pull=", pull_anim != null, " throw=", throw_anim != null)
		return
	print("pull len=%.3f  throw len=%.3f" % [pull_anim.length, throw_anim.length])
	var pull_arms := _extract_arms(pull_anim)
	var throw_arms := _extract_arms(throw_anim)
	var hold_arms := _extract_hold_from_end(pull_anim)
	print("提取完成: pull_tracks=%d throw_tracks=%d hold_tracks=%d" % [
		pull_arms.get_track_count(), throw_arms.get_track_count(), hold_arms.get_track_count()])
	# 校验：8 臂骨必须全齐（缺骨=Blender 骨骼名/骨架名不对齐，运行时会静默缺轨道）
	for pair in [["grenade_pull_arms.tres", pull_arms], ["grenade_hold_arms.tres", hold_arms],
			["grenade_throw_arms.tres", throw_arms]]:
		var missing := _check_arms_bones(pair[1])
		if missing != "":
			printerr("FAIL: %s 缺骨骼轨道: %s（检查 Blender 骨架名是否为 Armature、骨骼名是否 mixamorig_*）" % [pair[0], missing])
			quit(1)
			return
	for pair in [["grenade_pull_arms.tres", pull_arms], ["grenade_hold_arms.tres", hold_arms],
			["grenade_throw_arms.tres", throw_arms]]:
		var err := ResourceSaver.save(pair[1], OUT_DIR + pair[0])
		print("SAVE %s -> err=%d (0=OK)" % [pair[0], err])
	print("BUILD_DONE>>> 下一步：接入运行时（见 docs/尼泊尔3P动画管线完整手册.md 手雷章节接入清单）")

func _load_first_anim(path: String) -> Animation:
	var ps: PackedScene = load(path) as PackedScene
	if ps == null:
		printerr("FAIL: 无法加载 " + path)
		return null
	var inst = ps.instantiate()
	get_root().add_child(inst)
	var found: Animation = null
	for n in inst.get_children():
		if n is AnimationPlayer:
			var lib := (n as AnimationPlayer).get_animation_library("")
			var list := lib.get_animation_list()
			if list.size() == 1:
				found = lib.get_animation(list[0])
			elif list.size() > 1:
				# 多动画时优先按名字片段匹配
				for an in list:
					if String(an).containsn("grenade") or String(an).containsn("pull") or String(an).containsn("throw"):
						found = lib.get_animation(an)
						break
				if found == null:
					found = lib.get_animation(list[0])
			break
	inst.queue_free()
	return found

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
		for k in src.track_get_key_count(ti):
			dst.track_insert_key(nt, src.track_get_key_time(ti, k), src.track_get_key_value(ti, k))
	return dst

## 拉环末帧静态姿态（持环等待）：每骨 1 关键帧，长度 1/60
func _extract_hold_from_end(src: Animation) -> Animation:
	var dst := Animation.new()
	dst.length = 0.0166667
	dst.loop_mode = Animation.LOOP_LINEAR
	var kc_last := src.track_get_key_count(0) if src.get_track_count() > 0 else 0
	for ti in src.get_track_count():
		if src.track_get_type(ti) != Animation.TYPE_ROTATION_3D:
			continue
		var p := String(src.track_get_path(ti))
		var bone := _bone_of(p)
		if bone == "" or not ARMS_BONES.has(bone):
			continue
		var kc := src.track_get_key_count(ti)
		if kc == 0:
			continue
		var val: Quaternion = src.track_get_key_value(ti, kc - 1)
		var nt := dst.add_track(Animation.TYPE_ROTATION_3D)
		dst.track_set_path(nt, NodePath(p))
		dst.track_set_interpolation_type(nt, Animation.INTERPOLATION_LINEAR)
		dst.track_insert_key(nt, 0.0, val)
	return dst

func _check_arms_bones(anim: Animation) -> String:
	var have := {}
	for ti in anim.get_track_count():
		var bone := _bone_of(String(anim.track_get_path(ti)))
		have[bone] = true
	var missing := []
	for b in ARMS_BONES:
		if not have.has(b):
			missing.append(b)
	return "" if missing.is_empty() else ", ".join(missing)

func _bone_of(p: String) -> String:
	var idx := p.rfind(":")
	if idx < 0:
		return ""
	return p.substr(idx + 1).replace("mixamorig_", "")
