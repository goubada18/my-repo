# 项目记忆 — TPP_FPS_Action_Demo（Godot 4.7 TPP+FP 射击 Demo）
> 新增代码前先读本文件 + 相关源码。深度报告：`代码架构深度分析报告.html` `项目分析报告.html`。

## 1. 定位
TPP+FP（V 键切换）Mixamo 动画测试 Demo。资产：Mixamo 角色(`resources/mixamo_lib.tres`)、AK47 GLB。main_scene=`res://scenes/main.tscn`(飞虎队)；多角色入口 `scenes/main_multichar.tscn`。

## 2. 架构 + 时序（硬依赖）
- `Player`(CharacterBody3D,`player.gd`) 上帝类：动画状态机+物理+输入+子系统驱动+上下半身合成。
- 子系统：`CameraController`(@tool,`$CameraPivot`)、`WeaponRig`、`FPActionRetarget`(3P 双臂+世界枪)、`FPViewmodelPlayer`(挂相机下)、`AnimationCombiner`/`AnimationDiagnostics`(RefCounted)。
- **每帧时序**：`CameraController._process`→`AnimationPlayer`→`Player._process`(PRIORITY=10)：`_apply_torso_pitch_overlay`→`_fp_action.update`→`_weapon_rig.update`→`_fp_vm.update`。priority>10 会脱手。子系统无 `_process`，全手动 update。
- `pitch` 正=低头(`camera_controller.gd` L121/L160)；角色朝 +Z(非 Godot 默认 −Z)。` ` 键 = 自由观察视角(`KEY_QUOTELEFT`)：相机绕角色任意角度、角色朝向与 `pitch` 冻结。

## 3. 多角色/武器/能力（已落地）
`CharacterManager`+`CharacterAsset`+`CharacterRegistry`+`AnimationDirector`+`CharacterSwitchController`(1/2)；`WeaponSystem`+`WeaponDef`；`Ability` 基类+`sprint_burst.gd`。

## 4. 代码规范
GDScript；中文注释+`##`；PascalCase 类 / snake_case 变量 / SCREAMING_SNAKE 常量。`@export` 标定；`@tool` 须 `Engine.is_editor_hint()` 早退。勿跑 `setup_anim_lib.gd`/`setup_project.gd`。

## 5. 复用点
- 骨骼世界→`skel.global_transform*skel.get_bone_global_pose(idx)`；合成→`AnimationCombiner.*`。
- 换弹声(`audio/AK47-HQL_RELOAD.dat`)时长 `_recompute_reload_duration()`(FP+3P 均值)→`pitch_scale`；WAV→`AudioWavLoader.load_wav`。
- 复位：`_reset_all_locks`/`_reset_fp_state`/`_finish_reload_flexible`。

## 6. 已知 BUG/风险（已修）
- **#10 枪身近竖直 roll 退化**：`_align_axis_to_dir` 混入 `fwd`(char_basis.z) 参考，探针证 roll 连续，画面需目测。
- **换弹声三坑+蹲键误换弹**（已修）：站蹲过渡分支"换弹短路块"缩进错+残留 `_reload_input_buffer`；收回到 reload `if` 内、蹲下起步清 buffer、切角色 `_recompute_reload_duration` 共用。验证 `probe_reload_pitch`/`probe_crouch_fix_verify`。
- **刺刀手臂残留拉长**（已修）：`_translate_bone` 改以 `get_bone_rest().origin` 为基准(thrust→0 必回 rest)；`_reset_arms()` 收尾。肩骨平移版：`_translate_arms` 沿 +Z(非 −Z)。
- **刺刀俯仰·肩膀上翘 + 自由观察视角翻转（2026-08-15→16 修复·已实证）**：
  - 根因1(上翘)：3P 前刺取水平 `char_basis.z`，低头时投影屏幕变"向上"。修：传 `aim_forward`(相机视线 `-camera.basis.z`)。
  - 根因2(前后反)：`aim_forward` 取自 `-camera.basis.z`，**自由观察(`键)下相机绕到正面时 `-camera.basis.z=−Z`(角色身后)**，刺刀看似前后反/随观察视角变。修：`player.gd` 改算 `aim_forward = 角色水平前向(char_basis.z) 绕右轴 按 pitch 俯仰`（=角色枪口实际瞄准，与观察者相机无关；普通/FP 视角等价 `-camera.basis.z`）。`fp_action_retarget.gd` 增诊断 `_last_trans`。
  - 验证 `tools/probe_debug_freelook.gd`：普通/正面/侧面/平头自由观察 全部 aim=(0,−0.565,+0.825)、trans 前+0.215 上−0.147（恒 +Z 前向，不再翻 −Z/侧 +X）。`tools/probe_debug_aim.gd` 用 `_last_trans` 去噪核对（骨位差测量有 rest 基线漂移噪声，勿信）。
- **M82A1 P0 接入·"看不到枪"（2026-08-16 最终修复·已实证）**：三轮误诊（短轴缩放太小/改静态网格/单位错位）后，用 `probe_vm_world.gd` 忠实复刻 setup() 找到真根因：
  - 根因A：**单位体系错位**——M82 raw 172.4 单位在 Godot 只渲染 116mm（AK47 同 raw 却 1898mm），按 AK raw 对齐得到 5cm 枪。修：Godot 修正系数 → M82 raw 长轴须 2820 单位（k≈2709）。
  - 根因B：**SourceIO 覆写同名手**——M82 导入把 `hands__CSO_Hand_Male` 顶点换成 4.5 单位小手。修：**先导入 M82 后导入 AK47**（隔离）。
  - 根因C：**剥离蒙皮 → glTF 导出移出 Skeleton3D → 74m 错位**。修：保留蒙皮 + 权重传递（`data_transfer` VGROUP_WEIGHTS）从 AK47 原枪转给 M82 枪。
  - 终版 `tools/_blender_reskin_v9.py`：枪 1.9m/正确位置/有效蒙皮，手 AK47 原样，PLAY_OK（probe_m82a1_play.gd）。详见 §8.5。

## 7. 验证铁律
- 改完 grep 全输出查 `Parse Error`/`Compilation failed`(headless 增量 reload 偶发伪报错)。
- 三元 `var x := a if c else b` 报"Cannot infer type"→显式 `var x: T =`。
- headless 探针须 `extends SceneTree`+`_init()`；`@onready` 成员 `get("name")` 返 null→用节点路径。`Input.action_press` 仿真不可靠；相机 `global_position.y`=0(RendererDummy)；验证轮询纯逻辑变量 + 数学探针写 txt，勿靠 screenshot。

## 8. 换皮速查（路线B）
动画库换算 p'=scale·R_x90·p / q'=qR·q·qR⁻¹(`convert_anim_lib.gd`→`mixamo_lib_swat.tres`)；坐标系=节点缩放(Armature 飞虎队≈0.00026/SWAT≈0.0138)，非改网格。勿走路线A。

## 8.5 武器模型 reskin（FP 视图模型换枪）【2026-08-16 最终修正版】
> 本节推翻了旧结论"换皮必须静态挂 Armature"——那正是用户第三次"还是看不到"的原因（枪 5cm 或 74m 错位）。**蒙皮必须保留**，见下。

- **正确流程（`tools/_blender_reskin_v9.py`，已验证枪 1.9m+手 AK47 原样+PLAY_OK）**：
  1. **先导入 M82**（此刻 bpy.data 无同名对象）→ 找 King 材质枪 → `transform_apply` → 记录 raw bbox/中心 → `m82_raw = m82_gun.data.copy()` → 删光 M82 对象。
     - ⚠️ **SourceIO 会"原地覆写"同名对象**（`hands__CSO_Hand_Male` 顶点被换成 M82 小手 4.5 单位）。所以必须**先 M82 后 AK47**，让 SourceIO 先跑完、无处可污染；反过来（先 AK47 后 M82）手必被毁。
  2. 再导入 AK47（手 pristine）→ `ak_gun=weapon__02` → `ak_gun_orig=ak_gun.data.copy()`（权重源）→ 记录 ak 枪 raw bbox/中心。
  3. **Godot 尺寸修正**：M82 raw 长轴需 = `1898/(116/172.421) ≈ 2820` 单位（M82 源 1.041 单位 → k≈2709；直接按 AK47 raw 172 单位会得 5cm 枪）。按长轴对齐 + `rotation_difference` + 居中到 ak 枪中心，全 bake 进 `m82_raw`。
  4. `ak_gun.data = m82_raw` → **权重传递** `bpy.ops.object.data_transfer(data_type='VGROUP_WEIGHTS', use_create=True, vert_mapping='POLYINTERP_NEAREST', mix_mode='REPLACE')`（目标=ak_gun active，源=ak_gun_orig 唯一选中；两枪同位同向）。
     - ⚠️ **不能剥离蒙皮**：无有效蒙皮 → glTF 导出把枪移到 Armature 下 → Godot 渲染 74m 错位。有效蒙皮（指向真实骨骼）才被放 Skeleton3D 下且缩放正确（bind pose 含校正）。
     - ⚠️ M82 枪权重组名(R_Arm/L_Hand/L_Finger…)与 AK47 骨骼(Bone01/Bone_Lefthand/root…) **零重叠**，直接保留 M82 权重会被按索引映射到错误 AK47 骨骼 → 动画变形错乱。故必须权重传递。
  5. 删 src 对象/`ak_gun_orig`、删 AK47 多余 `weapon__*`、Armature=0.0254、导出 GLB。
- **验证工具**：`tools/probe_vm_world.gd`（忠实复刻 FPViewmodelPlayer.setup，读真实世界 AABB/cam_space，z 负=前）——**唯一可靠可见性标准**；`tools/probe_raw.gd`（直接量 local aabb+全局缩放）。Blender 静止渲染/节点树 dump 均不可信。
- **Blender 4.5 坑**：`modifiers.clear()`/`vertex_groups.clear()`/`v.groups.clear()` 全被移除→改循环 remove；**对象 bound_box 是过期缓存**（换 data 后不刷新）→ 用顶点范围判断真尺寸；`wm.read_factory_settings` 重置 SourceIO 注册。
- **glTF 导出**：`export_format='GLB'`；Blender 4.5 不认 `export_armature`/`export_apply_scale` 旧 kwarg。

## 9. 落地约定
先 Grep/Read 复用 §5；抽子节点非堆 player.gd。新动画改 `mixamo_lib.tres` 勿跑 setup_*。换枪改 `weapon_rig_config.tres`。FP 改动预览+运行时两处同步。Godot 真身 `C:/Users/93343/Desktop/godot`（路径 `C:/...` 拒 POSIX）。headless=RendererDummy→代码分析+数学探针。
