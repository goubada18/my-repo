extends SceneTree
func _init():
	var wavs := [
		"res://audio/nepal_draw.dat", "res://audio/nepal_slash1.dat", "res://audio/nepal_slash2.dat",
		"res://audio/v_deagle_draw.dat", "res://audio/v_deagle_fire.dat", "res://audio/v_deagle_reload.dat",
		"res://audio/gaobao_pull.dat", "res://audio/footstep_walk.dat",
	]
	for f in wavs:
		var w: AudioStreamWAV = AudioWavLoader.load_wav(f)
		print("%-28s len=%.3f %s" % [f.get_file(), w.get_length() if w else -1, "OK" if w else "FAIL"])
	var mp3s := [
		"res://audio/gaobao_throw.mp3", "res://audio/gaobao_bounce.mp3",
		"res://audio/gaobao_explode.mp3", "res://audio/jump_land.mp3",
	]
	for f in mp3s:
		var m: AudioStreamMP3 = load(f)
		print("%-28s len=%.3f %s" % [f.get_file(), m.get_length() if m else -1, "OK" if m else "FAIL"])
	quit(0)
