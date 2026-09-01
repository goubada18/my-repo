extends SceneTree
## 验证：Toss Grenade 拉环段 31 帧 vs 37 帧 的臂骨姿态差。
## 若差极小 → 31 帧后动作几乎静止（Mixamo 数据特征，观感"31帧是末帧"）。

func _sample(a: Animation, ti: int, t: float) -> Quaternion:
	var kc := a.track_get_key_count(ti)
	if kc == 0:
		return Quaternion.IDENTITY
	if t <= a.track_get_key_time(ti, 0):
		return a.track_get_key_value(ti, 0)
	for k in range(kc - 1):
		var t0: float = a.track_get_key_time(ti, k)
		var t1: float = a.track_get_key_time(ti, k + 1)
		if t >= t0 and t <= t1:
			var d := t1 - t0
			if d < 0.0001:
				return a.track_get_key_value(ti, k)
			var w := (t - t0) / d
			var q0: Quaternion = a.track_get_key_value(ti, k)
			var q1: Quaternion = a.track_get_key_value(ti, k + 1)
			return q0.slerp(q1, w)
	return a.track_get_key_value(ti, kc - 1)

func _init() -> void:
	var lib: AnimationLibrary = load("res://resources/mixamo_lib.tres") as AnimationLibrary
	var toss: Animation = lib.get_animation("Toss Grenade") as Animation
	var f31 := 31.0 / 30.0
	var f37 := 37.0 / 30.0
	var f38 := 38.0 / 30.0
	var bones := ["RightArm", "RightForeArm", "RightHand",
			"LeftArm", "LeftForeArm", "LeftHand", "Spine1", "Spine2"]
	for b in bones:
		var q31 := Quaternion.IDENTITY
		var q37 := Quaternion.IDENTITY
		var q38 := Quaternion.IDENTITY
		var found := false
		for ti in toss.get_track_count():
			if toss.track_get_type(ti) != Animation.TYPE_ROTATION_3D:
				continue
			var p := String(toss.track_get_path(ti))
			if not p.contains(b):
				continue
			q31 = _sample(toss, ti, f31)
			q37 = _sample(toss, ti, f37)
			q38 = _sample(toss, ti, f38)
			found = true
			break
		if not found:
			continue
		print("%-16s 31→37帧 角差=%6.2f°   37→38帧 角差=%6.2f°   31→38帧=%6.2f°" % [
			b, rad_to_deg(q31.angle_to(q37)), rad_to_deg(q37.angle_to(q38)),
			rad_to_deg(q31.angle_to(q38))])
	quit(0)
