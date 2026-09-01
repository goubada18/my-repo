extends SceneTree
## Generic WAV tail analyzer: per-10ms peak for the last 0.3s + envelope shape.
func _init():
	var args := OS.get_cmdline_user_args()
	var path: String = args[0] if args.size() > 0 else "res://audio/v_deagle_fire.dat"
	var wav: AudioStreamWAV = AudioWavLoader.load_wav(path)
	if wav == null:
		printerr("FAIL load " + path)
		quit(1)
		return
	var data: PackedByteArray = wav.data
	var rate: int = wav.mix_rate
	var stereo: bool = wav.stereo
	var bpf: int = 4 if stereo else 2
	var frames: int = data.size() / bpf
	print("len=%.3fs rate=%d stereo=%s" % [wav.get_length(), rate, str(stereo)])
	# 每 20ms 段峰值（全曲）
	var seg_s: int = rate / 50
	var f: int = 0
	var idx: int = 0
	var peaks: Array = []
	var times: Array = []
	while f < frames:
		var seg_n: int = mini(seg_s, frames - f)
		var peak: int = 0
		for k in range(0, seg_n):
			var base: int = (f + k) * bpf
			peak = maxi(peak, absi(data.decode_s16(base)))
			if stereo:
				peak = maxi(peak, absi(data.decode_s16(base + 2)))
		peaks.append(peak)
		times.append(float(idx) * 20.0 / 1000.0)
		f += seg_n
		idx += 1
	# 打印幅度 >0.5% 的最后位置之后的分布 + 尾部 0.3s
	var last_loud: int = 0
	for i in range(peaks.size()):
		if peaks[i] > 160:
			last_loud = i
	print("last segment >0.5%%: t=%.3fs (total %.3fs)" % [times[last_loud], times[-1] + 0.02])
	var tail_start: int = maxi(0, peaks.size() - 15)
	for i in range(tail_start, peaks.size()):
		print("t=%.3fs peak=%5d (%.2f%%)" % [times[i], peaks[i], peaks[i] / 327.68])
	quit(0)
