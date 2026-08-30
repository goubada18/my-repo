class_name CharacterManager
extends Node
## 角色管理器（P2 修订版）：管理角色槽位，角色视觉挂载到 Player/Character 挂载点。
##
## 关键修订（修复双模型 bug）：
## - 角色视觉【不挂在 CharacterManager 自己下面】，而是由 player 调用 mount_active_to()
##   挂到 Player/Character 挂载点 → 场景里始终只有一个可见角色模型
## - 切换 = 换挂载点下的子节点 + 通知 player 重绑定
##
## 用法（挂在 Main 下）：
##   cm.setup(registry)   # 或自动加载注册表
##   cm.mount_active_to(player)  # player 启动时调用，把角色视觉挂到 player/Character
##   cm.switch_to("swat") # 切换：换视觉 + 发信号，player 收到后重绑定

## 注册表（角色清单）
var registry: CharacterRegistry = null

## 槽位字典：id → {visual: Node3D, asset: CharacterAsset}
var _slots: Dictionary = {}
## 当前激活角色 id
var active_id: String = ""

## 信号：角色切换完成（player 监听后重绑定动画库/武器/FP）
signal character_switched(char_id: String)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ensure_ready()

## 【P2 修订】幂等初始化：确保注册表已加载、第一个角色已激活。
## 场景树 _ready 顺序不保证（player 可能先于 manager 执行 _ready），
## 任何调用方在访问槽位/挂载前先调用本方法，避免空槽位。
func ensure_ready() -> void:
	if registry == null:
		var reg_resource: CharacterRegistry = load("res://resources/characters/character_registry.tres")
		if reg_resource != null:
			setup(reg_resource)
	if active_id.is_empty() and count() > 0:
		var first_id: String = registry.characters[0].id
		# 【菜单迁移】尊重主菜单「设置」里选中的角色（GameState 跨场景持久）。
		# 仅当该角色确实在注册表中才覆盖默认首项；standalone(F6) 运行则为默认首项。
		var gs := get_node_or_null("/root/GameState")
		if gs != null and gs.selected_character_id != "" and _slots.has(gs.selected_character_id):
			first_id = gs.selected_character_id
		switch_to(first_id)

## 初始化：加载注册表并预创建所有角色槽位（视觉先挂到本节点下，mount 时再 reparent）
func setup(reg: CharacterRegistry) -> void:
	registry = reg
	if registry == null:
		push_warning("CharacterManager: 注册表为空")
		return
	for asset in registry.characters:
		if asset == null or asset.id.is_empty():
			continue
		_create_slot(asset)

## 创建单个角色槽位（实例化视觉场景，先挂在 manager 下但隐藏）
func _create_slot(asset: CharacterAsset) -> void:
	var visual: Node3D = null
	if asset.character_scene != null:
		var inst: Node = asset.character_scene.instantiate()
		if inst is Node3D:
			visual = inst as Node3D
			visual.visible = false
			add_child(visual)
			# 【关键修复】槽位创建时就禁用角色自带相机（如 swat 的 PreviewCamera,
			# current=true 挂在角色正前方 4.6m）。即使角色隐藏，Camera3D.current 仍
			# 会抢走 Player 主相机的渲染权 —— 必须在创建时禁用，不能只等挂载时。
			_set_cameras_inactive(visual)
	_slots[asset.id] = {
		"visual": visual,
		"asset": asset,
	}
	if visual == null:
		push_warning("CharacterManager: 角色 %s 实例化失败（降级跳过）" % asset.id)

## 把当前激活角色的视觉 reparent 到 player/Character 挂载点下（保证唯一可见模型）。
## 其他角色视觉保持挂在 manager 下（隐藏）。player 启动/切换后调用。
func mount_active_to(player: Node) -> void:
	if active_id == "" or not _slots.has(active_id):
		return
	var mount: Node3D = player.get_node_or_null("Character") as Node3D
	if mount == null:
		push_warning("CharacterManager: player 无 Character 挂载点")
		return
	# 清空挂载点现有内容（上次挂载的角色）
	# 【修复】只释放"不属于任何槽位"的遗留节点；槽位视觉一律移回 manager 隐藏。
	# 原先无条件 queue_free：重复调用本函数时（挂载点里仍是当前激活视觉）会把
	# _slots[active_id]["visual"] 指向的对象送进释放队列 → 模型消失 + 悬空引用。
	for c in mount.get_children():
		if _slot_id_of_visual(c) != "":
			if c is Node3D:
				_stash_visual(c as Node3D)
		else:
			c.queue_free()
	# 把当前角色视觉从 manager 下移到挂载点
	var visual: Node3D = _slots[active_id]["visual"]
	if visual == null:
		return
	# 保持世界变换 reparent（角色位置=挂载点位置，通常原点）
	var parent_before: Node = visual.get_parent()
	if parent_before != null and parent_before != mount:
		parent_before.remove_child(visual)
	mount.add_child(visual)
	visual.visible = true
	visual.name = "ActiveCharacter"
	# 【关键修复】禁用角色场景自带的 Camera3D（如 swat 的 PreviewCamera, current=true
	# 挂在角色正前方 4.6m）——否则它会抢走 Player 主相机的 current，渲染用错相机
	# （表现为相机固定在角色前方/不跟随）。只保留 Player 自己的相机。
	_set_cameras_inactive(visual)

## 递归禁用子树内所有 Camera3D 的 current（保留节点但不再作为渲染相机）
func _set_cameras_inactive(n: Node) -> void:
	if n is Camera3D:
		var cam: Camera3D = n as Camera3D
		cam.current = false
	for c in n.get_children():
		_set_cameras_inactive(c)

## 【修复】该节点是否属于某个角色槽位（防止挂载清理时把槽位视觉当垃圾释放）
func _slot_id_of_visual(n: Node) -> String:
	for id in _slots:
		if _slots[id]["visual"] == n:
			return id
	return ""

## 【修复】把槽位视觉移回 manager 下并隐藏（switch_to 与 mount 清理共用）
func _stash_visual(v: Node3D) -> void:
	var p: Node = v.get_parent()
	if p != null:
		p.remove_child(v)
	add_child(v)
	v.visible = false

## 切换角色
func switch_to(char_id: String) -> void:
	if char_id == active_id:
		return
	if not _slots.has(char_id):
		push_warning("CharacterManager: 无角色 %s（降级：保持当前）" % char_id)
		return
	# 旧角色视觉：回到 manager 下并隐藏
	if active_id != "" and _slots.has(active_id):
		var cur: Node3D = _slots[active_id]["visual"]
		if cur != null:
			var mount: Node = cur.get_parent()
			if mount != null and mount.name != "" and mount != self:
				mount.remove_child(cur)
			add_child(cur)
			cur.visible = false
	# 激活新角色
	active_id = char_id
	character_switched.emit(char_id)

## 获取当前角色资产
func get_active_asset() -> CharacterAsset:
	if active_id != "" and _slots.has(active_id):
		return _slots[active_id]["asset"]
	return null

## 获取角色视觉（按 id；当前激活的可能已挂到 player 下）
func get_visual(char_id: String) -> Node3D:
	if _slots.has(char_id):
		return _slots[char_id]["visual"]
	return null

## 当前角色数
func count() -> int:
	return _slots.size()
