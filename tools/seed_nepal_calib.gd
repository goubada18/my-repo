extends SceneTree
## 一次性工具：播种尼泊尔刀每角色标定资源（从旧全局常量 + k 换算精确推导）。
## 运行一次即可；此后由标定场景 scenes/nepal_knife_calib.tscn 维护。
## 生成：
##   resources/characters/nepal_knife_calib_feihu.tres  （k=1，= 旧全局常量原值）
##   resources/characters/nepal_knife_calib_swat.tres   （k=0.00026/0.013795，= 旧运行时实际值）
## 播种后游戏内刀位与改动前完全一致（行为零变化）。

const SRC_LOCAL_POS := Vector3(1285.234375, -185.922363, -1347.628662)
const SRC_LOCAL_ROT := Quaternion(-0.301986, -0.627026, -0.380828, 0.608780)
const SRC_LOCAL_SCALE := Vector3(17307.695313, 17307.693359, 17307.695313)
const FEIHU_SCALE := 0.00026
const SWAT_SCALE := 0.013795

func _init() -> void:
	_seed("feihu", 1.0, "res://resources/characters/nepal_knife_calib_feihu.tres",
		"飞虎队（A 空间）右手骨骼局部系。由旧全局常量原值播种（k=1）。")
	_seed("swat", FEIHU_SCALE / SWAT_SCALE, "res://resources/characters/nepal_knife_calib_swat.tres",
		"SWAT（N 空间）右手骨骼局部系。由旧全局常量 ×k 播种（k=0.00026/0.013795），与改动前运行时刀位一致。")
	quit(0)

func _seed(char_id: String, k: float, path: String, note: String) -> void:
	# headless 下全局类缓存不含新 class_name → 显式 load 脚本（项目已知坑，见 player.gd 头部注释）
	var CalibScript: GDScript = load("res://scripts/nepal_knife_calib.gd")
	var c: Resource = CalibScript.new()
	c.local_pos = SRC_LOCAL_POS * k
	c.local_rot = SRC_LOCAL_ROT
	c.local_scale = SRC_LOCAL_SCALE * k
	c.bone_name = "mixamorig_RightHand"
	c.note = note
	var err := ResourceSaver.save(c, path)
	print("seed %s -> %s (err=%d) pos=%s scale=%s" % [char_id, path, err, str(c.local_pos), str(c.local_scale)])
