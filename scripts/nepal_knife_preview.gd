@tool
## 尼泊尔刀 3P 挂载预览/标定场景（WYSIWYG = 与游戏实机链路完全一致）
## - 加载角色 + 持刀待机合成（含 NEPAL_ARM_LIFT_DEG 抬臂），与 player.gd _apply_nepal_stance 一致
## - Knife：普通 Node3D 包裹（KnifeModel 才是 glb 实例），编辑器视口/场景树直接选中、拖拽、缩放、旋转
## - HandleMarker（绿球，Knife 子节点）：拖到刀柄位置 = 你要绑到手掌的点
## - RightHandMarker（红球，场景保存的 BoneAttachment 子节点）：右手骨骼位置（手掌）= 绑定目标，原生跟随骨骼、可在树中选中
##   ⚠️ 两个球都必须是"非实例保护"的节点（绿球是普通 Node3D 子节点、红球是场景保存的骨骼附件节点），
##      否则 3D 视口点选会被父级网格/实例根吞掉，导致"选不中"。
## 标定流程：
##   1) 编辑器里把 Knife 拖到完美持刀位，把绿球(HandleMarker)拖到刀柄
##   2) 运行时 F6 → 按 B：脚本把刀柄吸附到红球(手掌)并打印绑定常量
##   3) 把控制台打印的 3 个常量发我 → 写入 player.gd
## 数学：BoneAttachment3D 每帧把自身 transform 覆盖为骨骼姿态，偏移/旋转【必须写在刀本身(inst)】，
##   不能写在 ba 上（否则全部失效 → 进游戏刀不在编辑器标定的位置）。
##   绑定 = inst.transform = ba.global^{-1} * (平移刀使刀柄点在骨骼原点后的刀世界 transform)
extends Node3D

@export var re_place: bool = false:
	set(v):
		re_place = v
		if v and _knife != null:
			_reset_knife_default()

const KNIFE_BONE := "mixamorig_RightHand"
const ARMS_BONES := ["LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand", "RightShoulder", "RightArm", "RightForeArm", "RightHand"]
const IDLE_ARMS := "res://resources/animations/nepal3p/nepal_idle_arms.tres"
const NEPAL_ARM_LIFT_DEG := 22.0

## 默认摆位（用户还没拖时给个合理起点；拖过之后脚本不再覆盖）
const DEFAULT_KNIFE_POS := Vector3(-0.55, 2.25, 0.62)
const DEFAULT_KNIFE_ROT_DEG := Vector3(-90.0, 0.0, 0.0)
const DEFAULT_KNIFE_SCALE := 4.5
## 默认刀柄标注点（Knife 局部，假设 -Z 为刀柄端）：用户会拖到真实刀柄
const DEFAULT_HANDLE_LOCAL := Vector3(0.0, 0.0, -0.09)

var _knife: Node3D = null
var _marker: MeshInstance3D = null
var _skel: Skeleton3D = null
var _label: Label = null
var _setup_done := false
var _b_held := false

var _bound_pos := Vector3.ZERO
var _bound_rot := Quaternion.IDENTITY
var _bound_scale := Vector3.ONE

func _ready() -> void:
	if _setup_done:
		return
	_setup_done = true
	# 【崩溃修复】游戏运行时（非编辑器）不做动画合成：
	# _apply_knife_stance 会通过 AnimationCombiner.install 改写共享的
	# "Rifle Aiming Idle" Animation 资源（mixamo_lib.tres），与游戏侧
	# player.gd _apply_nepal_stance 同时操作同一资源 → 悬空指针 → SIGSEGV。
	# 运行时只需要 Knife 子树（用户标定的刀位），动画合成只对编辑器标定有意义。
	if not Engine.is_editor_hint():
		print("[NEPAL-PREVIEW] 运行时模式，跳过动画合成（守卫生效）")
		_knife = find_child("Knife", true, false) as Node3D
		var char_inst := find_child("Character", true, false) as Node
		if char_inst == null:
			char_inst = self
		for n in char_inst.find_children("*", "Skeleton3D", true, false):
			_skel = n as Skeleton3D
			break
		print("[NEPAL-PREVIEW] 运行时初始化完成, Knife=", _knife != null, " Skeleton=", _skel != null)
		return
	_setup()

func _setup() -> void:
	var char_inst := find_child("Character", true, false) as Node
	if char_inst == null:
		char_inst = self
	for n in char_inst.find_children("*", "Skeleton3D", true, false):
		_skel = n as Skeleton3D
		break
	if _skel == null:
		push_warning("预览: 未找到 Skeleton3D")
		return
	if _skel.find_bone(KNIFE_BONE) < 0:
		push_warning("预览: 未找到骨骼 " + KNIFE_BONE)
		return
	# 红球（右手骨骼位置）：已在场景里用 BoneAttachment3D 直接挂在骨骼上
	# （场景节点 RightHandAttach / RightHandMarker，bone_name=mixamorig_RightHand）。
	# 这是引擎原生"贴骨骼"机制，编辑器与运行时都自动跟随骨骼姿态，
	# 不依赖脚本 _process，且作为场景保存节点可在场景树/视口直接选中。
	_marker = find_child("RightHandMarker", true, false) as MeshInstance3D
	if _marker == null:
		push_warning("预览: 未找到 RightHandMarker（场景应含 RightHandAttach/RightHandMarker）")
	# 刀（场景预置节点：Knife 为普通 Node3D 包裹，KnifeModel 为 glb 实例，
	#   HandleMarker 为 Knife 子节点 → 视口/场景树均可直接选中拖拽）
	_knife = find_child("Knife", true, false) as Node3D
	if _knife == null:
		push_warning("预览: 未找到 Knife")
	# 用户还没摆 → 默认摆位（避免刀在原点看不见）
	if _knife != null and _knife.position.length() < 0.001 and absf(_knife.scale.x - 1.0) < 0.001:
		_reset_knife_default()
	_apply_knife_stance(char_inst)
	_make_label()

## 用户还没摆刀时给默认摆位（Knife 在原点/未缩放才触发；拖过后不再覆盖）
func _reset_knife_default() -> void:
	if _knife == null:
		return
	_knife.scale = Vector3.ONE * DEFAULT_KNIFE_SCALE
	_knife.rotation_degrees = DEFAULT_KNIFE_ROT_DEG
	_knife.position = DEFAULT_KNIFE_POS
	var h := find_child("HandleMarker", true, false) as Node3D
	if h != null:
		h.position = DEFAULT_HANDLE_LOCAL * DEFAULT_KNIFE_SCALE

## 持刀待机合成（与 player.gd _apply_nepal_stance 逐参数一致：含 22° 抬臂）
func _apply_knife_stance(char_inst: Node) -> void:
	var ak := char_inst.find_child("Weapon_AK47", true, false) as Node3D
	if ak != null:
		ak.visible = false
	var ap: AnimationPlayer = null
	for n in char_inst.find_children("*", "AnimationPlayer", true, false):
		ap = n as AnimationPlayer
		break
	if ap == null:
		return
	var idle: Animation = ap.get_animation("Rifle Aiming Idle")
	var arms: Animation = load(IDLE_ARMS)
	if idle == null or arms == null:
		push_warning("预览: 持刀待机合成缺资源 idle=", idle != null, " arms=", arms != null)
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
	var _q_lift := Quaternion.IDENTITY
	if absf(NEPAL_ARM_LIFT_DEG) > 0.01:
		_q_lift = Quaternion(Vector3(1.0, 0.0, 0.0), deg_to_rad(-NEPAL_ARM_LIFT_DEG))
	for i in arms.get_track_count():
		var sp := str(arms.track_get_path(i))
		if not AnimationCombiner.is_upper_body_track(sp, ARMS_BONES):
			continue
		if arms.track_get_type(i) != Animation.TYPE_ROTATION_3D:
			continue
		var _is_sh: bool = sp.contains("Shoulder")
		var _plen: float = arms.length
		var _kc: int = arms.track_get_key_count(i)
		var _ni := comb.add_track(Animation.TYPE_ROTATION_3D)
		comb.track_set_path(_ni, arms.track_get_path(i))
		for _j in range(_kc):
			var _t: float = arms.track_get_key_time(i, _j)
			var _v: Quaternion = arms.track_get_key_value(i, _j)
			if _is_sh:
				_v = _q_lift * _v
			var _t2: float = _t
			while _t2 <= comb.length + 0.001:
				comb.track_insert_key(_ni, _t2, _v)
				_t2 += _plen
		comb.track_set_interpolation_type(_ni, Animation.INTERPOLATION_LINEAR)
	AnimationCombiner.install(ap, "Rifle Aiming Idle", comb)
	ap.play("Rifle Aiming Idle")

func _right_hand_world_pos() -> Vector3:
	if _skel == null:
		return Vector3.ZERO
	var bi := _skel.find_bone(KNIFE_BONE)
	if bi < 0:
		return Vector3.ZERO
	return _skel.to_global(_skel.get_bone_global_pose(bi).origin)

## 绑定：把刀柄标注球(HandleMarker)吸附到手掌骨骼，输出可直接写 player.gd 的常量。
## 关键：BoneAttachment3D 每帧覆盖自身 transform → 偏移/旋转写在【刀本身】(inst)。
func _bind_handle_to_palm() -> void:
	if _knife == null or _skel == null:
		push_warning("绑定: 缺 Knife 或 Skeleton")
		return
	var handle := find_child("HandleMarker", true, false) as Node3D
	if handle == null:
		push_warning("绑定: 未找到 HandleMarker")
		return
	var bi := _skel.find_bone(KNIFE_BONE)
	if bi < 0:
		return
	# 骨骼世界 transform（等价于 ba.global，已验证）
	var bone_world: Transform3D = _skel.global_transform * _skel.get_bone_global_pose(bi)
	# 用户在预览里摆好的刀世界 transform + 标注的刀柄世界点
	var Kw: Transform3D = _knife.global_transform
	var H_world: Vector3 = handle.global_position
	# 平移刀，使刀柄点落到骨骼原点（保持刀的旋转/缩放不变）
	var delta: Vector3 = bone_world.origin - H_world
	var mounted_Kw: Transform3D = Transform3D(Basis.IDENTITY, delta) * Kw
	# 换算为"相对骨骼的局部 transform"（骨架空间原始单位，直接写 inst，无需 /arm_scale）
	# ⚠️ 必须用 affine_inverse()：普通 inverse() 不反转缩放（Godot4.7 的 Transform3D.inverse
	# 只反旋转/平移），会导致刀世界缩放置 0。affine_inverse() 才正确反缩放。
	var L: Transform3D = bone_world.affine_inverse() * mounted_Kw
	_bound_pos = L.origin
	_bound_rot = Quaternion(L.basis.orthonormalized())
	_bound_scale = L.basis.get_scale()
	# 预览实时把刀移到绑定位置（所见即所得：刀柄吸附到手掌红球）
	_knife.global_transform = mounted_Kw
	print("===== 尼泊尔刀绑定结果（写入 player.gd 的 3 个常量）=====")
	print("const NEPAL_KNIFE_LOCAL_POS := Vector3(%s, %s, %s)" % [_num(_bound_pos.x), _num(_bound_pos.y), _num(_bound_pos.z)])
	print("const NEPAL_KNIFE_LOCAL_ROT := Quaternion(%s, %s, %s, %s)" % [_num(_bound_rot.x), _num(_bound_rot.y), _num(_bound_rot.z), _num(_bound_rot.w)])
	print("const NEPAL_KNIFE_LOCAL_SCALE := Vector3(%s, %s, %s)" % [_num(_bound_scale.x), _num(_bound_scale.y), _num(_bound_scale.z)])
	print("=======================================================")

func _num(v: float) -> String:
	return "%.6f" % v

func _process(delta: float) -> void:
	# 红球已用 BoneAttachment 挂在骨骼上，引擎自动跟随（编辑器/运行时都生效），无需脚本干预。
	if Engine.is_editor_hint():
		return  # 编辑器里刀由用户直接拖拽，脚本不干预
	var step: float = 0.005 * (2.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	if Input.is_key_pressed(KEY_B) and not _b_held:
		_b_held = true
		_bind_handle_to_palm()
	elif not Input.is_key_pressed(KEY_B):
		_b_held = false
	if _knife != null:
		if Input.is_key_pressed(KEY_UP):
			_knife.position.z -= step
		if Input.is_key_pressed(KEY_DOWN):
			_knife.position.z += step
		if Input.is_key_pressed(KEY_LEFT):
			_knife.position.x -= step
		if Input.is_key_pressed(KEY_RIGHT):
			_knife.position.x += step
		if Input.is_key_pressed(KEY_PAGEUP):
			_knife.position.y += step
		if Input.is_key_pressed(KEY_PAGEDOWN):
			_knife.position.y -= step
		if Input.is_key_pressed(KEY_BRACKETRIGHT):
			_knife.scale *= 1.01
		if Input.is_key_pressed(KEY_BRACKETLEFT):
			_knife.scale *= 0.99
		if Input.is_key_pressed(KEY_Q):
			_knife.rotate_y(0.02)
		if Input.is_key_pressed(KEY_E):
			_knife.rotate_y(-0.02)
	_update_label()

func _make_label() -> void:
	var cl := CanvasLayer.new()
	cl.name = "HUD"
	add_child(cl)
	_label = Label.new()
	_label.name = "Info"
	_label.position = Vector2(10, 10)
	_label.add_theme_font_size_override("font_size", 16)
	cl.add_child(_label)

func _update_label() -> void:
	if _label == null:
		return
	var hand_world := _right_hand_world_pos()
	_label.text = "尼泊尔刀标定（WYSIWYG 与游戏一致）\n" \
		+ "【编辑器】拖 Knife 到完美持刀位；拖绿球(HandleMarker/Knife子节点)到刀柄\n" \
		+ "【运行时】方向键移刀 Shift加速 [ ]大小 Q/E绕Y；按 B = 刀柄吸附手掌并打印常量\n" \
		+ "红球=右手骨骼: %s\n" % Vector3(round(hand_world.x * 1000) / 1000, round(hand_world.y * 1000) / 1000, round(hand_world.z * 1000) / 1000) \
		+ "【绑定后发我】NEPAL_KNIFE_LOCAL_POS=%s\n" % _bound_pos \
		+ "  ROT=%s\n" % _bound_rot \
		+ "  SCALE=%s" % _bound_scale
