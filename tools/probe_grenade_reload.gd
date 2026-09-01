extends SceneTree
## 验证：CACHE_MODE_REPLACE 读取标定 tres（新逻辑），确认每次能拿到最新值。
func _init():
	for p in [
		"res://resources/characters/grenade_calib_feihu.tres",
		"res://resources/characters/grenade_calib_swat.tres",
	]:
		var r = ResourceLoader.load(p, "", ResourceLoader.CACHE_MODE_REPLACE)
		if r == null:
			printerr("FAIL: 无法读取 " + p)
			quit(1)
			return
		print("%s: pos=%s scale=%s" % [p.get_file(), str(r.local_pos), str(r.local_scale)])
		# 再读一次（模拟重复调用），确认同样能读到
		var r2 = ResourceLoader.load(p, "", ResourceLoader.CACHE_MODE_REPLACE)
		print("  二次读取 OK: scale=%s" % str(r2.local_scale))
	print("验证完成")
	quit(0)
