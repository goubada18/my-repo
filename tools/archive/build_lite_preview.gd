extends SceneTree
## 轻量系统预览：原始新SWAT（不动）+ 自带待机动画 + AK47 + 地板 + 相机。保证能看。
## 用法：godot --headless --path <proj> --script tools/build_lite_preview.gd

const OUT := "res://scenes/swat_system_preview.tscn"

func _collect(n: Node, out: Array = []) -> Array:
	out.append(n)
	for c in n.get_children():
		_collect(c, out)
	return out

func _set_owner(n: Node, owner: Node) -> void:
	n.owner = owner
	for c in n.get_children():
		_set_owner(c, owner)

func _initialize() -> void:
	var root3d := Node3D.new()
	root3d.name = "SWATSystem"
	root.add_child(root3d)
	# 环境 + 灯光
	var env := WorldEnvironment.new()
	env.name = "WorldEnvironment"
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.35, 0.42, 0.5)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.6, 0.65)
	e.ambient_light_energy = 0.8
	env.environment = e
	root3d.add_child(env)
	var light := DirectionalLight3D.new()
	light.name = "Sun"
	light.rotation_degrees = Vector3(-50, 30, 0)
	light.shadow_enabled = true
	light.light_energy = 1.0
	root3d.add_child(light)
	# 地板
	var floor := StaticBody3D.new()
	floor.name = "Floor"
	floor.position = Vector3(0, -0.5, 0)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(30, 1, 30)
	col.shape = shape
	floor.add_child(col)
	var fmesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(30, 1, 30)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.45, 0.48)
	mat.roughness = 0.9
	box.material = mat
	fmesh.mesh = box
	floor.add_child(fmesh)
	root3d.add_child(floor)
	# 角色：实例 swat_preview.tscn（原始FBX + 待机动画 + 相机，零改动）
	var swat_ps: PackedScene = load("res://scenes/swat_preview.tscn")
	var swat: Node = swat_ps.instantiate()
	swat.name = "Character_SWAT"
	root3d.add_child(swat)
	# 武器：从 character.tscn 复制 Weapon_AK47 子树，放到双手之间
	var tpl: Node = load("res://scenes/character.tscn").instantiate()
	root.add_child(tpl)
	await process_frame
	var wpn: Node = null
	for n in _collect(tpl):
		if n.name == "Weapon_AK47":
			wpn = n
			break
	wpn.get_parent().remove_child(wpn)
	root3d.add_child(wpn)
	wpn.name = "Weapon_AK47"
	# 手部世界位置：RightHand=(-0.247,2.298,0.288) LeftHand=(-0.022,2.333,0.791)，武器放中点，保持原旋转
	var mid := Vector3(-0.135, 2.315, 0.54)
	var base := Transform3D(wpn.transform.basis, mid)
	wpn.transform = base
	_set_owner(wpn, root3d)
	_set_owner(floor, root3d)
	_set_owner(env, root3d)
	_set_owner(light, root3d)
	_set_owner(swat, root3d)
	# 相机：放角色正面稍远（若 swat_preview 自带相机则保留）
	var ps := PackedScene.new()
	var err := ps.pack(root3d)
	print("pack err=%d" % err)
	if err == OK:
		err = ResourceSaver.save(ps, OUT)
		print("save err=%d -> %s" % [err, OUT])
	tpl.free()
	await process_frame
	quit(0)
