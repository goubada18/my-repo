@tool
extends Node3D
## 尼泊尔刀 3P 挂点【标定场景】——编辑器内 WYSIWYG 调整 + 一键保存到每角色标定资源。
##
## 用法（在编辑器中打开本场景，选中根节点）：
##   1. Inspector 顶部 character_id 选择要标定的角色（feihu / swat）——预览会自动重建：
##      角色 + 持刀待机合成（22° 抬臂，与游戏 _apply_nepal_stance 逐参数一致）+ 刀挂右手骨骼
##   2. 在 3D 视口直接拖拽/旋转/缩放 Knife 节点（场景树里名为 "Knife"），直到刀贴手满意
##      （待机动画在编辑器中持续播放，刀实时跟随手部骨骼，所见即所得）
##   3. 点 Inspector 里的 [保存当前刀位 → 标定资源] 按钮 → 写入该角色的
##      resources/characters/nepal_knife_calib_<角色>.tres
##   4. 进游戏切尼泊尔即为标定后的位置（运行时读同一份资源；游戏从不加载本场景）
##
## 【与旧版 nepal_knife_preview.tscn 的区别】旧流程 = 按 B 打印 3 个常量 → 手工抄进
## player.gd（三代方案叠加后常量注释互相矛盾，抄错层级即出 bug）。新流程 = 每角色
## 一份标定资源直存直读，player.gd 不再持有刀位常量，且无 k 跨角色换算。

const CHAR_SCENES := {
	"feihu": "res://scenes/character.tscn",
	"swat": "res://scenes/character_preview.tscn",
}
const CALIB_PATHS := {
	"feihu": "res://resources/characters/nepal_knife_calib_feihu.tres",
	"swat": "res://resources/characters/nepal_knife_calib_swat.tres",
}
const KNIFE_MODEL := "res://resources/models/nepal/nepal_knife.glb"
const KNIFE_BONE := "mixamorig_RightHand"
const IDLE_NAME := "Rifle Aiming Idle"
const IDLE_ARMS := "res://resources/animations/nepal3p/nepal_idle_arms.tres"
const NEPAL_ARM_LIFT_DEG := 22.0
const ARMS_BONES := ["LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
	"RightShoulder", "RightArm", "RightForeArm", "RightHand"]

@export_enum("feihu", "swat") var character_id: String = "feihu":
	set(v):
		character_id = v
		if is_inside_tree and is_node_ready():
			_rebuild()

@export_tool_button("保存当前刀位 → 标定资源") var _save_btn: Callable = _save_calib
@export_tool_button("重置为已保存标定") var _reset_btn: Callable = _reload_calib
@export_tool_button("重建预览") var _rebuild_btn: Callable = _rebuild

var _char_inst: Node = null
var _skel: Skeleton3D = null
var _bone_idx: int = -1
var _ba: BoneAttachment3D = null
var _knife: Node3D = null
var _dyn: Array = []   # 动态创建的节点（不设 owner → 不会污染本 tscn）

func _ready() -> void:
	_rebuild()

func _rebuild() -> void:
	# 清理上一轮动态节点
	for n in _dyn:
		if is_instance_valid(n):
			n.queue_free()
	_dyn.clear()
	_char_inst = null
	_skel = null
	_ba = null
	_knife = null
	_bone_idx = -1
	if not is_inside_tree:
		return
	# 1) 实例角色场景
	var scene_path: String = CHAR_SCENES.get(character_id, CHAR_SCENES["feihu"])
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		push_warning("标定场景: 无法加载角色场景 " + scene_path)
		return
	_char_inst = packed.instantiate()
	add_child(_char_inst)
	_dyn.append(_char_inst)
	# 2) 藏内嵌步枪（与游戏持刀观感一致）
	var ak := _char_inst.find_child("Weapon_AK47", true, false) as Node3D
	if ak != null:
		ak.visible = false
	# 3) 持刀待机合成（与 player.gd _apply_nepal_stance / 旧标定场景逐参数一致）
	var ap := _find_anim_player(_char_inst)
	if ap == null:
		push_warning("标定场景: 角色无 AnimationPlayer")
		return
	_apply_knife_stance(ap)
	# 4) 右手骨骼挂点
	_skel = _find_skeleton(_char_inst)
	if _skel == null:
		push_warning("标定场景: 角色无 Skeleton3D")
		return
	_bone_idx = _skel.find_bone(KNIFE_BONE)
	if _bone_idx < 0:
		push_warning("标定场景: 骨骼缺失 " + KNIFE_BONE)
		return
	_ba = BoneAttachment3D.new()
	_ba.name = "KnifeHandAttach"
	_ba.bone_name = KNIFE_BONE
	_skel.add_child(_ba)
	_dyn.append(_ba)
	# 5) 刀模型（拖拽这个节点）
	var knife_ps: PackedScene = load(KNIFE_MODEL) as PackedScene
	if knife_ps == null:
		push_warning("标定场景: 无法加载刀模型 " + KNIFE_MODEL)
		return
	_knife = knife_ps.instantiate() as Node3D
	_ba.add_child(_knife)
	_dyn.append(_knife)
	_apply_calib()
	print("标定场景[%s]: 预览就绪。在视口拖拽场景树中的 Knife 节点调位，满意后点 Inspector 的保存按钮。" % character_id)

## 持刀待机合成（与 player.gd _nepal_combine / 旧标定场景逐参数一致：含 22° 抬臂、
## 循环动画跳过 position 轨道、仅替换手臂 8 骨）
func _apply_knife_stance(ap: AnimationPlayer) -> void:
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

func _apply_calib() -> void:
	if _knife == null:
		return
	var c = load(CALIB_PATHS.get(character_id, "")) if CALIB_PATHS.has(character_id) else null
	if c == null:
		push_warning("标定场景: %s 无标定资源，刀置于原点（拖好后点保存即会生成）" % character_id)
		_knife.transform = Transform3D.IDENTITY
		return
	_knife.position = c.local_pos
	_knife.quaternion = c.local_rot
	_knife.scale = c.local_scale

func _save_calib() -> void:
	if _knife == null:
		push_warning("标定场景: 预览未就绪，无法保存")
		return
	var path: String = CALIB_PATHS.get(character_id, "")
	if path == "":
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

func _find_anim_player(root: Node) -> AnimationPlayer:
	for n in root.find_children("*", "AnimationPlayer", true, false):
		return n as AnimationPlayer
	return null

func _find_skeleton(root: Node) -> Skeleton3D:
	for n in root.find_children("*", "Skeleton3D", true, false):
		return n as Skeleton3D
	return null
