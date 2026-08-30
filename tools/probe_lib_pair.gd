extends SceneTree
## 一次性诊断（全库版）：逐动画输出两库关系指纹（位置比率中位数/方向保持率/旋转差分布），
## 揭示 2026-08-14 生成的 SWAT 库与飞虎库之间真实的逐动画结构。
func _init() -> void:
	var src: AnimationLibrary = load("res://resources/mixamo_lib.tres")
	var dst: AnimationLibrary = load("res://resources/mixamo_lib_swat.tres")
	for n in src.get_animation_list():
		if not dst.has_animation(n):
			print("%s: 仅飞虎" % n)
			continue
		var a: Animation = src.get_animation(n)
		var b: Animation = dst.get_animation(n)
		var ratios := []
		var dir_kept := 0
		var dir_broke := 0
		var rot_id := 0
		var rot_moved: Array = []
		for i in a.get_track_count():
			var t: int = a.track_get_type(i)
			var path := String(a.track_get_path(i))
			var j := _find(b, t, path)
			if j < 0:
				continue
			var kc: int = a.track_get_key_count(i)
			if t == Animation.TYPE_POSITION_3D:
				for k in range(0, kc, maxi(1, kc / 4)):
					var va: Vector3 = a.track_get_key_value(i, k)
					var vb: Vector3 = b.track_get_key_value(j, k)
					if va.length() > 1e-4 and vb.length() > 1e-4:
						ratios.append(vb.length() / va.length())
						if rad_to_deg(va.normalized().angle_to(vb.normalized())) > 1.5:
							dir_broke += 1
						else:
							dir_kept += 1
			elif t == Animation.TYPE_ROTATION_3D:
				var maxd := 0.0
				for k in range(0, kc, maxi(1, kc / 4)):
					var qa: Quaternion = a.track_get_key_value(i, k)
					var qb: Quaternion = b.track_get_key_value(j, k)
					maxd = maxf(maxd, rad_to_deg(qa.angle_to(qb)))
				var bone: String = path.get_slice(":", path.rfind(":") + 1)
				if maxd > 0.1:
					rot_moved.append("%s(%.1f°)" % [bone, maxd])
				else:
					rot_id += 1
		var rm := _median(ratios)
		print("%s: pos比率中位=%.4f 方向保持%d/改%d 旋转恒等%d 变化%s" % [
			n, rm, dir_kept, dir_broke, rot_id, str(rot_moved)])
	quit(0)

func _find(a: Animation, type: int, path: String) -> int:
	for i in a.get_track_count():
		if a.track_get_type(i) == type and String(a.track_get_path(i)) == path:
			return i
	return -1

func _median(arr: Array) -> float:
	if arr.is_empty():
		return -1.0
	var s := arr.duplicate()
	s.sort()
	return s[s.size() / 2]
