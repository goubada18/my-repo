extends Node
## 脚步声系统：波峰切片 + 两腿交叉同步（用户 v2 设计）。
## 原理：
## 1. 走路录音的每个波峰 = 一次踩踏声（footstep_walk.dat 含 5 个均匀波峰），
##    运行时按波峰切成"单步"片段，触发放播时轮换。
## 2. 播放点 = 【两腿交叉时刻】：左右脚骨架空间 Y 反相（相位差 π），
##    每半个步态周期两脚 Y 相等一次（交叉）= 一步。检测两脚 Y 差值的
##    符号翻转（过零）即播放——步频自动跟随走/跑/蹲动画，无需标定。
## ⚠️ 用骨架空间 Y（get_bone_global_pose 原值，不乘 global_transform）：
## 世界 Y 含角色整体位移（跳跃/坠落）会污染交叉检测。

const AudioWavLoader = preload("res://scripts/audio_wav_loader.gd")
const WALK_SFX := "res://audio/footstep_walk.dat"
const FOOT_BONES := ["mixamorig_LeftFoot", "mixamorig_RightFoot"]
const CLIP_HALF := 0.15        # 单步片段半长（秒）：波峰 ±0.15s
const DEBOUNCE := 0.18         # 两次播放最小间隔（秒）——交叉每步一次，防抖过滤噪声过零
const MIN_PEAK_RATIO := 5.0    # 波峰阈值 = 20ms 段均值 × 该倍数
const VOLUME_DB := 6.0         # 录音峰值仅 5%，适当增益

var _skel: Skeleton3D = null
var _clips: Array = []         # AudioStreamWAV 单步切片（按波峰顺序）
var _clip_idx: int = 0         # 轮换索引
var _player: AudioStreamPlayer = null
var _foot_idx: Array = []      # [左脚 idx, 右脚 idx]（-1=缺失）
var _diff_prev: float = INF    # 上一帧两脚 Y 差（left - right）
var _last_play_ms: int = 0

func setup(skel: Skeleton3D) -> void:
	_skel = skel
	_foot_idx = []
	_diff_prev = INF
	_last_play_ms = 0
	if _skel == null:
		return
	for bn in FOOT_BONES:
		_foot_idx.append(_skel.find_bone(bn))
	_build_clips()
	if _player == null:
		_player = AudioStreamPlayer.new()
		_player.volume_db = VOLUME_DB
		add_child(_player)

## 每帧驱动（player PRIORITY=10 时序内调用）。
## moving：水平移动中且在地面（player 判定传入）。
## 两腿交叉检测：diff = leftY - rightY 每半个步态周期过零一次（两脚相遇），
## 过零（符号翻转）即播放一个单步切片。防抖过滤噪声。
func update(_delta: float, moving: bool) -> void:
	if _skel == null or _clips.is_empty() or _player == null:
		return
	if _foot_idx.size() < 2 or _foot_idx[0] < 0 or _foot_idx[1] < 0:
		return
	var yl: float = _skel.get_bone_global_pose(_foot_idx[0]).origin.y
	var yr: float = _skel.get_bone_global_pose(_foot_idx[1]).origin.y
	var diff: float = yl - yr
	if _diff_prev != INF:
		# 过零（符号翻转）：正→负 或 负→正，都算两腿相遇一次
		var crossed: bool = (diff > 0.0 and _diff_prev <= 0.0) or (diff < 0.0 and _diff_prev >= 0.0)
		if crossed and moving:
			var now := Time.get_ticks_msec()
			if now - _last_play_ms >= int(DEBOUNCE * 1000.0):
				_last_play_ms = now
				_play_next_clip()
	_diff_prev = diff

func _play_next_clip() -> void:
	if _clips.is_empty() or _player == null:
		return
	# 【随机播放】每次从切片里随机选（避免顺序轮换的循环感——用户要求"随机"）。
	# 若随机到与上一次相同则顺移一格，减少连续重复。
	var next: int = randi_range(0, _clips.size() - 1)
	if _clips.size() > 1 and next == _clip_idx:
		next = (next + 1) % _clips.size()
	_player.stream = _clips[next]
	_player.play()
	_clip_idx = next

## 分析走路声波峰 → 切单步片段（运行时一次）
func _build_clips() -> void:
	_clips = []
	var src := AudioWavLoader.load_wav(WALK_SFX)
	if src == null:
		push_warning("FootstepSystem: 无法加载 " + WALK_SFX)
		return
	var data: PackedByteArray = src.data
	var rate: int = src.mix_rate
	var stereo: bool = src.stereo
	var bpf: int = 4 if stereo else 2     # 每帧字节数（16bit × 通道）
	var frames: int = data.size() / bpf
	# 20ms 段峰值（|L|,|R| 取大）
	var seg_s: int = rate / 50
	var peaks: Array = []
	var f: int = 0
	while f < frames:
		var seg_n: int = mini(seg_s, frames - f)
		var peak: int = 0
		for k in range(0, seg_n):
			var base: int = (f + k) * bpf
			peak = maxi(peak, absi(data.decode_s16(base)))
			if stereo:
				peak = maxi(peak, absi(data.decode_s16(base + 2)))
		peaks.append(peak)
		f += seg_n
	var sum: int = 0
	for p in peaks: sum += p
	var thresh: float = (float(sum) / peaks.size()) * MIN_PEAK_RATIO
	# 波峰段合并（相邻 40ms 内算同一步）→ 步中心时间
	var step_times: Array = []
	var burst: Array = []
	for idx in range(peaks.size()):
		if peaks[idx] > thresh:
			if burst.is_empty() or idx - burst[-1] <= 2:
				burst.append(idx)
			else:
				step_times.append(float(burst[0] + burst[-1]) * 0.5 * 20.0 / 1000.0)
				burst = [idx]
	if not burst.is_empty():
		step_times.append(float(burst[0] + burst[-1]) * 0.5 * 20.0 / 1000.0)
	if step_times.is_empty():
		push_warning("FootstepSystem: 未检测到脚步波峰")
		return
	# 每个波峰 ±CLIP_HALF 切单步片段（边界裁剪到录音范围）
	for t in step_times:
		var s_f: int = maxi(0, int((t - CLIP_HALF) * rate))
		var e_f: int = mini(frames, int((t + CLIP_HALF) * rate))
		if e_f - s_f < rate / 20:   # 至少 50ms
			continue
		var clip := AudioStreamWAV.new()
		clip.format = src.format
		clip.mix_rate = src.mix_rate
		clip.stereo = src.stereo
		clip.data = data.slice(s_f * bpf, e_f * bpf)
		_clips.append(clip)
