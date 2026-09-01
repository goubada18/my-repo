extends SceneTree
func _init():
	var def: Resource = load("res://resources/weapons/m82a1.tres")
	var bolt: String = def.get("bolt_sfx")
	var reload: String = def.get("reload_sfx")
	print("bolt_sfx=%s" % bolt)
	print("reload_sfx=%s" % reload)
	var ok1: bool = bolt == "res://audio/m82a1_bolt.dat"
	var ok2: bool = reload == "res://audio/m82a1_reload.dat"
	# 两个音效可加载
	var b: AudioStreamWAV = AudioWavLoader.load_wav(bolt)
	var r: AudioStreamWAV = AudioWavLoader.load_wav(reload)
	print("bolt load: %s (%.3fs)  reload load: %s (%.3fs)" % [str(b != null), b.get_length() if b else -1, str(r != null), r.get_length() if r else -1])
	# 换弹 pitch（新音效 2.350s vs 动画 2.305s）
	var pitch: float = clampf(r.get_length() / 2.305, 0.5, 2.0)
	print("reload pitch = %.3f (normal, no pitch-down)" % pitch)
	var ok3: bool = b != null and r != null and absf(pitch - 1.02) < 0.05
	print("=> %s" % ("ALL PASS" if (ok1 and ok2 and ok3) else "FAIL"))
	quit(0)
