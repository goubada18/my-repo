extends "res://fp_viewmodel/fp_action_preview.gd"
const AudioWavLoader = preload("res://scripts/audio_wav_loader.gd")
# ============================================================================
# fp_gameplay.gd — 第一人称玩法整合（单场景 F6 全测）
# ----------------------------------------------------------------------------
# 继承 fp_action_preview.gd（复用：模型摆放/相机位/镜像/呼吸/防崩钳制）。
# 动画分配（用户选定）：
#   draw   -> V 键 / 初始进入：切换到第一人称（出枪）
#   idle   -> 平时循环（带角色呼吸叠加）
#   shoot2 -> 鼠标左键：开火
#   cidao1 -> 鼠标右键：刺刀
#   reload -> R 键：换弹
# 音效（取自 AK贴图/weapons，已复制到 res://audio/）：
#   开火=ak47hql_shoot2.WAV；换弹=AK47-HQL_RELOAD.WAV；刺刀=AK47-HQL_KNIFE-ATTACK.WAV；
#   出枪=AK47-HQL_BLOWBACK.WAV（枪机声）
# 非循环动作播完自动回到 idle。
# ============================================================================

const ANIM_IDLE := "idle"
const ANIM_DRAW := "draw"
const ANIM_RELOAD := "reload"
const ANIM_SHOOT := "shoot2"
const ANIM_BAYONET := "cidao1"
# 动作<->待机 交叉淡入淡出时长（秒）。回位尾巴让动作末帧=idle 首帧后，这里只需极短兜底。
const BLEND_TIME := 0.05
# 长按左键自动连发间隔（秒/发）：0.15 ≈ 400 发/分。
# 每次开火都硬切重播动画开头（后坐+枪口火光循环），松开即停。
const AUTO_FIRE_INTERVAL := 0.15
# 动作末帧"回位"过渡时长（秒）：在动作 dup 动画末尾追加一段"回到 idle 首帧姿态"的关键帧，
# 让后坐/挥砍造成的姿态偏移在动画内自然回位，播完时恰好=idle 首帧 => 切换零跳变。
# 只对需要回位的动作生效（当前 shoot；reload/cidao1 播完时本身已回到持枪位则不需要）。
const RECOVERY_DUR := 0.18
const RECOVERY_ANIMS := ["shoot2"]

# 音效：CS:GO 原版 BWF/特殊 WAV 会让 Godot 4.7 的 WAV 导入器崩溃（headless 实测），
# 故全部转成标准 PCM 后改名 .dat 放入 res://audio/，运行时手动解析 RIFF 构建
# AudioStreamWAV —— 完全绕开资源导入器，任何环境都稳定。
const SFX_PATH_SHOOT := "res://audio/ak47hql_shoot2.dat"
const SFX_PATH_RELOAD := "res://audio/AK47-HQL_RELOAD.dat"
const SFX_PATH_BAYONET := "res://audio/AK47-HQL_KNIFE-ATTACK.dat"
const SFX_PATH_DRAW := "res://audio/AK47-HQL_BLOWBACK.dat"

var _sfx: AudioStreamPlayer
var _sfx_shoot: AudioStreamWAV
var _sfx_reload: AudioStreamWAV
var _sfx_bayonet: AudioStreamWAV
var _sfx_draw: AudioStreamWAV
# 自动连发状态：按住左键时 _fire_hold=true，_process 按射速倒计时补发
var _fire_hold := false
var _fire_timer := 0.0

func _load_sfx_wav(res_path: String) -> AudioStreamWAV:
	return AudioWavLoader.load_wav(res_path)

func _ready() -> void:
	# 父类 _ready 会读 loop_action 决定 dup 的 loop_mode；运行时动作必须单次
	# （初始 draw 播完 -> finished -> 回 idle），否则 draw 会一直循环。
	# 编辑器里父类用 is_editor_hint() 强制循环预览，不受此影响。
	loop_action = false
	super._ready()
	_sfx = AudioStreamPlayer.new()
	add_child(_sfx)
	_sfx_shoot = _load_sfx_wav(SFX_PATH_SHOOT)
	_sfx_reload = _load_sfx_wav(SFX_PATH_RELOAD)
	_sfx_bayonet = _load_sfx_wav(SFX_PATH_BAYONET)
	_sfx_draw = _load_sfx_wav(SFX_PATH_DRAW)
	var ap := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap != null and not ap.animation_finished.is_connected(_on_anim_finished):
		ap.animation_finished.connect(_on_anim_finished)
	# 编辑器里不响应游戏输入（避免误触）；F6 运行时才接收
	set_process_unhandled_input(not Engine.is_editor_hint())
	# 运行时需要 _process 跑自动连发（编辑器里父类已自行 set_process）
	set_process(true)

func _on_action_duplicated(anim: Animation, n: String) -> void:
	# 轨道层面：给动作 dup 动画末尾追加"回位尾巴"，末帧姿态对齐 idle 首帧，消除切换跳变。
	if not n in RECOVERY_ANIMS:
		return
	var ap := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var skel := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if ap == null or skel == null or not ap.has_animation(ANIM_IDLE):
		return
	# target 优先取"带呼吸的 idle_preview"（若已生成过），否则源 idle——保证与真实切换目标一致
	var idle: Animation = ap.get_animation("idle_preview") if ap.has_animation("idle_preview") else ap.get_animation(ANIM_IDLE)
	var body_end: float = anim.length  # 动作主体结束（尾巴接在其后）
	var tail_time := body_end + RECOVERY_DUR
	for t in anim.get_track_count():
		var sp := str(anim.track_get_path(t))
		var kc: int = anim.track_get_key_count(t)
		if kc == 0:
			continue
		# 目标值 = idle 首帧该骨骼该轨道的值（idle key0）；idle 无此轨道则用 rest 值
		var target: Variant
		var idle_t := -1
		for it in idle.get_track_count():
			if str(idle.track_get_path(it)) == sp and idle.track_get_type(it) == anim.track_get_type(t):
				idle_t = it
				break
		if idle_t >= 0:
			target = idle.track_get_key_value(idle_t, 0)
		else:
			var bone_name := sp.substr(sp.rfind(":") + 1)
			var bi := skel.find_bone(bone_name)
			if bi < 0:
				continue
			var rest := skel.get_bone_rest(bi)
			match anim.track_get_type(t):
				Animation.TYPE_POSITION_3D:
					target = rest.origin
				Animation.TYPE_ROTATION_3D:
					target = rest.basis.get_rotation_quaternion()
				Animation.TYPE_SCALE_3D:
					target = rest.basis.get_scale()
				_:
					continue
		# 主体期间该骨骼的最后关键帧保持原值到 body_end（k=1 轨道在 t=0 也要平移到主体末尾，
		# 否则回位会污染动作主体），然后在 body_end..tail_time 过渡到 idle 首帧姿态。
		var last_time: float = anim.track_get_key_time(t, kc - 1)
		if last_time < body_end - 0.001:
			anim.track_set_key_time(t, kc - 1, body_end)
		anim.track_insert_key(t, tail_time, target)
		anim.track_set_interpolation_type(t, Animation.INTERPOLATION_LINEAR)
	# 关键：Animation.length 是显式属性，插入超长 key 不会自动延长，必须手动更新，
	# 否则动画在旧长度处截断，尾巴关键帧不会被播放。
	anim.length = tail_time

func _play_named(n: String, hard: bool = false) -> void:
	# 统一入口。hard=true（连发/动作重触发）时 blend=0 硬切：立即打断上一段动画，
	# 彻底清除上次开火残余（枪火骨骼回到 t=0 重新展开、动作从 0 重播），连发响应干净利落。
	# 动画资源首次创建后复用（不每次 remove/add 重建，避免连发卡顿）。
	action = n
	var ap := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap == null:
		return
	var local_name := n + "_preview"
	if ap.has_animation(local_name):
		var anim: Animation = ap.get_animation(local_name)
		anim.loop_mode = 1 if n == ANIM_IDLE else 0
		if hard:
			# 关键：Godot 4.7 对"正在播放的同一动画"调用 play() 不会重启（继续播放），
			# 导致连发时动画只按自己的周期播（固定频率）、跟不上枪声节奏。
			# 先 stop() 再 play() 才能真正从头重播，每次点击/每发连发都完整重置。
			ap.stop()
			ap.play(local_name, 0.0)
		else:
			ap.play(local_name, BLEND_TIME)
	else:
		# 首次：走父类 _play_action 创建 dup（含呼吸/回位尾巴）并播放
		_play_action()

func _play_sfx(stream: AudioStream) -> void:
	if _sfx == null or stream == null:
		return
	_sfx.stream = stream
	_sfx.play()  # 每次 play() 都从头重播，自然截断上一次的枪声残余

func _do_shoot() -> void:
	_play_named(ANIM_SHOOT, true)
	_play_sfx(_sfx_shoot)

func _do_bayonet() -> void:
	_play_named(ANIM_BAYONET, true)
	_play_sfx(_sfx_bayonet)

func _do_reload() -> void:
	_play_named(ANIM_RELOAD, true)
	_play_sfx(_sfx_reload)

func _do_draw() -> void:
	_play_named(ANIM_DRAW, true)
	_play_sfx(_sfx_draw)

func _on_anim_finished(anim_name: StringName) -> void:
	# 非循环动作播完回到 idle（idle 为循环，不会触发 finished）
	var nm := String(anim_name)
	if nm.ends_with("_preview"):
		nm = nm.trim_suffix("_preview")
	if nm == ANIM_DRAW or nm == ANIM_RELOAD or nm == ANIM_SHOOT or nm == ANIM_BAYONET:
		_play_named(ANIM_IDLE)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		# 注意：echo 属性只有 InputEventKey 有，鼠标按钮事件没有 => 不能访问
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				# 单击：立即开火（硬切清残余），并进入"按住连发"状态，倒计时自动补发
				_do_shoot()
				_fire_hold = true
				_fire_timer = AUTO_FIRE_INTERVAL
			else:
				_fire_hold = false  # 松开：停止自动连发，当前这发自然播完回 idle
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			_do_bayonet()
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo:
			if k.keycode == KEY_R:
				_do_reload()
			elif k.keycode == KEY_V:
				_do_draw()

func _process(delta: float) -> void:
	# 编辑器：保留父类的相机拖拽轮询
	if Engine.is_editor_hint():
		super._process(delta)
		return
	# 运行时：按住左键自动连发（扫射）。每 AUTO_FIRE_INTERVAL 秒一发，
	# 每次 _do_shoot 硬切重播动画（枪火/后坐/枪声全部重新触发，无残余）。
	if _fire_hold:
		_fire_timer -= delta
		if _fire_timer <= 0.0:
			_fire_timer = AUTO_FIRE_INTERVAL
			_do_shoot()
