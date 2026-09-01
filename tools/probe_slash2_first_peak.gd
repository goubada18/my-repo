extends SceneTree
## Find first peak boundaries in nepal_slash2.dat (heavy slash sfx).
func _init():
	var wav: AudioStreamWAV = AudioWavLoader.load_wav("res://audio/nepal_slash2.dat")
	if wav == null:
		printerr("FAIL")
		quit(1)
		return
	var data: PackedByteArray = wav.data
	var rate: int = wav.mix_rate
	var stereo: bool = wav.stereo
	var bpf: int = 4 if stereo else 2
	var frames: int = data.size() / bpf
	print("len=%.3fs rate=%d stereo=%s frames=%d" % [wav.get_length(), rate, str(stereo), frames])
	# 每 10ms 段峰值，打印前 0.6s
	var seg_s: int = rate / 100
	var f: int = 0
	var idx: int = 0
	while f < frames and idx < 70:
		var seg_n: int = mini(seg_s, frames - f)
		var peak: int = 0
		for k in range(0, seg_n):
			var base: int = (f + k) * bpf
			peak = maxi(peak, absi(data.decode_s16(base)))
			if stereo:
				peak = maxi(peak, absi(data.decode_s16(base + 2)))
		var t: float = float(idx) * 10.0 / 1000.0
		if peak > 400:
			print("t=%.3f peak=%d (%.1f%%)" % [t, peak, peak / 327.68])
		f += seg_n
		idx += 1
	quit(0)
