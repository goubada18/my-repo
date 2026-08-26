class_name AnimationCombiner
extends RefCounted

# ============================================================
# 动画轨道合成工具
#
# 从 player.gd 抽离的纯算法层：只操作 Animation 对象与骨骼名字符串，
# 不依赖 AnimState 枚举、不依赖任何 Player 状态。
# 「哪些动画要合成」的业务表仍留在 player.gd，本类只负责「怎么合成」。
#
# 核心用途：把换弹动画的上半身骨骼轨道，与移动动画的下半身骨骼轨道
# 拼成一条新动画，从而实现「边走边换弹」。
# ============================================================


# ------------------------------------------------------------
# 轨道查找
# ------------------------------------------------------------

## 在 anim 中查找路径与类型都匹配的轨道，找不到返回 -1
static func find_track_by_path(anim: Animation, path_str: String, track_type: int) -> int:
	for i in range(anim.get_track_count()):
		if anim.track_get_type(i) == track_type and str(anim.track_get_path(i)) == path_str:
			return i
	return -1


## 判断某条轨道路径是否属于上半身骨骼
## Mixamo 轨道路径形如 "Armature/Skeleton3D:mixamorig_Spine"（带 mixamorig_ 前缀）。
## 按【带前缀骨名】做子串匹配（mixamorig_<骨名>）：
##  - 兼容子骨骼：mixamorig_LeftHandThumb1 含 mixamorig_LeftHand → 命中（与改前子串行为一致）；
##  - 精确区分脊柱：mixamorig_Spine 非 mixamorig_Spine1 子串，Spine/Spine1/Spine2 各自正确归类；
##  - 排除假想骨：mixamorig_LowerSpine 不含 mixamorig_Spine 子串 → 正确排除（原子串 find("Spine") 的隐患）。
## 兜底：非 Mixamo 的裸骨名路径（"...:Spine"）按末段精确匹配。
static func is_upper_body_track(path_str: String, upper_bones) -> bool:
	for bone_name in upper_bones:
		var full := "mixamorig_" + str(bone_name)
		if path_str.contains(full):
			return true
		# 兜底：裸骨名路径（无 mixamorig_ 前缀，如 "...:Spine"）
		if path_str.ends_with(":" + str(bone_name)) or path_str == str(bone_name):
			return true
	return false


# ------------------------------------------------------------
# 轨道复制
# ------------------------------------------------------------

## 整条复制轨道（含全部关键帧）。dst_pos 为 -1 表示追加到末尾。
static func copy_track(src: Animation, src_idx: int, dst: Animation, dst_pos: int = -1) -> int:
	var track_type := src.track_get_type(src_idx)
	var new_idx := dst.add_track(track_type, dst_pos)
	dst.track_set_path(new_idx, src.track_get_path(src_idx))
	for j in range(src.track_get_key_count(src_idx)):
		dst.track_insert_key(
			new_idx,
			src.track_get_key_time(src_idx, j),
			src.track_get_key_value(src_idx, j),
			src.track_get_key_transition(src_idx, j)
		)
	return new_idx


## 复制轨道，但只保留 max_time 之前的关键帧（用于把长动画裁到过渡动画时长）
static func copy_track_clipped(src: Animation, src_idx: int, dst: Animation, max_time: float) -> int:
	var track_type := src.track_get_type(src_idx)
	var new_idx := dst.add_track(track_type, -1)
	dst.track_set_path(new_idx, src.track_get_path(src_idx))
	for j in range(src.track_get_key_count(src_idx)):
		var time: float = src.track_get_key_time(src_idx, j)
		if time > max_time + 0.001:
			break
		dst.track_insert_key(
			new_idx,
			time,
			src.track_get_key_value(src_idx, j),
			src.track_get_key_transition(src_idx, j)
		)
	return new_idx


## 循环复制轨道以填满 target_length。
## 用于让 1 秒的行走循环铺满 3.5 秒的换弹时长，避免下半身在中途定格。
static func copy_looping_track_to_fill(src: Animation, src_idx: int, dst: Animation, target_length: float) -> int:
	var track_type := src.track_get_type(src_idx)
	var new_idx := dst.add_track(track_type)
	dst.track_set_path(new_idx, src.track_get_path(src_idx))

	var key_count := src.track_get_key_count(src_idx)
	var src_length := src.length
	if key_count < 2 or src_length <= 0.01:
		# 关键帧不足或时长过短，无从循环，退化为复制一次
		for j in range(key_count):
			dst.track_insert_key(
				new_idx,
				src.track_get_key_time(src_idx, j),
				src.track_get_key_value(src_idx, j),
				src.track_get_key_transition(src_idx, j)
			)
		return new_idx

	# +1 是为了铺满尾部余量，多出的关键帧会被 target_length 判据截断
	var repeats: int = int(ceil(target_length / src_length)) + 1
	for r in range(repeats):
		var time_offset: float = r * src_length
		for j in range(key_count):
			var new_time: float = src.track_get_key_time(src_idx, j) + time_offset
			if new_time > target_length + 0.001:
				break
			dst.track_insert_key(
				new_idx,
				new_time,
				src.track_get_key_value(src_idx, j),
				src.track_get_key_transition(src_idx, j)
			)
	return new_idx


# ------------------------------------------------------------
# 合成
# ------------------------------------------------------------

## 循环填充式合成：适用于「边移动边换弹」。
## 成品长度 = 上半身动画长度；下半身轨道循环铺满该长度。
static func combine_looping(upper_anim: Animation, lower_anim: Animation, upper_bones) -> Animation:
	var combined := Animation.new()
	combined.length = upper_anim.length
	combined.loop_mode = Animation.LOOP_NONE  # 一次性动画

	# 下半身（以及一切非上半身轨道）：循环铺满整个时长
	for i in range(lower_anim.get_track_count()):
		if not is_upper_body_track(str(lower_anim.track_get_path(i)), upper_bones):
			copy_looping_track_to_fill(lower_anim, i, combined, combined.length)

	# 上半身：直接取自换弹动画，本身已覆盖整个时长
	_merge_upper_tracks(upper_anim, combined, upper_bones, -1.0)
	return combined


## 过渡式合成：适用于「换弹途中蹲下/起立」。
## 成品长度 = 下半身过渡动画长度；上半身轨道裁剪到该长度。
static func combine_transition(upper_anim: Animation, lower_anim: Animation, upper_bones) -> Animation:
	var combined := Animation.new()
	combined.length = lower_anim.length
	combined.loop_mode = Animation.LOOP_NONE

	# 下半身过渡动画：原样复制一次，不循环
	for i in range(lower_anim.get_track_count()):
		if not is_upper_body_track(str(lower_anim.track_get_path(i)), upper_bones):
			copy_track(lower_anim, i, combined, -1)

	# 上半身：裁剪到过渡时长
	_merge_upper_tracks(upper_anim, combined, upper_bones, combined.length)
	return combined


## 把 upper_anim 的上半身轨道并入 dst，跳过已存在的同路径轨道。
## clip_to < 0 表示整条复制，否则裁剪到该时长。
static func _merge_upper_tracks(upper_anim: Animation, dst: Animation, upper_bones, clip_to: float) -> void:
	for i in range(upper_anim.get_track_count()):
		var path_str := str(upper_anim.track_get_path(i))
		if not is_upper_body_track(path_str, upper_bones):
			continue
		# 下半身动画可能也带同名骨骼轨道，已存在则不覆盖
		if find_track_by_path(dst, path_str, upper_anim.track_get_type(i)) >= 0:
			continue
		if clip_to < 0.0:
			copy_track(upper_anim, i, dst, -1)
		else:
			copy_track_clipped(upper_anim, i, dst, clip_to)


# ------------------------------------------------------------
# 安装与清理
# ------------------------------------------------------------

## 把合成好的动画注册进 AnimationPlayer 的默认库（同名则替换）
static func install(anim_player: AnimationPlayer, anim_name: String, anim: Animation) -> bool:
	if anim_name.is_empty() or anim_player == null or not is_instance_valid(anim_player):
		return false
	var lib := anim_player.get_animation_library("")
	if lib == null:
		lib = AnimationLibrary.new()
		anim_player.add_animation_library("", lib)
	# 【崩溃防护·关键】若该动画当前正在播放，直接 remove_animation 会让 AnimationPlayer
	# 内部 track 缓存(_update_caches)访问悬空指针 → 崩溃。先停播再替换，避免 dangling。
	if lib.has_animation(anim_name):
		if anim_player.current_animation == anim_name:
			anim_player.stop()
		lib.remove_animation(anim_name)
	lib.add_animation(anim_name, anim)
	return true


## 移除动画中的全部 3D 位置轨道，返回移除数量。
## Mixamo 的 Hips 位置轨道处于错误坐标系，保留会导致闪现；
## 角色位移交由 CharacterBody3D 物理负责，动画只管姿态。
static func strip_position_tracks(anim: Animation) -> int:
	var removed := 0
	for i in range(anim.get_track_count() - 1, -1, -1):
		if anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
			anim.remove_track(i)
			removed += 1
	return removed
