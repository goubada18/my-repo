extends SceneTree
## Slice first peak (0.03~0.14s) of nepal_slash2.dat into nepal_slash2_peak.dat.
func _write_wav(wav: AudioStreamWAV, out_path: String) -> void:
	var bits: int = 8 if wav.format == AudioStreamWAV.FORMAT_8_BITS else 16
	var ch: int = 2 if wav.stereo else 1
	var rate: int = wav.mix_rate
	var data: PackedByteArray = wav.data
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(36 + data.size())
	f.store_buffer("WAVE".to_ascii_buffer())
	f.store_buffer("fmt ".to_ascii_buffer())
	f.store_32(16)
	f.store_16(1)
	f.store_16(ch)
	f.store_32(rate)
	f.store_32(rate * ch * bits / 8)
	f.store_16(ch * bits / 8)
	f.store_16(bits)
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(data.size())
	f.store_buffer(data)
	f.close()
func _init():
	var wav: AudioStreamWAV = AudioWavLoader.load_wav("res://audio/nepal_slash2.dat")
	if wav == null:
		printerr("FAIL")
		quit(1)
		return
	var rate: int = wav.mix_rate
	var bpf: int = 4 if wav.stereo else 2
	var data: PackedByteArray = wav.data
	var s_f: int = int(0.03 * rate)
	var e_f: int = int(0.14 * rate)
	wav.data = data.slice(s_f * bpf, e_f * bpf)
	_write_wav(wav, "res://audio/nepal_slash2_peak.dat")
	var chk: AudioStreamWAV = AudioWavLoader.load_wav("res://audio/nepal_slash2_peak.dat")
	print("slash2_peak: %.3fs -> %.3fs (first peak 0.03~0.14s)" % [wav.get_length(), chk.get_length()])
	quit(0)
