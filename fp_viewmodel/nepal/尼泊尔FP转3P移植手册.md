# 尼泊尔刀 FP→3P 动画移植 · Blender 手动合成手册

> 目标：把第一人称（FP）尼泊尔刀动画，移植/合成到第三人称（3P）Mixamo 人形骨架上。
> 适用：已生成好的干净 FP glb + 项目现有 3P Mixamo 骨架动画。

## 一、你手上的素材

### A. 干净 FP 视图模型（已去干扰、骨名改英文）
路径：`fp_viewmodel/nepal/exports_blender/`
- `nepal_idle.glb`   动画：idle（待机）
- `nepal_heavy.glb`  动画：stab（重击）
- `nepal_light.glb`  动画：midslash1（轻击）

结构：1 个 Armature + 右手臂骨链 + `hand__hands`（手网格）+ `weapon__ref-1`（刀网格）。
**注意：Armature 不能删！** 之前你看到的"球体"就是骨骼显示，删了动画就没了。
手臂骨干名（已英文化）：
- `arm_root → arm_upper → arm_forearm → arm_wrist`
- 手指：`thumb_1/2/3`、`index_1/2/3`、`mid_1/2/3`（以及 palm_*/finger6-10_* 为多余手指细节）
- 刀：`blade_tip`、`wpn_socket_a/b`

### B. 现有 3P 成品（已经移植好的 Mixamo 动画，不用重做）
路径：`resources/animations/`
- `nepal_idle_3p.glb` —— 内含 3 段动作：`nepal_3p_idle` / `nepal_3p_midslash1` / `nepal_3p_stab`
- 另还有 `nepal_heavy_v2/v3.tres`、`nepal_light_v2/v3.tres`、`nepal_idle_3p_anim.tres` 等后续版本

**结论：3 个动作的 3P 版其实你已经有了。** 如果只是要在 Godot 里用，直接用 B 即可，无需再手动移植。

---

## 二、关键技巧 1：别让 FP 骨骼球体挡视线

Blender 默认把没有几何体的骨节点画成"八面体骨股/球"。两个办法解决，都不是删除：

1. **切换骨骼显示形状**（推荐）：
   - 选中 FP 的 `Armature` → 右侧骨骼属性（绿骨图标）→ `Viewport Display` → 把 `Display As` 从 `Octahedral` 改成 `Wire` 或 `Stick`。球体立刻变细线，不挡视线。
2. **仅显示相关骨**：
   - 在 Armature 编辑/姿态模式下，框选只需要的 `arm_root / arm_upper / arm_forearm / arm_wrist` 四根，按 `Shift+H` 只显示它们，其他骨隐藏（`Alt+H` 恢复）。

---

## 三、关键技巧 2：两个模型同场景 + 移植的具体操作

> 说明：FP 是"只有右臂+刀"的局部骨架，3P 是完整人形。两者骨名/数量不同，
> Blender **不能自动**把 FP 动画套到 3P 上。需要手动 retarget（约束映射）。
> 你之前的 `nepal_idle_3p.glb` 已经证明了这套映射可行。

### 方案 X（最省事，推荐先看）：直接用现有 3P 成品
如果你只是要把动画接到游戏角色，根本不需要 Blender：
- Godot 里直接引用 `resources/animations/nepal_idle_3p.glb` 的 3 段 AnimationPlayer 动画，
  或把 `.tres` 动作库挂到 Mixamo 角色骨架上即可。

### 方案 Y（手动在 Blender 合成/微调）：标准 retarget 流程
1. **导入 3P 目标**：`File → Import → glTF 2.0`，选一个带 Mixamo 骨架的 3P 角色（如飞虎队/SWAT 的 glb，或 `nepal_idle_3p.glb` 当骨架参考）。
2. **导入 FP 源**：同一场景再 `File → Import → glTF 2.0`，选 `exports_blender/nepal_idle.glb`（或其它动作文件）。现在场景里有两个 Armature。
3. **对齐姿势**：把 FP Armature 大致移到 3P 右手位置（只是参考用，不用精确）。
4. **用 Bone Constraint 做映射**（姿态模式）：
   - 选中 3P 的 `RightShoulder`，添加 `Bone Constraint → Copy Transforms`（或 `Copy Rotation`），
	 Target 选 FP 的 `arm_root`。
   - 同理映射：`RightArm←arm_upper`、`RightForeArm←arm_forearm`、`RightHand←arm_wrist`、
	 手指 `RightHandThumb1/2/3←thumb_1/2/3`、`RightHandIndex1/2/3←index_1/2/3`、`RightHandMiddle1/2/3←mid_1/2/3`。
   - 多余 FP 手指（palm_*/finger6-10_*）3P 无对应骨，忽略即可。
5. **烘焙动画**：选 3P Armature → `Pose → Animation → Bake Action`
   （勾选 `Visual Keying`、`Clear Constraints`、`Overwrite Current`，帧范围覆盖该动作）。
   这会把约束结果固化成 3P 自己的关键帧。
6. **删掉 FP 源 Armature**，只留 3P。导出 `File → Export → glTF 2.0`（勾 `- Animation`），得到纯 3P 动画文件。
7. 对 idle / 轻击 / 重击 三个文件分别重复步骤 2–6（或在一个文件里依次烘焙 3 段）。

### 简化方案 Z（如果你只想"看对照、不真移植"）
导入两个模型后，只用来**参考 FP 的手部姿态**手调 3P——此时 FP 骨骼设成 `Wire` 显示、半透明，
当作"手部姿势参考物"，直接在 3P 上 K 帧。适合做风格化微调。

---

## 四、骨名对照表（直接抄）

| FP 骨（exports_blender） | 3P Mixamo 骨 |
|---|---|
| arm_root | mixamorig:RightShoulder |
| arm_upper | mixamorig:RightArm |
| arm_forearm | mixamorig:RightForeArm |
| arm_wrist | mixamorig:RightHand |
| thumb_1 / thumb_2 / thumb_3 | RightHandThumb1 / 2 / 3 |
| index_1 / 2 / 3 | RightHandIndex1 / 2 / 3 |
| mid_1 / 2 / 3 | RightHandMiddle1 / 2 / 3 |
| palm_* / finger6-10_* | （3P 无对应，忽略） |
| blade_tip / wpn_socket_a/b | 刀挂点（3P 自带刀模型时不需要） |

---

## 五、常见坑
- **删了 Armature → 动画全没**：那"球体"是骨骼，必须留。
- **FP 局部骨架不能直接套 3P**：必须 retarget（约束+烘焙），不是简单复制。
- **乱码骨名**：源文件是 GBK 乱码，已帮你改成英文，无需再处理。
- **glb 导入报 "Couldn't parse"**：早期版本有 bin 截断 / GODOT 扩展残留；现在 `exports_blender/` 的版本已修正，可直接导入。
