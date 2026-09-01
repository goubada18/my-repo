extends SceneTree
## Analyze tail of AK47-HQL_BLOWBACK.dat to locate clipping/glitch region.
func _init():
	var wav: AudioStreamWAV = AudioWavLoader.load_wav("res://audio/AK47-HQL_BLOWBACK.dat")
	if wav == null:
		printerr("FAIL load")
		quit(1)
		return
	var data: PackedByteArray = wav.data
	var n: int = data.size() / 2   # 16-bit samples
	var rate: int = wav.mix_rate
	print("len=%.3fs  samples=%d  rate=%d  bits=%d" % [wav.get_length(), n, rate, 16])
	# 尾部最后 0.35s：每 10ms 一段，打印峰值幅度（归一化到 16bit 满幅 32768）
	var seg_ms: int = 10
	var seg_s: int = rate * seg_ms / 1000
	var start_s: int = maxi(0, n - int(rate * 0.35))
	var t0: float = float(start_s) / rate
	var i: int = start_s
	var idx: int = 0
	while i < n:
		var seg_n: int = mini(seg_s, n - i)
		var peak: int = 0
		for k in range(0, seg_n):
			var s: int = data.decode_s16((i + k) * 2)
			peak = maxi(peak, absi(s))
		print("t=%.3f~%.3fs  peak=%5d (%.2f%%)" % [t0 + idx * seg_ms / 1000.0, t0 + (idx + 1) * seg_ms / 1000.0, peak, peak / 327.68])
		i += seg_n
		idx += 1
	quit(0)
