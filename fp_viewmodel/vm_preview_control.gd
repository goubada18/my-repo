@tool
extends Node3D
# ============================================================================
# vm_preview_control.gd — 高爆手雷 FP 视图模型预览控制
# ----------------------------------------------------------------------------
# 编辑器内：保持静止 idle 第 0 帧（不循环播放），避免编辑器里不停播放动画。
# 运行时(F6)：
#   数字键动画映射（用户定义）：
#     1 = 投掷(Throw)   2 = 切换手雷(draw)   3 = 待机(idle)   4 = 拉环(plugin)
#   鼠标左键交互（手雷投掷手势）：
#     · 按下(点按)：播 拉环(4) → 自动接 待机(3)（拔销后持握，即 4+3 组合）
#     · 长按(按住不放)：拉环播到末帧后停在最后一帧（holding，销已拔出、手停在拉环姿势）
#     · 松开(长按后)：播 投掷(1)，投掷完回待机
#   说明：无需时间阈值——靠"拉环是否播完"区分点按/长按：
#     短按(松开关在拉环播完前) → 拉环播完转待机；
#     长按(按住到拉环播完) → 停末帧 holding，松开才投掷。
# ============================================================================

## 动画名（与 v_gaobao_viewmodel.gltf 的 clip 名一致）
const ANIM_IDLE := "idle"
const ANIM_DRAW := "draw"
const ANIM_THROW := "Throw"
const ANIM_PULL := "plugin"

## 数字键 → 动画名（用户定义）
const KEY_ANIM_MAP := {
	KEY_1: ANIM_THROW,
	KEY_2: ANIM_DRAW,
	KEY_3: ANIM_IDLE,
	KEY_4: ANIM_PULL,
}

enum Phase { IDLE, PULLING, HOLDING, THROWING }

var _ap: AnimationPlayer = null
var _clips: Array = []
var _phase: int = Phase.IDLE
var _mouse_held: bool = false

func _ready() -> void:
	_ap = _find_anim_player()
	if _ap == null:
		push_warning("[VM预览] 未找到 AnimationPlayer")
		return
	_clips = _ap.get_animation_list()
	if _clips.is_empty():
		push_warning("[VM预览] 动画列表为空")
		return
	if not _ap.animation_finished.is_connected(_on_anim_finished):
		_ap.animation_finished.connect(_on_anim_finished)
	if Engine.is_editor_hint():
		# 编辑器：仅定位到 idle 第 0 帧并静止显示，不循环播放。
		var id := _find_idle()
		if _ap.has_animation(id):
			_ap.current_animation = id
			_ap.seek(0.0, true)
		set_process(false)
	else:
		_phase = Phase.IDLE
		_mouse_held = false
		_play(ANIM_IDLE, true)
		print("[VM预览] 待机。数字键: 1投掷 2切换 3待机 4拉环 | 鼠标左键: 按下拉环→待机, 长按持握末帧, 松开投掷")

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	# 数字键切换动画（手动查看某个 clip）
	var kev := event as InputEventKey
	if kev != null and kev.pressed and not kev.echo:
		if KEY_ANIM_MAP.has(kev.keycode):
			_mouse_held = false
			_phase = Phase.IDLE
			_play(KEY_ANIM_MAP[kev.keycode], false)
			print("[VM预览] 播放: %s" % KEY_ANIM_MAP[kev.keycode])
			return
	# 鼠标左键：投掷手势
	var mev := event as InputEventMouseButton
	if mev != null and mev.button_index == MOUSE_BUTTON_LEFT:
		if mev.pressed:
			_on_mouse_down()
		else:
			_on_mouse_up()

# 左键按下：开始拉环（4）
func _on_mouse_down() -> void:
	_mouse_held = true
	_phase = Phase.PULLING
	_play(ANIM_PULL, false)
	print("[VM预览] 拉环(4)...")

# 左键松开
func _on_mouse_up() -> void:
	_mouse_held = false
	if _phase == Phase.HOLDING:
		# 长按后松开 → 投掷（1）
		_phase = Phase.THROWING
		_play(ANIM_THROW, false)
		print("[VM预览] 投掷(1)")

# 动画播完：推进状态机
func _on_anim_finished(anim_name: StringName) -> void:
	if Engine.is_editor_hint():
		return
	var n := String(anim_name)
	if n.ends_with("_preview"):
		n = n.trim_suffix("_preview")
	if n == ANIM_PULL:
		if _mouse_held:
			# 长按：拉环末帧保持（holding）
			_ap.pause()
			_phase = Phase.HOLDING
			print("[VM预览] holding 拉环末帧")
		else:
			# 点按已松开：接待机（4+3 组合完成）
			_phase = Phase.IDLE
			_play(ANIM_IDLE, true)
			print("[VM预览] 待机(3)")
	elif n == ANIM_THROW:
		_phase = Phase.IDLE
		_play(ANIM_IDLE, true)
		print("[VM预览] 待机(3)")

func _play(name: String, loop: bool) -> void:
	if _ap == null or not _ap.has_animation(name):
		return
	var a: Animation = _ap.get_animation(name)
	if a != null:
		a.loop_mode = 1 if loop else 0
	_ap.play(name)

func _find_idle() -> StringName:
	for c in _clips:
		if String(c).begins_with("idle"):
			return c
	return _clips[0]

func _find_anim_player() -> AnimationPlayer:
	return find_child("AnimationPlayer", true, false) as AnimationPlayer
