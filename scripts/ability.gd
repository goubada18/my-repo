class_name Ability
extends RefCounted
## 能力基类（P3）：把"新动作逻辑"做成独立脚本类，player.gd 只留统一激活入口。
## 新能力 = 继承本类 + 实现 can_activate/activate/update/finish，注册到 player._abilities。
##
## 生命周期：
##   player 每帧调用 try_activate() → can_activate() 决定能否触发 → activate() 启动
##   → update(delta) 返回 true 表示进行中（player 每帧调用）→ finish() 收尾
##   （can_activate 需排除"已在激活中"，防止重复触发）

## 能力唯一标识
var id: String = ""
## 激活中的能力由 player 调用 update/finish（不要自己管理状态机外的东西）
var is_active: bool = false

## 能否激活（player 在每帧/输入时调用；应检查玩家状态：在地面/不换弹/不死亡等）
func can_activate(player: Node) -> bool:
	return false

## 激活（player 调用；实现里设置 is_active=true 并做启动动作）
func activate(player: Node) -> void:
	is_active = true

## 每帧更新（player 在 is_active 时调用）。返回 false 表示本次更新后已结束（player 会调 finish）
func update(player: Node, delta: float) -> bool:
	return is_active

## 每帧推进（player 对所有已注册能力每帧调用，无论是否激活）。
## 【修复】冷却推进原先定义在 SprintBurst 子类，player 只能类型特判调用，
## 违背本类"新能力=继承+注册"的开放封闭承诺。会话外状态（冷却等）放这里，
## 激活中的逐帧逻辑放 update()。
func tick(player: Node, delta: float) -> void:
	pass

## 收尾（player 在 update 返回 false 时调用；实现里复位 is_active）
func finish(player: Node) -> void:
	is_active = false
