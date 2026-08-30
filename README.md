# RushFire（奔赴火线）

Godot 4.7 第三人称 FPS 动作测试 Demo：2 角色（飞虎队 / SWAT）× 5 武器（AK47 / 沙漠之鹰 / 尼泊尔军刀 / 高爆手雷 / M82A1）× 第一/第三人称切换，Mixamo 动画体系，含完整的启动预加载与菜单流程。

## 运行

用 Godot 4.7 打开本项目（含 `project.godot` 的目录），F5 运行。主入口 `scenes/boot.tscn`（预加载进度条）→ 主菜单 → `main_multichar.tscn`。

## 操作

| 输入 | 功能 |
|---|---|
| WASD / Shift | 移动 / 奔跑（地面奔跑禁射） |
| 空格 / Ctrl | 跳跃 / 蹲伏（peek 与长按两种模式） |
| 鼠标左键 / 右键 | 开火（近战=轻击 / 重击·刺刀·开镜） |
| 1-5 | 武器直选：1=AK47 2=沙漠之鹰 3=尼泊尔 4=高爆 5=M82A1 |
| Q / R | 上一把武器 / 换弹 |
| V | 第一/第三人称切换 |
| K | 死亡后手动复活（`death` action，可用 K 自杀） |
| 反引号(`) | 长按自由视角 |

## 架构速览

- `scripts/player.gd` — 玩家控制器（动画状态机 + 输入 + 武器/开镜/换弹调度）
- `scripts/weapon_system.gd` + `resources/weapons/*.tres` — 武器数据驱动（`WeaponDef`：`weapon_type`/`fire_mode`/`scopable`/音效/FP 动画映射，加新武器不改代码）
- `scripts/character_manager.gd` + `resources/characters/*.tres` — 角色注册表与热切换
- `scripts/weapon_rig.gd` — 3P 世界枪每帧握持对齐（跨骨架缩放换算 `0.00026/骨架scale`）
- `scripts/fp_viewmodel_player.gd` + `fp_viewmodel/` — 第一人称视图模型（挂相机下、运行时烘焙动作、镜像 scale.z=-1）
- `scripts/animation_combiner.gd` — 换弹/挥刀的上半身×下半身合成
- `scripts/audio_wav_loader.gd` — 运行时 RIFF WAV 解析（音效统一 `.dat`，绕开 Godot BWF 导入崩溃）

详细设计文档见 `docs/`；开发史与踩坑记录见 `.workbuddy/memory/`（不入库）。

## 加新武器 / 新角色

- **新武器**：放一个 `WeaponDef .tres`（填 `weapon_type`/`fire_mode`/`scopable`/音效 `.dat` 路径/`fp_anim_map`），角色资产 `weapons` 列表加一项，`WEAPON_SLOT_IDS`（player.gd 头部）按需挂槽位。音效一律 `.dat`（标准 PCM 16-bit 直接改名），**不要用 `.wav`**（会被导入器接管，导出后运行时解析不到）。
- **新角色**：`tools/build_character_asset.gd` 表格加一行生成角色资产，进 `character_registry.tres`。

## 工具与验证

- `tools/smoke_main.gd` / `tools/smoke_multichar.gd` — headless 冒烟：
  `godot --headless --path . --script res://tools/smoke_multichar.gd`
  输出必须 grep 检查 `Parse Error` / `SCRIPT ERROR`。
- `tools/verify_all.gd` — 12 项验收门禁。
- `tools/archive/` — 历史一次性脚本（重跑会覆盖手工场景，勿执行）。

## 已知取舍与遗留（截至 2026-08-30 修复批次）

- FP 低头穿地：三种方案均评估过，定案接受现状。
- v_deagle / 尼泊尔 / 手雷暂无声效（`silent=true`，等专属音频）；换弹声 pitch 残差 ~1.02×。
- 持 AK 待机手臂姿势（`mixamo_lib.tres` 手臂轨道历史污染）：需从 git 历史
  `git show 13a455ac:resources/mixamo_lib.tres.bak_pre_rifle_fix` 取回原始轨道做外科手术，涉及视觉验证。
- 手雷仅做到"持有/投掷/动作"，爆炸表现与数量系统未做；能力框架（Q）已搭好但未接输入入口。
- Intel Iris Xe 上停止播放/关窗口偶发 Vulkan 崩溃（负缩放蒙皮网格触发，未根除）。
