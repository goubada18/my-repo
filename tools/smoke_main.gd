extends SceneTree
# 整局冒烟测试：加载真实 main.tscn，运行若干帧，捕获任何运行期错误/崩溃。
func _init():
	var ps = load("res://scenes/main.tscn")
	if ps == null:
		printerr("cannot load main scene")
		quit(1)
		return
	var m = ps.instantiate()
	root.add_child(m)
	for i in range(30):
		await process_frame
	print("SMOKE_OK>>> 加载 main.tscn 并运行30帧无崩溃")
	quit(0)
