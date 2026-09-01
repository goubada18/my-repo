extends SceneTree
## Detect hard-truncated tails (last 20ms peak vs global peak) and apply linear
## fade-out to offenders. Only rewrites files whose tail is audibly cut.
const CHECK := [
	"res://audio/v_deagle_fire.dat", "res://audio/v_deagle_reload.dat", "res://audio/v_deagle_draw.dat",
	"res://audio/nepal_slash1.dat", "res://audio/nepal_slash2.dat", "res://audio/nepal_draw.dat",
	"res://audio/gaobao_pull.dat",
]
func _peaks(data: PackedByteArray, rate: int, stereo: bool, seg_ms: int) -> Array:
	var bpf: int = 4 if stereo else 2
	var frames: int = data.size() / bpf
	var seg_s: int = rate * seg_ms / 1000
	var out: Array = []
	var f: int = 0
	while f < frames:
		var seg_n: int = mini(seg_s, frames - f)
		var peak: int = 0
		for k in range(0, seg_n):
			var base: int = (f + k) * bpf
			peak = maxi(peak, absi(data.decode_s16(base)))
			if stereo:
				peak = maxi(peak, absi(data.decode_s16(base + 2)))
		out.append(peak)
		f += seg_n
	return out
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
	for path in CHECK:
		var wav: AudioStreamWAV = AudioWavLoader.load_wav(path)
		if wav == null:
			print("%s: LOAD FAIL" % path.get_file())
			continue
		var data: PackedByteArray = wav.data
		var rate: int = wav.mix_rate
		var stereo: bool = wav.stereo
		var bpf: int = 4 if stereo else 2
		var peaks: Array = _peaks(data, rate, stereo, 20)
		var gmax: int = 0
		for p in peaks: gmax = maxi(gmax, p)
		var tail: int = peaks[-1]
		var tail_pct: float = tail / 327.68
		var trunc_ratio: float = float(tail) / float(gmax) if gmax > 0 else 0.0
		# 截断判定：最后 20ms 峰值 > 全曲峰值 3% 且 > 1.5% 绝对幅度 → 尾音被硬切
		if trunc_ratio > 0.03 and tail_pct > 1.5:
			# 线性淡出：从最后 0.09s 起把幅度降为 0
			var bpf2: int = bpf
			var frames: int = data.size() / bpf2
			var fade_frames: int = int(0.09 * rate)
			var start_f: int = maxi(0, frames - fade_frames)
			for fi in range(start_f, frames):
				var g: float = 1.0 - float(fi - start_f) / float(frames - start_f)
				var base: int = fi * bpf2
				data.encode_s16(base, int(data.decode_s16(base) * g))
				if stereo:
					data.encode_s16(base + 2, int(data.decode_s16(base + 2) * g))
			wav.data = data
			_write_wav(wav, path)
			print("%s: TRUNC %.1f%% -> faded out (0.09s)" % [path.get_file(), trunc_ratio * 100])
		else:
			print("%s: tail ok (%.1f%% of peak)" % [path.get_file(), trunc_ratio * 100])
	quit(0)
