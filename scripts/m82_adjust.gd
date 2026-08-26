@tool
extends Node3D
## M82A1 视图模型调整工作区（编辑器实时调摆放 + 运行时切换动画）
## 用法：
##   编辑器打开 scenes/m82_adjust.tscn
##   - 编辑器里自动播放 idle 动画（3D 视口直接显示握枪待机姿势）
##   - Inspector 调 gun_pos / gun_rot / mirror_scale，模型实时跟随（编辑器 3D 视口）
##   - 相机是独立节点，可在编辑器里直接拖动/改 transform 调整观察角度
##   - F6 运行，按 1~7 数字键切换动画（1=idle 2=shoot1 3=shoot2 4=shoot3 5=reload 6=draw 7=idle2）
##   调好后把 gun_pos/gun_rot/camera transform 数值抄给实际使用处。

@export var model_path: String = "res://fp_viewmodel/m82a1_viewmodel.gltf"
@export var gun_pos: Vector3 = Vector3(0.10, -0.20, -0.70)   # 与 fp_view_config 的 fp_gun_pos 同义
@export var gun_rot: Vector3 = Vector3(0.0, 1.5708, 0.04)    # fp_gun_rot
@export var mirror_scale: bool = true                        # FP 左手镜像成右手

var _model: Node3D = null
var _ap: AnimationPlayer = null

func _ensure_model() -> void:
	if _model == null or not is_instance_valid(_model):
		var ps: PackedScene = load(model_path)
		if ps == null:
			return
		_model = ps.instantiate() as Node3D
		_model.name = "M82VM"
		add_child(_model)
		_ap = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if _ap != null and _ap.animation_finished.is_connected(_on_anim_done) == false:
			_ap.animation_finished.connect(_on_anim_done)
		# 不向世界投阴影（FP 视图模型惯例）
		for mi in _model.find_children("*", "GeometryInstance3D", true, false):
			(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _apply_pose() -> void:
	_ensure_model()
	if _model == null:
		return
	_model.scale = Vector3(1, 1, -1) if mirror_scale else Vector3.ONE
	_model.position = gun_pos
	_model.rotation = gun_rot

func _ready() -> void:
	_apply_pose()
	# 编辑器里也播放 idle，方便直接看握枪待机姿势调整相机
	_play_anim("idle")

func _on_anim_done(name: StringName) -> void:
	if name != "idle":
		_play_anim("idle")

func _play_anim(nm: String) -> void:
	_ensure_model()
	if _ap == null:
		return
	if _ap.has_animation(nm):
		_ap.play(nm)
		print("[M82] 动画 -> ", nm)
	else:
		print("[M82] 无动画: ", nm)

var _ANIMS: Array[String] = ["idle", "shoot1", "shoot2", "shoot3", "reload", "draw", "idle2"]

func _process(_delta: float) -> void:
	_apply_pose()   # 编辑器里实时跟随 Inspector 修改
	if not Engine.is_editor_hint():
		for i in range(_ANIMS.size()):
			var code: Key = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7][i]
			if Input.is_key_pressed(code):
				_play_anim(_ANIMS[i])
