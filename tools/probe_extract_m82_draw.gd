extends SceneTree
## Extract M82 draw sfx (m82a1_draw.dat) as a standalone WAV file.
func _write_wav(wav: AudioStreamWAV, out_path: String) -> bool:
	if wav == null:
		return false
	var bits: int = 8 if wav.format == AudioStreamWAV.FORMAT_8_BITS else 16
	var ch: int = 2 if wav.stereo else 1
	var rate: int = wav.mix_rate
	var data: PackedByteArray = wav.data
	var byte_rate: int = rate * ch * bits / 8
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(36 + data.size())
	f.store_buffer("WAVE".to_ascii_buffer())
	f.store_buffer("fmt ".to_ascii_buffer())
	f.store_32(16)
	f.store_16(1)
	f.store_16(ch)
	f.store_32(rate)
	f.store_32(byte_rate)
	f.store_16(ch * bits / 8)
	f.store_16(bits)
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(data.size())
	f.store_buffer(data)
	f.close()
	return true

func _init():
	var wav: AudioStreamWAV = AudioWavLoader.load_wav("res://audio/m82a1_draw.dat")
	if wav == null:
		printerr("FAIL: load m82a1_draw.dat")
		quit(1)
		return
	var out_dir := "C:/Users/93343/Desktop/demo/output"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var out_wav := out_dir + "/m82a1_draw.wav"
	var ok := _write_wav(wav, out_wav)
	print("format=%d stereo=%s rate=%d bits=%d len=%.3f s" % [
		wav.format, str(wav.stereo), wav.mix_rate,
		8 if wav.format == AudioStreamWAV.FORMAT_8_BITS else 16, wav.get_length()])
	print("wav -> %s : %s" % [out_wav, "OK" if ok else "FAIL"])
	# 同时复制原始 .dat 方便对照
	var src := FileAccess.open("res://audio/m82a1_draw.dat", FileAccess.READ)
	if src != null:
		var out_dat := out_dir + "/m82a1_draw.dat"
		var dst := FileAccess.open(out_dat, FileAccess.WRITE)
		if dst != null:
			dst.store_buffer(src.get_buffer(src.get_length()))
			dst.close()
			print("dat -> %s : OK" % out_dat)
		src.close()
	quit(0)
