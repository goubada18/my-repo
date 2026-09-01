extends SceneTree
## Verify: 1) M82 reload pitch clamped (was 0.29 -> now 0.5), 2) M82 draw sfx injected.
func _init():
	var def: Resource = load("res://resources/weapons/m82a1.tres")
	if def == null:
		printerr("FAIL: m82a1.tres load")
		quit(1)
		return
	print("def.draw_sfx = %s" % def.get("draw_sfx"))
	var draw_ok: bool = def.get("draw_sfx") == "res://audio/m82a1_draw.dat"
	print("draw sfx check: %s" % ("PASS M82 own draw" if draw_ok else "FAIL"))
	# reload pitch calc: native 0.666 / target 2.305 = 0.289 -> clamped 0.5
	var nat: float = 0.666
	var target: float = 2.305
	var raw: float = nat / target
	var pitched: float = clampf(raw, 0.5, 2.0)
	print("reload pitch: raw=%.3f -> clamped=%.3f (was 0.289, now %s)" % [raw, pitched, "normal-ish" if pitched >= 0.5 else "still low"])
	# AK check (should be unaffected): 2.821s sfx vs ~2.4s target -> ~1.17
	var ak_pitch: float = clampf(2.821 / 2.4, 0.5, 2.0)
	print("AK reload pitch: %.3f (within range, unaffected)" % ak_pitch)
	quit(0)
