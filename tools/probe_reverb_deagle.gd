extends SceneTree
## Add multi-tap echo "reverb" tail to v_deagle_fire.dat (user request: 延长混响).
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
	var wav: AudioStreamWAV = AudioWavLoader.load_wav("res://audio/v_deagle_fire.dat")
	if wav == null:
		printerr("FAIL")
		quit(1)
		return
	var rate: int = wav.mix_rate
	var stereo: bool = wav.stereo
	var bpf: int = 4 if stereo else 2
	var old: PackedByteArray = wav.data
	var old_frames: int = old.size() / bpf
	var tail_s: float = 0.35
	var new_frames: int = old_frames + int(tail_s * rate)
	var new_data := PackedByteArray()
	new_data.resize(new_frames * bpf)
	# 多重回声：延迟/增益表（模拟房间混响尾）
	var delays := [0.055, 0.097, 0.143, 0.191, 0.247, 0.311]
	var gains := [0.42, 0.34, 0.27, 0.21, 0.15, 0.10]
	for fi in range(new_frames):
		var acc_l: int = 0
		var acc_r: int = 0
		for t in range(delays.size()):
			var src_f: int = fi - int(delays[t] * rate)
			if src_f < 0 or src_f >= old_frames:
				continue
			var base: int = src_f * bpf
			var g: float = gains[t]
			# 主信号（首 tap 用 1.0 原声）+ 回声叠加
			var gl: float = (1.0 if t == 0 else g)
			acc_l += int(old.decode_s16(base) * gl)
			if stereo:
				acc_r += int(old.decode_s16(base + 2) * gl)
		if fi < old_frames:
			var base: int = fi * bpf
			acc_l += old.decode_s16(base)
			if stereo:
				acc_r += old.decode_s16(base + 2)
		acc_l = clampi(acc_l, -32767, 32767)
		var wbase: int = fi * bpf
		new_data.encode_s16(wbase, acc_l)
		if stereo:
			acc_r = clampi(acc_r, -32767, 32767)
			new_data.encode_s16(wbase + 2, acc_r)
	wav.data = new_data
	_write_wav(wav, "res://audio/v_deagle_fire.dat")
	var chk: AudioStreamWAV = AudioWavLoader.load_wav("res://audio/v_deagle_fire.dat")
	print("deagle fire: %.3fs -> %.3fs (echo tail added)" % [float(old_frames) / rate, chk.get_length()])
	quit(0)
