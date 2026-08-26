class_name SprintBurst
extends Ability
## 示例能力（P3 框架验证）：冲刺爆发——按 Q 触发，短时间加速移动（不依赖新动画，
## 纯逻辑可验证 Ability 调度器闭环）。实际游戏中可替换为翻滚/滑铲等带动画的能力。

## 爆发时长（秒）
@export_range(0.1, 2.0) var burst_duration: float = 1.2
## 爆发倍速（相对普通移动）
@export_range(1.2, 3.0) var speed_multiplier: float = 2.0
## 爆发冷却（秒）
@export_range(0.0, 5.0) var cooldown: float = 1.5

var _elapsed: float = 0.0
var _cool_timer: float = 0.0

func _init() -> void:
	id = "sprint_burst"

## 可激活条件：在地面、非死亡、非换弹/过渡/一次性覆盖中、冷却已结束
func can_activate(player: Node) -> bool:
	if is_active or _cool_timer > 0.0:
		return false
	if player.get("is_dead") or player.get("is_transitioning") or player.get("_is_in_one_shot_override") or player.get("is_crouching"):
		return false
	return true

func activate(player: Node) -> void:
	super(player)
	_elapsed = 0.0
	player.set("_ability_speed_mult", speed_multiplier)

func update(player: Node, delta: float) -> bool:
	_elapsed += delta
	if _elapsed >= burst_duration:
		return false   # 结束 → player 调 finish
	return true

func finish(player: Node) -> void:
	super(player)
	player.set("_ability_speed_mult", 1.0)
	_cool_timer = cooldown

## player 每帧调用：推进冷却（不激活时）
func tick_cooldown(delta: float) -> void:
	if _cool_timer > 0.0:
		_cool_timer = maxf(0.0, _cool_timer - delta)
