extends SceneTree
## Read actual durations of M82/AK audio via project's AudioWavLoader.
func _init():
	var files := [
		"res://audio/m82a1_reload.dat",
		"res://audio/m82a1_shoot.dat",
		"res://audio/m82a1_draw.dat",
		"res://audio/m82a1_clipout.dat",
		"res://audio/m82a1_mzc.dat",
		"res://audio/AK47-HQL_RELOAD.dat",
		"res://audio/AK47-HQL_BLOWBACK.dat",
	]
	for f in files:
		var wav: AudioStreamWAV = AudioWavLoader.load_wav(f)
		if wav != null:
			print("%s: len=%.3f s  (%d samples @ %d Hz)" % [
				f.get_file(), wav.get_length(), wav.data.size(), wav.mix_rate])
		else:
			print("%s: LOAD FAIL" % f.get_file())
	quit(0)
