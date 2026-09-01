extends SceneTree
func _init():
	for f in ["res://audio/m82a1_reload.dat", "res://audio/m82a1_bolt.dat", "res://audio/m82a1_scope.dat"]:
		var wav: AudioStreamWAV = AudioWavLoader.load_wav(f)
		if wav != null:
			print("%s: len=%.3f s" % [f.get_file(), wav.get_length()])
		else:
			print("%s: LOAD FAIL" % f.get_file())
	quit(0)
