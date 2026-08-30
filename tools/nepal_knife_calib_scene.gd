@tool
extends Node3D
## 尼泊尔刀 3P 挂点【标定场景】——编辑器内 WYSIWYG 调整 + 一键保存到每角色标定资源。
##
## 场景树（Knife 节点常驻本 tscn，打开即可见可选）：
##   NepalKnifeCalib
##   ├─ CharacterHolder   （角色实例，脚本按 character_id 动态创建/切换）
##   └─ HandAnchor        （脚本每帧驱动到右手骨骼位姿）
##       └─ Knife         （★ 拖拽这个节点调刀位；local transform 即标定值）
##
## 用法：
##   1. Inspector 顶部 character_id 选角色（feihu / swat）——角色自动重建，持刀待机
##      合成（22° 抬臂）与游戏 _apply_nepal_stance 逐参数一致，动画持续播放
##   2. 拖拽 Knife（或 3D 视口点选拖动），直到刀贴手满意
##   3. 点 [保存当前刀位 → 标定资源] → 写入 resources/characters/nepal_knife_calib_<角色>.tres
##   4. 进游戏切尼泊尔即为标定位置（运行时读同一份 tres；本场景不会被游戏加载）
##
## 注意：HandAnchor 由脚本每帧跟随手部骨骼；Knife 的 local transform 才是标定值，
## 脚本绝不会改写它（拖拽与脚本不打架）。Ctrl+S 保存场景会把拖后的 Knife 姿态
## 一并写进 tscn，仅作显示缓存——运行时以 tres 为准（_ready 会重新应用）。

const CHAR_SCENES := {
	"feihu": "res://scenes/character.tscn",
	"swat": "res://scenes/character_preview.tscn",
}
const CALIB_PATHS := {
	"feihu": "res://resources/characters/nepal_knife_calib_feihu.tres",
	"swat": "res://resources/characters/nepal_knife_calib_swat.tres",
}
const KNIFE_BONE := "mixamorig_RightHand"
const IDLE_NAME := "Rifle Aiming Idle"
const IDLE_ARMS := "res://resources/animations/nepal3p/nepal_idle_arms.tres"
const NEPAL_ARM_LIFT_DEG := 22.0
const ARMS_BONES := ["LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
	"RightShoulder", "RightArm", "RightForeArm", "RightHand"]

@export_enum("feihu", "swat") var character_id: String = "feihu":
	set(v):
		character_id = v
		if is_node_ready():
			_rebuild_character()

@export_tool_button("保存当前刀位 → 标定资源") var _save_btn: Callable = _save_calib
@export_tool_button("重置为已保存标定") var _reset_btn: Callable = _reload_calib
@export_tool_button("重建角色预览") var _rebuild_btn: Callable = _rebuild_character

@onready var _hand_anchor: Node3D = $HandAnchor
@onready var _knife: Node3D = $HandAnchor/Knife

var _char_inst: Node = null
var _skel: Skeleton3D = null
var _bone_idx: int = -1
var _dyn: Array = []   # 动态创建的节点（不设 owner → 不会写进本 tscn）

func _ready() -> void:
	_rebuild_character()
	_apply_calib()

func _process(_delta: float) -> void:
	# HandAnchor 每帧跟随右手骨骼全局位姿（Knife 是其子节点 → 实时跟手）
	if _skel != null and _bone_idx >= 0 and _hand_anchor != null:
		_hand_anchor.global_transform = _skel.global_transform * _skel.get_bone_global_pose(_bone_idx)

## （重）实例角色、藏内嵌步枪、合成持刀待机并播放。Knife/HandAnchor 不动。
func _rebuild_character() -> void:
	# 清理上一轮动态节点
	for n in _dyn:
		if is_instance_valid(n):
			n.queue_free()
	_dyn.clear()
	_char_inst = null
	_skel = null
	_bone_idx = -1
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
		ak.visible = false   # 藏内嵌步枪（持刀观感）
	var ap := _find_anim_player(_char_inst)
	if ap == null:
		push_warning("标定场景: 角色无 AnimationPlayer")
		return
	_apply_knife_stance(ap)
	_skel = _find_skeleton(_char_inst)
	if _skel == null:
		push_warning("标定场景: 角色无 Skeleton3D")
		return
	_bone_idx = _skel.find_bone(KNIFE_BONE)
	if _bone_idx < 0:
		push_warning("标定场景: 骨骼缺失 " + KNIFE_BONE)
		return
	# 【关键】切角色后必须把 Knife 重置为新角色的已保存标定：
	# 否则 Knife 残留上一角色的局部值，此时点保存会把 A 空间数值写进 N 空间角色的
	# tres（差 ~53 倍，实测踩坑）。
	_apply_calib()
	print("标定场景[%s]: 角色预览就绪。拖拽 HandAnchor/Knife 调刀位，满意后点保存按钮。" % character_id)

## 持刀待机合成（与 player.gd _nepal_combine / 旧标定场景逐参数一致：含 22° 抬臂、
## 循环动画跳过 position 轨道、仅替换手臂 8 骨）
func _apply_knife_stance(ap: AnimationPlayer) -> void:
	# 【防污染·关键】ap 的默认动画库就是共享的 mixamo_lib(_swat).tres 资源对象。
	# 直接 install 会 remove/add 共享库条目 → 编辑器把 tres 标脏 → 保存时
	# "尼泊尔手臂版 Rifle Aiming Idle"被写进磁盘 → 游戏 AK 第三人称待机自动变成
	# 持刀手臂（循环 bug 实测：每次标定保存后必现）。与运行时
	# player._make_anim_library_private 同纪律：先换入私有库副本再改写，
	# 共享 tres 从此不被触碰、不会标脏。换库前先停播（防 dangling 引用）。
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
	if absf(NEPAL_ARM_LIFT_DEG) > 0.01:
		q_lift = Quaternion(Vector3(1.0, 0.0, 0.0), deg_to_rad(-NEPAL_ARM_LIFT_DEG))
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

## 把当前保存的标定应用到 Knife 的 local transform（拖拽后脚本绝不改写它）
func _apply_calib() -> void:
	var c = load(CALIB_PATHS.get(character_id, "")) if CALIB_PATHS.has(character_id) else null
	if c == null:
		push_warning("标定场景: %s 无标定资源（Knife 保持现状，拖好后点保存即会生成）" % character_id)
		return
	_knife.position = c.local_pos
	_knife.quaternion = c.local_rot
	_knife.scale = c.local_scale

func _save_calib() -> void:
	var path: String = CALIB_PATHS.get(character_id, "")
	if path == "" or _knife == null:
		push_warning("标定场景: 未就绪，无法保存")
		return
	var CalibScript: GDScript = load("res://scripts/nepal_knife_calib.gd")
	var c: Resource = CalibScript.new()
	c.local_pos = _knife.position
	c.local_rot = _knife.quaternion
	c.local_scale = _knife.scale
	c.bone_name = KNIFE_BONE
	c.note = "%s 右手骨骼局部系。标定场景 scenes/nepal_knife_calib.tscn 拖拽保存。" % character_id
	var err := ResourceSaver.save(c, path)
	print("标定场景[%s]: 已保存 %s (err=%d)  pos=%s  rot=%s  scale=%s" % [
		character_id, path, err, str(c.local_pos), str(c.local_rot), str(c.local_scale)])
	if err != OK:
		push_error("标定场景: 保存失败 err=%d" % err)

func _reload_calib() -> void:
	_apply_calib()
	print("标定场景[%s]: 已重置为已保存标定" % character_id)

## 换入默认动画库的私有副本（浅复制：动画对象共享但库条目私有），
## 使后续 install 的 remove/add 只作用于副本。共享 tres 资源对象不被修改。
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
