extends SceneTree
## Truncate AK47-HQL_BLOWBACK.dat at 0.520s to remove tail glitch spike (0.521~0.561s).
func _write_wav(wav: AudioStreamWAV, out_path: String) -> void:
	var bits: int = 8 if wav.format == AudioStreamWAV.FORMAT_8_BITS else 16
	var ch: int = 2 if wav.stereo else 1
	var rate: int = wav.mix_rate
	var data: PackedByteArray = wav.data
	var byte_rate: int = rate * ch * bits / 8
	var f := FileAccess.open(out_path, FileAccess.WRITE)
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

func _init():
	var wav: AudioStreamWAV = AudioWavLoader.load_wav("res://audio/AK47-HQL_BLOWBACK.dat")
	if wav == null:
		printerr("FAIL load")
		quit(1)
		return
	var rate: int = wav.mix_rate
	var keep_samples: int = int(0.520 * rate)
	var data: PackedByteArray = wav.data
	var new_data := data.slice(0, keep_samples * 2)
	wav.data = new_data
	_write_wav(wav, "res://audio/AK47-HQL_BLOWBACK.dat")
	var chk: AudioStreamWAV = AudioWavLoader.load_wav("res://audio/AK47-HQL_BLOWBACK.dat")
	print("orig=%.3fs  new=%.3fs  (truncated @0.520s, glitch 0.521-0.561s removed)" % [
		float(data.size()) / 2.0 / rate, chk.get_length() if chk else -1])
	quit(0)
