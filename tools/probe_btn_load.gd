extends SceneTree
func _init():
	var ps = load("res://scenes/player.tscn")
	print("player.tscn 加载 OK")
	var inst = ps.instantiate()
	root.add_child(inst)
	await process_frame
	print("实例化 OK")
	quit(0)
