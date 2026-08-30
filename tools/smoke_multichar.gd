extends SceneTree
# 整局冒烟测试（多角色主场景）：加载真实 main_multichar.tscn，运行若干帧，
# 捕获任何运行期错误/崩溃。与 smoke_main.gd 配对：后者跑 main.tscn。
func _init():
	var ps = load("res://scenes/main_multichar.tscn")
	if ps == null:
		printerr("cannot load main_multichar scene")
		quit(1)
		return
	var m = ps.instantiate()
	root.add_child(m)
	for i in range(60):
		await process_frame
	print("SMOKE_OK>>> 加载 main_multichar.tscn 并运行60帧无崩溃")
	quit(0)
