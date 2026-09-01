@tool
extends Node3D
## 高爆手雷 3P 挂点【标定场景】——编辑器内 WYSIWYG 调整 + 一键保存到每角色标定资源。
##（仿 nepal_knife_calib_scene.gd；手雷待机=尼泊尔手臂姿态+22°抬臂，与运行时一致）
##
## 场景树（Grenade 节点常驻本 tscn，打开即可见可选）：
##   GrenadeCalib
##   ├─ CharacterHolder   （角色实例，脚本按 character_id 动态创建/切换）
##   └─ HandAnchor        （脚本每帧驱动到右手骨骼位姿）
##       └─ Grenade       （local transform 即标定值）
##
## 用法：
##   1. Inspector 顶部 character_id 选角色（feihu / swat）——角色自动重建，持雷待机
##      合成（22° 抬臂，与游戏 _grenade_combine 一致），动画持续播放
##   2. 勾选 freeze_anchor【冻结挂点】——停动画 + 停每帧跟随，拖拽基准才稳定
##   3. 调【手雷标定】组的 grenade_scale / grenade_pos（★ 推荐直接输数字，见下）
##   4. 点 [保存当前手雷位 → 标定资源] → 写入 resources/characters/grenade_calib_<角色>.tres
##   5. 进游戏切手雷即为标定位置（运行时读同一份 tres；本场景不会被游戏加载）
##
## 【为什么推荐输数字而不是拖 3D gizmo】
##   手雷挂在骨骼下，父链缩放极小（feihu Armature≈0.00026），gizmo 手感极差；
##   且 HandAnchor 每帧被动画驱动（实测 0.056°/帧、0.3mm/帧），拖拽基准一直在漂。
##   世界长轴换算：0.10m 对应 feihu local_scale≈1316 / swat≈24.8，
##   即【世界长轴(米) ≈ grenade_scale / 13163.6】（feihu）。

const CHAR_SCENES := {
	"feihu": "res://scenes/character.tscn",
	"swat": "res://scenes/character_preview.tscn",
}
const CALIB_PATHS := {
	"feihu": "res://resources/characters/grenade_calib_feihu.tres",
	"swat": "res://resources/characters/grenade_calib_swat.tres",
}
const GRENADE_BONE := "mixamorig_RightHand"
const GRENADE_MODEL := "res://resources/models/grenade/grenade_world.glb"
const IDLE_NAME := "Rifle Aiming Idle"
const IDLE_ARMS := "res://resources/animations/nepal3p/nepal_idle_arms.tres"
const ARM_LIFT_DEG := 22.0
const ARMS_BONES := ["LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
	"RightShoulder", "RightArm", "RightForeArm", "RightHand"]

@export_enum("feihu", "swat") var character_id: String = "feihu":
	set(v):
		character_id = v
		if is_node_ready():
			_rebuild_character()
			_apply_calib()   # 切角色 → 必须换用该角色的标定值

## 冻结挂点（标定时用）：停动画 + 停止每帧覆盖 HandAnchor。
## ⚠️【不持久化】用按钮切换运行时变量，绝不用 @export bool——
## @export 会被 Godot 写进 .tscn，用户勾完保存后场景重载仍冻结，切角色时
## HandAnchor 停在旧姿态，标定显示严重失真（swat 手雷 6mm 事故即此）。
## 重载场景永远从"跟随骨骼"状态开始，所见即真实挂载。
var _frozen: bool = false

@export_tool_button("⏸/▶ 冻结挂点（标定时点一下）") var _freeze_btn: Callable = _toggle_freeze

func _toggle_freeze() -> void:
	_frozen = not _frozen
	_apply_freeze()

@export_group("手雷标定（直接输数字，别拖 gizmo）")
## 手雷在右手骨骼局部系下的缩放（三轴同值）。
## 世界长轴(米) ≈ grenade_scale / 13163.6（feihu 骨架）。0.10m 需 ≈1316.36。
@export var grenade_scale: float = 1316.36:
	set(v):
		grenade_scale = v
		_push_transform()
## 手雷在右手骨骼局部系下的位置（骨骼局部单位，非米）
@export var grenade_pos: Vector3 = Vector3(-333.0905, 583.8481, -61.35):
	set(v):
		grenade_pos = v
		_push_transform()

@export_tool_button("保存当前手雷位 → 标定资源") var _save_btn: Callable = _save_calib
@export_tool_button("重置为已保存标定") var _reset_btn: Callable = _reload_calib
@export_tool_button("重建角色预览") var _rebuild_btn: Callable = _rebuild_character

@onready var _hand_anchor: Node3D = $HandAnchor
@onready var _grenade: Node3D = $HandAnchor/Grenade

var _char_inst: Node = null
var _skel: Skeleton3D = null
var _bone_idx: int = -1
var _anim: AnimationPlayer = null
var _dyn: Array = []   # 动态创建的节点（不设 owner → 不会写进本 tscn）
## 朝向由标定资源加载，不在 Inspector 暴露（欧拉角来回转换会有精度损失）
var _rot: Quaternion = Quaternion(0.7071, 0.0, 0.0, 0.7071)

func _ready() -> void:
	_rebuild_character()
	_apply_calib()

func _process(_delta: float) -> void:
	if _frozen:
		return   # 冻结时不动 HandAnchor，用户可自由调整挂点/手雷
	# HandAnchor 每帧跟随右手骨骼全局位姿（Grenade 是其子节点 → 实时跟手）
	if _skel != null and _bone_idx >= 0 and _hand_anchor != null:
		_hand_anchor.global_transform = _skel.global_transform * _skel.get_bone_global_pose(_bone_idx)

## 把 Inspector 上的标定字段写进 Grenade 节点（字段是唯一数据源，避免互相覆盖）
func _push_transform() -> void:
	if _grenade == null:
		return
	_grenade.position = grenade_pos
	_grenade.quaternion = _rot
	_grenade.scale = Vector3.ONE * grenade_scale

## 冻结/恢复：速度归零比 pause() 更稳（pause 后 play 会从头跳）
func _apply_freeze() -> void:
	if _anim != null and is_instance_valid(_anim):
		_anim.speed_scale = 0.0 if _frozen else 1.0
	print("标定场景: 挂点跟随%s" % ("已冻结（可自由拖拽）" if _frozen else "已恢复（跟随骨骼）"))

## （重）实例角色、藏内嵌步枪、合成持雷待机并播放。Grenade/HandAnchor 不动。
func _rebuild_character() -> void:
	for n in _dyn:
		if is_instance_valid(n):
			n.queue_free()
	_dyn.clear()
	_char_inst = null
	_skel = null
	_bone_idx = -1
	_anim = null
	if not is_inside_tree:
		return
	var scene_path: String = CHAR_SCENES.get(character_id, CHAR_SCENES["feihu"])
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		push_warning("标定场景: 无法加载角色场景 " + scene_path)
		return
	_char_inst = packed.instantiate()
	add_child(_char_inst)
	_dyn.append(_char_inst)
	var ak := _char_inst.find_child("Weapon_AK47", true, false) as Node3D
	if ak != null:
		ak.visible = false
	var ap := _find_anim_player(_char_inst)
	if ap == null:
		push_warning("标定场景: 角色无 AnimationPlayer")
		return
	_apply_grenade_stance(ap)
	_skel = _find_skeleton(_char_inst)
	if _skel == null:
		push_warning("标定场景: 角色无 Skeleton3D")
		return
	_bone_idx = _skel.find_bone(GRENADE_BONE)
	if _bone_idx < 0:
		push_warning("标定场景: 骨骼缺失 " + GRENADE_BONE)
		return
	_apply_freeze()   # 沿用当前 freeze_anchor 状态（重建后动画默认会重新播放）
	print("标定场景[%s]: 角色预览就绪。建议先勾 freeze_anchor，再调「手雷标定」组数值。" % character_id)

## 持雷待机合成（与 player.gd _grenade_combine 逐参数一致：含 22° 抬臂、
## 循环动画跳过 position 轨道、仅替换手臂 8 骨）
func _apply_grenade_stance(ap: AnimationPlayer) -> void:
	_anim = ap   # 供 _apply_freeze 控制 speed_scale
	_privatize_anim_library(ap)
	if not ap.has_animation(IDLE_NAME):
		push_warning("标定场景: 角色动画库缺 " + IDLE_NAME)
		return
	var idle: Animation = ap.get_animation(IDLE_NAME)
	var arms: Animation = load(IDLE_ARMS) as Animation
	if arms == null:
		push_warning("标定场景: 缺 " + IDLE_ARMS)
		return
	var comb := Animation.new()
	comb.length = idle.length
	comb.loop_mode = Animation.LOOP_LINEAR
	for i in idle.get_track_count():
		if AnimationCombiner.is_upper_body_track(str(idle.track_get_path(i)), ARMS_BONES):
			continue
		if idle.track_get_type(i) == Animation.TYPE_POSITION_3D:
			continue
		AnimationCombiner.copy_track(idle, i, comb, -1)
	var q_lift := Quaternion.IDENTITY
	if absf(ARM_LIFT_DEG) > 0.01:
		q_lift = Quaternion(Vector3(1.0, 0.0, 0.0), deg_to_rad(-ARM_LIFT_DEG))
	for i in arms.get_track_count():
		var sp := str(arms.track_get_path(i))
		if not AnimationCombiner.is_upper_body_track(sp, ARMS_BONES):
			continue
		if arms.track_get_type(i) != Animation.TYPE_ROTATION_3D:
			continue
		var is_sh: bool = sp.contains("Shoulder")
		var plen: float = arms.length
		var kc: int = arms.track_get_key_count(i)
		if plen <= 0.001:
			continue
		var ni := comb.add_track(Animation.TYPE_ROTATION_3D)
		comb.track_set_path(ni, arms.track_get_path(i))
		for j in kc:
			var t: float = arms.track_get_key_time(i, j)
			var v: Quaternion = arms.track_get_key_value(i, j)
			if is_sh:
				v = q_lift * v
			var t2: float = t
			while t2 <= comb.length + 0.001:
				comb.track_insert_key(ni, t2, v)
				t2 += plen
		comb.track_set_interpolation_type(ni, Animation.INTERPOLATION_LINEAR)
	AnimationCombiner.install(ap, IDLE_NAME, comb)
	ap.play(IDLE_NAME)

## 从标定资源回填 Inspector 字段（字段是唯一数据源 → 再同步到 Grenade 节点）。
## 只在【打开场景】和【切换 character_id】时调用；「重建角色预览」不调用，
## 否则用户刚调好的数值会被标定资源悄悄覆盖（实测踩过的坑）。
func _apply_calib() -> void:
	# @onready 尚未赋值时（场景刚实例化、未进树就被改 character_id）直接跳过，
	# 否则 _grenade.position 会报 "on a base object of type 'Nil'"
	if _grenade == null:
		return
	var c = load(CALIB_PATHS.get(character_id, "")) if CALIB_PATHS.has(character_id) else null
	if c == null:
		push_warning("标定场景: %s 无标定资源（保持现状，调好后点保存即会生成）" % character_id)
		return
	grenade_scale = c.local_scale.x
	grenade_pos = c.local_pos
	_rot = c.local_rot
	_push_transform()

func _save_calib() -> void:
	var path: String = CALIB_PATHS.get(character_id, "")
	if path == "" or _grenade == null:
		push_warning("标定场景: 未就绪，无法保存")
		return
	var CalibScript: GDScript = load("res://scripts/nepal_knife_calib.gd")
	var c: Resource = CalibScript.new()
	# ★ 以 Grenade 节点当前 transform 为准（用户在 3D 视口拖的是【节点】，不是字段！
	#   字段是单向"字段→节点"推送，拖节点不会回写字段——若保存读字段，拖动白拖）。
	c.local_pos = _grenade.position
	c.local_rot = _grenade.quaternion
	c.local_scale = _grenade.scale
	c.bone_name = GRENADE_BONE
	c.note = "%s 右手骨骼局部系。世界长轴≈scale/13163.6 米。标定场景 scenes/grenade_calib.tscn 保存。" % character_id
	var err := ResourceSaver.save(c, path)
	# 回填字段，让 Inspector 与节点一致（避免"节点是新的、字段还是旧的"困惑）
	grenade_pos = _grenade.position
	grenade_scale = _grenade.scale.x
	_rot = _grenade.quaternion
	print("标定场景[%s]: 已保存 %s (err=%d)  pos=%s  scale=%.4f（世界长轴≈%.4f m）" % [
		character_id, path, err, str(c.local_pos), c.local_scale.x, c.local_scale.x / 13163.6])
	if err != OK:
		push_error("标定场景: 保存失败 err=%d" % err)

func _reload_calib() -> void:
	_apply_calib()
	print("标定场景[%s]: 已重置为已保存标定" % character_id)

## 换入默认动画库的私有副本（浅复制），使 install 的 remove/add 只作用于副本。
func _privatize_anim_library(ap: AnimationPlayer) -> void:
	ap.stop()
	var lib := ap.get_animation_library("")
	if lib == null:
		return
	var priv := AnimationLibrary.new()
	for an in lib.get_animation_list():
		priv.add_animation(an, lib.get_animation(an))
	ap.remove_animation_library("")
	ap.add_animation_library("", priv)

func _find_anim_player(root: Node) -> AnimationPlayer:
	for n in root.find_children("*", "AnimationPlayer", true, false):
		return n as AnimationPlayer
	return null

func _find_skeleton(root: Node) -> Skeleton3D:
	for n in root.find_children("*", "Skeleton3D", true, false):
		return n as Skeleton3D
	return null
