extends SceneTree
## Correct stereo-aware footstep peak analysis.
func _init():
	var wav: AudioStreamWAV = AudioWavLoader.load_wav("res://audio/footstep_walk.dat")
	if wav == null:
		printerr("FAIL load")
		quit(1)
		return
	var data: PackedByteArray = wav.data
	var rate: int = wav.mix_rate
	var stereo: bool = wav.stereo
	print("len=%.3fs rate=%d stereo=%s bytes=%d" % [wav.get_length(), rate, str(stereo), data.size()])
	# 帧数（每帧 = 1 采样，stereo 时含 L+R 两样本）
	var bytes_per_frame: int = 4 if stereo else 2
	var frames: int = data.size() / bytes_per_frame
	print("frames=%d  true_dur=%.3fs" % [frames, float(frames) / rate])
	# 每 20ms 段峰值（取 |L|,|R| 最大）
	var seg_s: int = rate / 50
	var peaks: Array = []
	var f: int = 0
	while f < frames:
		var seg_n: int = mini(seg_s, frames - f)
		var peak: int = 0
		for k in range(0, seg_n):
			var base: int = (f + k) * bytes_per_frame
			var l: int = data.decode_s16(base)
			peak = maxi(peak, absi(l))
			if stereo:
				var r: int = data.decode_s16(base + 2)
				peak = maxi(peak, absi(r))
		peaks.append(peak)
		f += seg_n
	var sum: int = 0
	for p in peaks: sum += p
	var avg: float = float(sum) / peaks.size()
	var thresh: float = avg * 5.0
	print("avg=%.0f thresh=%.0f" % [avg, thresh])
	var steps: Array = []
	for idx in range(peaks.size()):
		if peaks[idx] > thresh:
			if steps.is_empty() or idx - steps[-1][-1] > 2:
				steps.append([idx])
			else:
				steps[-1].append(idx)
	for s in steps:
		var t0: float = float(s[0]) * 20.0 / 1000.0
		var t1: float = float(s[-1] + 1) * 20.0 / 1000.0
		var pk: int = 0
		for seg in s: pk = maxi(pk, peaks[seg])
		print("step: %.3f~%.3fs peak=%d (%.1f%%)" % [t0, t1, pk, pk / 327.68])
	quit(0)
