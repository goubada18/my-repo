@tool
extends Node
# 编辑器预览脚本：挂在 character.tscn 根节点。
# 作用：打开场景时把骨骼固定到"待机动画(Rifle Aiming Idle)第0帧"姿态，
# 这样 GripPoint_RH/LH 标注球在编辑器里看到的就是运行时默认姿态，
# 用户把球拖到"模型手心"保存 = 运行时精确对应（所见即所得）。
# 运行时(@tool 关闭)此脚本不干预任何逻辑。

func _ready():
	if not Engine.is_editor_hint():
		return
	call_deferred("_pin_to_idle_frame")

func _process(_delta):
	if not Engine.is_editor_hint():
		return
	# 每次进入播放态就钉回第0帧（防编辑器误触播放/重载后跑走）
	var ap: AnimationPlayer = get_node_or_null("AnimationPlayer")
	if ap == null or ap.current_animation != "Rifle Aiming Idle":
		_pin_to_idle_frame()

func _pin_to_idle_frame():
	var ap: AnimationPlayer = get_node_or_null("AnimationPlayer")
	if ap == null or not ap.has_animation("Rifle Aiming Idle"):
		return
	ap.play("Rifle Aiming Idle")
	ap.seek(0.0, true)
	ap.pause()
