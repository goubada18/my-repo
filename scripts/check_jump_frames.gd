extends SceneTree

func _init():
	var lib = load("res://resources/mixamo_lib.tres") as AnimationLibrary
	if not lib:
		print("ERROR: 无法加载 AnimationLibrary")
		quit(1)
		return
	
	# 检查 Jump Forward 和 Rifle Run 的首尾帧数据
	var check_anims = ["Jump Forward", "Jump Up", "Jump Down", "Rifle Run", "Walking"]
	
	for anim_name in check_anims:
		if not lib.has_animation(anim_name):
			print(anim_name + ": 不存在!")
			continue
		var anim = lib.get_animation(anim_name)
		print("\n===== " + anim_name + " (length=" + str(anim.length) + ") =====")
		
		# 检查所有轨道的首尾帧
		var pos_tracks = 0
		var rot_tracks = 0
		var first_last_diff = false
		
		for i in range(anim.get_track_count()):
			var track_type = anim.track_get_type(i)
			var path_str = str(anim.track_get_path(i))
			
			if track_type == Animation.TYPE_POSITION_3D:
				pos_tracks += 1
			elif track_type == Animation.TYPE_ROTATION_3D:
				rot_tracks += 1
				
				# 检查首尾帧差异（仅关键骨骼）
				if path_str.find("Hips") >= 0 or path_str.find("LeftUpLeg") >= 0 or path_str.find("RightUpLeg") >= 0:
					var key_count = anim.track_get_key_count(i)
					if key_count >= 2:
						var first_val = anim.track_get_key_value(i, 0)
						var last_val = anim.track_get_key_value(i, key_count - 1)
						# 计算四元数差异
						var diff = abs(first_val.x - last_val.x) + abs(first_val.y - last_val.y) + abs(first_val.z - last_val.z) + abs(first_val.w - last_val.w)
						if diff > 0.01:
							if not first_last_diff:
								print("  [首尾帧差异] " + path_str + ": diff=" + str(snapped(diff, 0.001)))
								print("    首帧: " + str(first_val))
								print("    末帧: " + str(last_val))
							first_last_diff = true
		
		if not first_last_diff:
			print("  [首尾帧匹配] 所有旋转轨道首尾帧一致")
		print("  位置轨道=" + str(pos_tracks) + " 旋转轨道=" + str(rot_tracks))
		
		# 对于Rifle Run，打印Hips的首中尾帧来分析步频
		if anim_name == "Rifle Run":
			for i in range(anim.get_track_count()):
				var path_str = str(anim.track_get_path(i))
				if path_str.find("Hips") >= 0 and anim.track_get_type(i) == Animation.TYPE_ROTATION_3D:
					var key_count = anim.track_get_key_count(i)
					print("\n  --- Rifle Run Hips旋转关键帧分析 ---")
					print("  关键帧数: " + str(key_count))
					# 打印所有关键帧的Y旋转分量（判断步频）
					for j in range(key_count):
						var time = anim.track_get_key_time(i, j)
						var val = anim.track_get_key_value(i, j)
						print("    t=" + str(snapped(time, 0.001)) + " y=" + str(snapped(val.y, 0.001)))
					break
	
	quit(0)
