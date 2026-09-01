extends SceneTree
## Analyze walk.wav: find footstep peaks with adaptive threshold.
func _init():
	var wav: AudioStreamWAV = AudioWavLoader.load_wav("C:/Users/93343/Desktop/新建文件夹/走路声.wav")
	if wav == null:
		printerr("FAIL load")
		quit(1)
		return
	var data: PackedByteArray = wav.data
	var n: int = data.size() / 2
	var rate: int = wav.mix_rate
	print("len=%.3fs rate=%d" % [wav.get_length(), rate])
	var seg_s: int = rate / 50   # 20ms
	var peaks: Array = []
	var i: int = 0
	while i < n:
		var seg_n: int = mini(seg_s, n - i)
		var peak: int = 0
		for k in range(0, seg_n):
			var s: int = data.decode_s16((i + k) * 2)
			peak = maxi(peak, absi(s))
		peaks.append(peak)
		i += seg_n
	var sum: int = 0
	for p in peaks: sum += p
	var avg: float = float(sum) / peaks.size()
	var maxp: int = 0
	for p in peaks: maxp = maxi(maxp, p)
	print("seg avg=%.0f max=%d  (%.2f%%)" % [avg, maxp, maxp / 327.68])
	# 每 20ms 段打印，标出显著波峰（>avg*5）
	var thresh: float = avg * 5.0
	var bursts: Array = []
	for idx in range(peaks.size()):
		if peaks[idx] > thresh:
			bursts.append(idx)
	# 合并相邻（gap<=2 段=40ms 内算同一步）
	var steps: Array = []
	for b in bursts:
		if steps.is_empty() or b - steps[-1][-1] > 2:
			steps.append([b])
		else:
			steps[-1].append(b)
	for s in steps:
		var t0: float = float(s[0]) * 20.0 / 1000.0
		var t1: float = float(s[-1] + 1) * 20.0 / 1000.0
		var pk: int = 0
		for seg in s: pk = maxi(pk, peaks[seg])
		print("step: %.3f~%.3fs  peak=%d (%.1f%%)" % [t0, t1, pk, pk / 327.68])
	quit(0)
