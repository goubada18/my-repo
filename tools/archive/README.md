# tools/archive — 一次性工具归档

本目录存放历史开发阶段的一次性构建/校验脚本（2026-08-11 ~ 08-28）。
它们完成使命后不再维护，**重跑可能覆盖现有人工维护的场景/资源**，仅作历史参考。

| 脚本 | 当年用途 | 风险备注 |
|---|---|---|
| build_multichar.gd | 文本拼接生成 main_multichar.tscn | 重跑会覆盖手工维护的场景 |
| build_character_preview.gd | 08-14 换皮场景生成（Armature 替换法） | 已被后续方案取代 |
| build_swat_preview.gd / build_system_preview.gd / build_simple_preview.gd / build_lite_preview.gd | 换皮预览各方案 | 四者输出目标互踩 |
| build_nepal3p_arms.gd | 从自制 glb 提取手臂动画生成 tres | 隐含"轻击取 light / 重击取 heavy"约束 |
| build_weapon_defs.gd | 生成 ak47.tres | 重跑会回滚手工修改 |
| verify_gltf.gd / verify_m82_render.gd | M82 接入期验证 | 硬编码绝对路径，换机器失效 |
| verify_preview_load.gd | 换皮期预览链校验 | 一次性 |
| smoke_player_preview.gd | 预览冒烟 | 有未生效的死代码 |
| verify_mirror.py | Blender 镜像重导验证 | 对应方案已判失败，仅存档 |

仍然有效的工具：`../smoke_main.gd`（主场景冒烟）、`../verify_all.gd`（12 项验收门禁）、
`../build_character_asset.gd`（新角色资产生成器）。
