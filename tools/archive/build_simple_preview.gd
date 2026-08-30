extends SceneTree
## 修复 build_simple_preview：避免 tpl+swat 节点名冲突
## 用 swat FBX 作为 Character 根，tpl 只贡献武器/脚本/AnimationPlayer 节点（reparent 后加 unique 后缀）
## 用法：godot --headless --path <proj> --script tools/build_simple_preview.gd

const FEIHU := "res://scenes/character.tscn"
const NEW_FBX := "res://新角色/Rifle Aiming Idle.fbx"
const SWAT_LIB := "res://resources/mixamo_lib_swat.tres"
const OUT := "res://scenes/character_preview.tscn"

var _buf: PackedStringArray = PackedStringArray()

func _log(s: String) -> void:
	_buf.append(s)

func _flush() -> void:
	var f := FileAccess.open("res://probe_build_simple.txt", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_buf) + "\n")
		f.close()
	for s in _buf:
		print(s)

func _collect(n: Node, out: Array = []) -> Array:
	out.append(n)
	for c in n.get_children():
		_collect(c, out)
	return out

## 设置 owner 链。关键：遇到【实例化节点】（scene_file_path 非空，如 gltf 武器实例）
## 只设它自己，不深入其子节点——实例内部节点的 owner 属于实例场景，
## pack 时不会展开成手动节点，从而避免 "ak" 之类的重名冲突。
func _set_owner(n: Node, owner: Node) -> void:
	n.owner = owner
	if n.scene_file_path != "":
		return
	for c in n.get_children():
		_set_owner(c, owner)

func _initialize() -> void:
	_log("=== 修复版：swat 作 Character 根，tpl 节点重命名加入 ===")
	# 1) swat FBX 作 Character 根（含 Skeleton3D+mesh+自身 AnimationPlayer）
	var swat: Node = load(NEW_FBX).instantiate()
	swat.name = "Character_SWAT"
	root.add_child(swat)
	await process_frame
	await process_frame
	# 2) 从 character.tscn 拿武器/AnimationPlayer/脚本（重命名避免冲突）
	var tpl: Node = load(FEIHU).instantiate()
	root.add_child(tpl)
	await process_frame
	await process_frame
	# 找到要 reparent 的节点
	var nodes_to_move := []
	for n in _collect(tpl):
		if n.name == "AnimationPlayer":
			nodes_to_move.append(n)
		elif n.name == "Weapon_AK47":
			nodes_to_move.append(n)
		# grip_pose_preview 脚本在根节点上，tpl 根也带这个脚本
	if tpl.get_node_or_null("."):
		var root_script: Script = tpl.get_script()
		if root_script:
			swat.set_script(root_script)
	_log("从 tpl 移出节点: %d 个" % len(nodes_to_move))
	# 3) Reparent 到 swat 根。
	# 注意：swat FBX 顶层只有 Skeleton3D + AnimationPlayer，没有 Weapon_AK47，
	# 所以武器【保持原名 Weapon_AK47】（player.gd 靠 find_child("Weapon_AK47") 挂载，
	# 改名会挂载失败 → 枪不射击/悬空）。只有 AnimationPlayer 与 swat 自带节点冲突，需改名。
	for n in nodes_to_move:
		var base_name: String = n.name
		tpl.remove_child(n)
		swat.add_child(n)
		if base_name == "AnimationPlayer":
			n.name = "AnimationPlayer_w1"
			_log("  reparented: %s -> %s（与 swat 自带 AnimationPlayer 重名，加后缀）" % [base_name, n.name])
		else:
			_log("  reparented: %s（保持原名，player.gd 依赖）" % base_name)
	# 4) AnimationPlayer 的库换成换算库（避免 tpl 的原 AnimationPlayer 没被移动时也用新库）
	for n in _collect(swat):
		if n is AnimationPlayer:
			var lib: AnimationLibrary = load(SWAT_LIB)
			if n.has_animation_library(""):
				n.remove_animation_library("")
			n.add_animation_library("", lib)
			_log("AnimationPlayer %s 换算库已替换" % n.name)
	# 5) Armature scale=0.013795（N单位→米，角色 205.7 → 2.838m 与飞虎队同高）
	# 关键：武器 transform 是飞虎队世界空间坐标（y≈2.38 手持位），
	# 只有角色也放大到 2.84m，武器才能落在角色手上而非悬空。
	var nskel: Skeleton3D = null
	for n in _collect(swat):
		if n is Skeleton3D:
			nskel = n
			break
	if nskel:
		var arm := Node3D.new()
		arm.name = "Armature"
		arm.transform = Transform3D(Basis.from_scale(Vector3.ONE * 0.013795), Vector3.ZERO)
		var sp: Node = nskel.get_parent()
		sp.remove_child(nskel)
		arm.add_child(nskel)
		sp.add_child(arm)
		_log("Armature 已加，scale=0.01")
	# 6) PreviewCamera（独立场景可选）
	var cam := Camera3D.new()
	cam.name = "PreviewCamera"
	cam.current = true
	cam.position = Vector3(0, 1.7, 4.6)
	cam.look_at(Vector3(0, 1.5, 0), Vector3.UP)
	swat.add_child(cam)
	# 7) 设置 owner + pack
	# swat 是场景根：清掉它的实例身份（FBX），让 _set_owner 能深入骨架/网格子树；
	# 而 tpl 里 reparent 过来的 Weapon_AK47/AK47Model 保持 gltf 实例（scene_file_path 非空），
	# _set_owner 只设其自身不深入 → pack 保留实例引用，避免 ak 重名冲突。
	swat.scene_file_path = ""
	_set_owner(swat, swat)
	var dbg: String = ""
	_collect_dump(swat, "", dbg)
	_log("节点树:\n" + dbg)
	var ps := PackedScene.new()
	var err := ps.pack(swat)
	_log("pack err=%d" % err)
	if err == OK:
		err = ResourceSaver.save(ps, OUT)
		_log("save err=%d -> %s" % [err, OUT])
	tpl.queue_free(); swat.queue_free()
	await process_frame
	_log("DONE")
	_flush()
	quit(0)

func _collect_dump(n: Node, indent: String, out: String) -> String:
	var s: String = out + indent + n.name + " [" + n.get_class() + "]\n"
	for c in n.get_children():
		s = _collect_dump(c, indent + "  ", s)
	return s
