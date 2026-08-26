extends SceneTree
## P2/P4 通用资产生成工具：为每个角色定义生成 CharacterAsset + 注册表。
## 角色定义表 _CHARACTERS 每加一行 = 一个新角色（P4 流水线核心）。
## 用法：godot --headless --path <proj> --script tools/build_character_asset.gd
## 产出：
##   resources/characters/<id>.tres          （CharacterAsset）
##   resources/characters/character_registry.tres（注册表，全角色）

const OUT_DIR := "res://resources/characters"
const REGISTRY := OUT_DIR + "/character_registry.tres"
## 【P4】AnimClip 管线目录：放 AnimClip .tres 到这里，build 时自动换算进各角色扩展库
const ACTIONS_DIR := "res://resources/actions"

## 角色定义表：加新角色在这里加一行即可
## 字段：id, 显示名, 视觉场景, 动画库, 武器配置(可为空=用默认+运行时自适应), FP模型(可空),
##       skeleton_scale=骨架空间缩放（weapon_rig 握持偏移换算标定；飞虎队 A 空间 0.00026，
##       SWAT N 空间 0.013795；新角色按各自 Armature scale 填）
const CHARACTERS: Array = [
	{
		"id": "feihu",
		"display_name": "飞虎队",
		"scene": "res://scenes/character.tscn",
		"anim_lib": "res://resources/mixamo_lib.tres",
		"weapon_cfg": "res://resources/weapon_rig_config.tres",
		"fp_scene": "",
		"skeleton_scale": 0.00026,
	},
	{
		"id": "swat",
		"display_name": "新SWAT",
		"scene": "res://scenes/character_preview.tscn",
		"anim_lib": "res://resources/mixamo_lib_swat.tres",
		"weapon_cfg": "res://resources/weapon_rig_config.tres",
		"fp_scene": "",
		"skeleton_scale": 0.013795,
	},
]

var _buf: PackedStringArray = PackedStringArray()

func _log(s: String) -> void:
	_buf.append(s)

func _flush() -> void:
	for s in _buf:
		print(s)

func _ensure_dir() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

## 从 player.gd 提取 ANIM_NAMES 生成 anim_map（各角色逻辑状态一致）
func _extract_anim_map() -> Dictionary:
	var player_src := FileAccess.open("res://scripts/player.gd", FileAccess.READ)
	if player_src == null:
		_log("!! 无法读取 player.gd")
		return {}
	var text: String = player_src.get_as_text()
	player_src.close()
	var start := text.find("const ANIM_NAMES")
	var dict_start := text.find("{", start)
	var depth := 0
	var dict_end := -1
	for i in range(dict_start, text.length()):
		var ch := text[i]
		if ch == "{":
			depth += 1
		elif ch == "}":
			depth -= 1
			if depth == 0:
				dict_end = i
				break
	if dict_start < 0 or dict_end < 0:
		return {}
	var block := text.substr(dict_start, dict_end - dict_start + 1)
	var anim_map := {}
	for line in block.split("\n"):
		var m := line.strip_edges()
		if m.begins_with("AnimState.") and m.contains(":"):
			var colon := m.find(":")
			var key := m.substr(0, colon).replace("AnimState.", "").strip_edges()
			var v := m.substr(colon + 1).strip_edges()
			if v.ends_with(","):
				v = v.substr(0, v.length() - 1)
			v = v.strip_edges()
			if v.begins_with("\"") and v.ends_with("\""):
				anim_map[key] = v.substr(1, v.length() - 2)
	return anim_map

func _build_asset(def: Dictionary) -> CharacterAsset:
	var asset := CharacterAsset.new()
	asset.id = def["id"]
	asset.display_name = def.get("display_name", def["id"])
	asset.character_scene = load(def["scene"])
	asset.anim_lib = load(def["anim_lib"])
	asset.anim_map = _extract_anim_map()
	asset.extra_anim_lib = null  # AnimClip 扩展库在 _initialize 里异步生成后填充
	var wc_path: String = def.get("weapon_cfg", "")
	# 【100%换皮】为每个角色生成【专属】握持配置（写入 skeleton_space_scale 标定），
	# 使握持偏移换算完全数据驱动：weapon_rig 读 config.skeleton_space_scale 换算，
	# 不再用骨架测量推断。生成文件 resources/characters/weapon_cfg_<id>.tres。
	var skel_scale: float = def.get("skeleton_scale", 0.00026)
	if wc_path != "" and ResourceLoader.exists(wc_path):
		var base_cfg: WeaponRigConfig = load(wc_path) as WeaponRigConfig
		var own_cfg: WeaponRigConfig = base_cfg.duplicate(true) if base_cfg != null else WeaponRigConfig.new()
		own_cfg.skeleton_space_scale = skel_scale
		var own_path: String = OUT_DIR + "/weapon_cfg_%s.tres" % def["id"]
		var err: int = ResourceSaver.save(own_cfg, own_path)
		if err != OK:
			_log("!! 保存武器配置失败 %s err=%d" % [own_path, err])
		asset.weapon_rig_config = load(own_path)
		_log("  [%s] 专属武器配置 skeleton_scale=%.6f → %s" % [def["id"], skel_scale, own_path])
	elif wc_path != "" and ResourceLoader.exists(wc_path):
		asset.weapon_rig_config = load(wc_path)
	var fp_path: String = def.get("fp_scene", "")
	if fp_path != "" and ResourceLoader.exists(fp_path):
		asset.fp_viewmodel_scene = load(fp_path)
	asset.skeleton_profile = BoneProfile.new()
	# 物理参数：SWAT 与飞虎队体型近似，暂用同一套（P2 后可每角色微调）
	asset.eye_height = 1.7
	asset.standing_height = 1.8
	asset.crouching_height = 1.1
	asset.capsule_radius = 0.45
	# 【P3】可装备武器清单（WeaponDef 资产；以后加武器 = 生成 WeaponDef + 这里加一项）
	var wpns: Array = def.get("weapons", ["res://resources/weapons/ak47.tres"])
	asset.weapons = []
	for w in wpns:
		if ResourceLoader.exists(w):
			asset.weapons.append(load(w))
	return asset

func _collect_nodes(n: Node, out: Array = []) -> Array:
	out.append(n)
	for c in n.get_children():
		_collect_nodes(c, out)
	return out

## 角色目标动画空间：按 skeleton_scale 判定（0.00026=A 飞虎千位级；>0.001=N SWAT 百位级）
func _char_space(def: Dictionary) -> String:
	var s: float = def.get("skeleton_scale", 0.00026)
	return "N" if s > 0.001 else "A"

## 加载角色场景骨架的 {骨名: rest 局部 Transform}（AnimClip 换算子骨 position 用）
func _load_rests_async(scene_path: String) -> Dictionary:
	var d := {}
	if not ResourceLoader.exists(scene_path):
		return d
	var inst: Node = load(scene_path).instantiate()
	root.add_child(inst)
	await process_frame
	await process_frame
	var skel: Skeleton3D = null
	for n in _collect_nodes(inst):
		if n is Skeleton3D:
			skel = n
			break
	if skel:
		for i in range(skel.get_bone_count()):
			d[skel.get_bone_name(i)] = skel.get_bone_rest(i)
	inst.queue_free()
	return d

## 从源动画场景提取第一个 Animation（actor/*.glb 等 → AnimationPlayer → 首个动画）
func _load_source_anim(source_fbx: String) -> Animation:
	if not ResourceLoader.exists(source_fbx):
		return null
	var ps: PackedScene = load(source_fbx)
	if ps == null:
		return null
	var inst: Node = ps.instantiate()
	root.add_child(inst)
	await process_frame
	await process_frame
	var ap: AnimationPlayer = null
	for n in _collect_nodes(inst):
		if n is AnimationPlayer:
			ap = n as AnimationPlayer
			break
	var anim: Animation = null
	if ap != null and ap.get_animation_list().size() > 0:
		anim = ap.get_animation(ap.get_animation_list()[0])
	inst.queue_free()
	return anim

## 【P4】AnimClip 管线：扫描 ACTIONS_DIR 的 AnimClip 资产，把 source_fbx 源动画
## 自动换算到当前角色空间，生成扩展库 anim_clips_<id>.tres + 返回新映射。
## 返回 { "lib": AnimationLibrary, "map": {逻辑状态: 动画名} }（无 clip 时 lib=null）
func _process_anim_clips(def: Dictionary) -> Dictionary:
	var dst_space: String = _char_space(def)
	var out := { "lib": null, "map": {} }
	var dir := DirAccess.open(ACTIONS_DIR)
	if dir == null:
		return out  # 无 actions 目录 = 无新动作，正常
	var dst_rest: Dictionary = await _load_rests_async(def["scene"])
	var lib := AnimationLibrary.new()
	var new_map := {}
	var files: Array = dir.get_files()
	files.sort()
	for fname in files:
		if not fname.ends_with(".tres"):
			continue
		var clip: AnimClip = load(ACTIONS_DIR + "/" + fname)
		if clip == null or clip.source_fbx.is_empty():
			continue
		var src_anim: Animation = await _load_source_anim(clip.source_fbx)
		if src_anim == null:
			_log("  !! [%s] AnimClip %s 源动画加载失败 %s" % [def["id"], clip.id, clip.source_fbx])
			continue
		var src_space: String = AnimConvertLib.detect_space(src_anim)
		var conv: Animation = src_anim.duplicate(true)
		if src_space == "":
			_log("  !! [%s] %s 空间无法自动检测（无 Hips position 轨道）→ 原样加入" % [def["id"], clip.id])
		elif src_space != dst_space:
			AnimConvertLib.convert_anim(conv, src_space, dst_space, dst_rest)
			_log("  [%s] %s: %s→%s 已换算" % [def["id"], clip.id, src_space, dst_space])
		else:
			_log("  [%s] %s: 同空间(%s) 直接加入" % [def["id"], clip.id, src_space])
		var anim_name: String = clip.anim_name if not clip.anim_name.is_empty() else clip.id
		lib.add_animation(anim_name, conv)
		if not clip.logical_state.is_empty():
			new_map[clip.logical_state] = anim_name
	if lib.get_animation_list().size() > 0:
		var out_path: String = OUT_DIR + "/anim_clips_%s.tres" % def["id"]
		var err: int = ResourceSaver.save(lib, out_path)
		_log("  [%s] AnimClip 扩展库 %d 动画 → %s err=%d" % [def["id"], lib.get_animation_list().size(), out_path, err])
		out["lib"] = lib
		out["map"] = new_map
	return out

func _initialize() -> void:
	_log("=== 通用资产生成（%d 个角色）===" % CHARACTERS.size())
	_ensure_dir()
	var anim_map := _extract_anim_map()
	_log("anim_map 状态数=%d" % anim_map.size())
	# 读旧注册表（保留其他角色）
	var reg: CharacterRegistry = null
	if ResourceLoader.exists(REGISTRY):
		reg = load(REGISTRY) as CharacterRegistry
	if reg == null:
		reg = CharacterRegistry.new()
	for def in CHARACTERS:
		var cid: String = def["id"]
		var asset := _build_asset(def)
		# 【P4】AnimClip 管线：新动作自动换算进本角色扩展库 + 映射合并
		var clips: Dictionary = await _process_anim_clips(def)
		if clips["lib"] != null:
			asset.extra_anim_lib = clips["lib"] as AnimationLibrary
			for st in clips["map"]:
				asset.anim_map[st] = clips["map"][st]
		var err := ResourceSaver.save(asset, OUT_DIR + "/" + cid + ".tres")
		_log("生成 %s.tres err=%d" % [cid, err])
		# 合并进注册表（去重）
		var exists := false
		for i in range(reg.characters.size()):
			if reg.characters[i] != null and reg.characters[i].id == cid:
				reg.characters[i] = asset
				exists = true
		if not exists:
			reg.characters.append(asset)
	var err2 := ResourceSaver.save(reg, REGISTRY)
	_log("保存注册表 err=%d（角色数=%d）" % [err2, reg.characters.size()])
	# 回读校验
	var back: CharacterRegistry = load(REGISTRY)
	if back == null:
		_log("!! 注册表回读失败")
		_flush()
		quit(1)
	for c in back.characters:
		if c != null:
			_log("回读：%s anim_map=%d" % [c.id, c.anim_map.size()])
	# 【P4 自检熔断】加载链完整性 + anim_map 动画存在性。
	# 任一角色资产缺关键资源 / 动画缺失 → FAIL（坏资产拒绝入库，需修后再生成）。
	var fail := 0
	# 合成动画状态（_combine_animations 运行时生成，库里无需存在）
	var synth_states := [
		"RELOAD_WALK_FORWARD", "RELOAD_WALK_BACKWARD", "RELOAD_STRAFE_LEFT", "RELOAD_STRAFE_RIGHT",
		"RELOAD_CROUCH_WALK_FORWARD", "RELOAD_CROUCH_WALK_BACKWARD",
		"RELOAD_CROUCH_STRAFE_LEFT", "RELOAD_CROUCH_STRAFE_RIGHT",
		"RELOAD_CROUCH_IDLE", "RELOAD_STAND_TO_CROUCH", "RELOAD_CROUCH_TO_STAND"]
	for c in back.characters:
		if c == null:
			fail += 1
			_log("  !! 注册表含 null 角色")
			continue
		var cid: String = c.id
		if c.character_scene == null:
			fail += 1
			_log("  !! %s: 视觉场景为空" % cid)
		if c.anim_lib == null:
			fail += 1
			_log("  !! %s: 动画库为空" % cid)
		if c.weapon_rig_config == null:
			fail += 1
			_log("  !! %s: 武器握持配置为空" % cid)
		if c.weapons.is_empty():
			fail += 1
			_log("  !! %s: 无可装备武器" % cid)
		var missing_anims := []
		for st in c.anim_map:
			if st in synth_states:
				continue
			var an: String = c.anim_map[st]
			if an.is_empty():
				missing_anims.append(st)
			elif c.anim_lib != null and not c.anim_lib.has_animation(an):
				missing_anims.append(st + "→" + an)
		if missing_anims.size() > 0:
			fail += 1
			_log("  !! %s: 动画缺失 %s" % [cid, str(missing_anims)])
	if fail == 0:
		_log("=== 自检: ALL_OK（%d 角色全部通过）===" % back.characters.size())
	else:
		_log("=== 自检: FAIL %d（坏资产拒绝入库，请修复后重新生成）===" % fail)
	_log("DONE")
	_flush()
	quit(1 if fail > 0 else 0)
