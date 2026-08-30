extends SceneTree
## 仅做 tscn 解析 + ext_resource 解析校验（不实例化，不跑 _ready），确认副本场景链可正常加载。
func _initialize() -> void:
	var paths := [
		"res://scenes/character_preview.tscn",
		"res://scenes/player_preview.tscn",
		"res://scenes/main_preview.tscn",
	]
	var ok := true
	for p in paths:
		var res = load(p)
		if res == null:
			print("FAIL load: " + p)
			ok = false
		else:
			print("OK   load: " + p + "  (resource_type=" + res.get_class() + ")")
	print("RESULT " + ("ALL_OK" if ok else "HAS_FAIL"))
	quit(0 if ok else 1)
