extends SceneTree
## Verify: alt sfx = slash2_peak (0.11s), heavy/bayonet sfx = slash2 (0.999s) unchanged.
func _init():
	var def: Resource = load("res://resources/weapons/nepal_kukri.tres")
	var alt: String = def.get("fp_alt_shoot_sfx")
	var bay: String = def.get("bayonet_sfx")
	print("alt_sfx=%s  bayonet_sfx=%s" % [alt, bay])
	var a: AudioStreamWAV = AudioWavLoader.load_wav(alt)
	var b: AudioStreamWAV = AudioWavLoader.load_wav(bay)
	var ok1: bool = alt == "res://audio/nepal_slash2_peak.dat" and a != null and a.get_length() < 0.2
	var ok2: bool = bay == "res://audio/nepal_slash2.dat" and b != null and absf(b.get_length() - 0.999) < 0.01
	print("alt len=%.3fs (expect ~0.11 第一个波峰)  bayonet len=%.3fs (expect 0.999 原重击)" % [a.get_length(), b.get_length()])
	print("=> %s" % ("ALL PASS" if (ok1 and ok2) else "FAIL"))
	quit(0)
