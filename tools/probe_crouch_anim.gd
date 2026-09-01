extends SceneTree
## 检查蹲走各方向动画的 Spine/Head 旋转轨道（CROUCH_STRAFE_LEFT 是否异常）。

func _init() -> void:
	var lib: AnimationLibrary = load("res://resources/mixamo_lib.tres") as AnimationLibrary
	var names := {
		"CROUCH_FWD": "Walk Crouching Forward",
		"CROUCH_BCK": "Walk Crouching Backward",
		"CROUCH_L": "Crouch Walk Strafe Left",
		"CROUCH_R": "Crouch Walk Strafe Right",
	}
	var bones := ["Spine", "Spine1", "Spine2", "Neck", "Head"]
	for tag in names.keys():
		var a: Animation = lib.get_animation(names[tag]) as Animation
		if a == null:
			print("%-10s 无动画" % tag)
			continue
		var info := ""
		for b in bones:
			for ti in a.get_track_count():
				if a.track_get_type(ti) != Animation.TYPE_ROTATION_3D:
					continue
				if not String(a.track_get_path(ti)).contains(b):
					continue
				var kc := a.track_get_key_count(ti)
				var min_q := Quaternion.IDENTITY
				var max_ang := 0.0
				for k in range(kc):
					var q: Quaternion = a.track_get_key_value(ti, k)
					if k == 0:
						min_q = q
					else:
						max_ang = maxf(max_ang, rad_to_deg(min_q.angle_to(q)))
				info += "%s:%d帧/%.0f° " % [b, kc, max_ang]
				break
		print("%-10s %s" % [tag, info])
	quit(0)
