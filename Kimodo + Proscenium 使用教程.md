# Kimodo + Proscenium 使用教程（无独显笔记本方案）

> 使用 Animatica Cloud 云服务，笔记本集显也能用

---

## 已完成的工作

- ✅ 已找到你的 Blender 安装位置：`C:\Program Files\Blender Foundation\Blender 4.5\blender.exe`
- ✅ 已下载 Proscenium 插件 v0.3.2（兼容 Blender 4.5）
- ✅ 已安装到：`%APPDATA%\Blender Foundation\Blender\4.5\scripts\addons\proscenium_blender\`

---

## 第一步：在 Blender 中启用插件

1. 打开 **Blender 4.5**
2. 菜单栏 → **Edit** → **Preferences** → **Add-ons**
3. 在搜索框输入 `proscenium`
4. 勾选 **Proscenium — AI Motion Generation** 启用插件

![](https://github.com/animatica-ai/proscenium-blender/raw/main/docs/screenshots/enable_addon.png)

---

## 第二步：注册 Animatica 云账号

1. 打开浏览器访问：**[https://animatica.ai](https://animatica.ai/)**
2. 点击 **Sign Up** 注册账号
3. 注册完成后回到 Blender

---

## 第三步：登录并连接云服务

1. 在 Blender 中：**Edit** → **Preferences** → **Add-ons** → 找到 **Proscenium**
2. 展开 **Preferences** 面板
3. 确保 **Self-hosted** 开关处于 **关闭** 状态（关闭 = 使用云服务）
4. 输入你的 Animatica 邮箱和密码 → 点击 **Sign in**
5. 登录成功后，回到 **3D 视图**，按 **N** 键打开右侧面板
6. 找到 **Proscenium** 选项卡
7. 点击 **Connect** 按钮，稍等片刻会显示可用模型列表

---

## 第四步：生成第一个动作

### 准备工作

1. 在 **Proscenium** 面板的 **Main** 中，点击 **Import... skeleton** 导入参考骨架
2. 这会自动创建一个带骨骼的模型

### 添加文字提示

1. 把时间轴视图底部切换到 **Timeline**（默认就是）
2. 在 Timeline 上你会看到一行 **Proscenium** 轨道
3. **双击** 轨道上的空白区域，添加一个 Prompt 块
4. **双击** 这个块，输入提示词，例如：`a person walks forward and waves`
5. 拖动 Prompt 块的边缘调整时长

### 生成动作

1. 设置好总帧范围（例如 1-150 帧）
2. 点击 **Generate Motion** 按钮
3. 等待进度条完成（云服务需要几秒到几十秒）
4. 播放动画预览结果
5. 满意就点 **Accept**，不满意就点 **Reject** 修改后重新生成

---

## 常用提示词示例

| 中文 | English |
|------|---------|
| 一个人向前走 | a person walks forward |
| 一个人开心地跳跃 | a person jumps happily |
| 一个人跑步然后停下 | a person runs and then stops |
| 一个人挥手打招呼 | a person waves hello |
| 一个人弯腰捡东西 | a person bends down to pick something up |
| 一个人跳舞 | a person is dancing |
| 一个人走着然后转身 | a person walks forward and turns around |

---

## 更多功能

- **关键帧约束**：在 Timeline 上给角色摆 Pose，AI 会根据关键帧生成过渡动作
- **路径约束**：画一条曲线，角色会沿着路径走
- **手部/脚部固定**：把手或脚固定在某个物体上
- **多段提示**：在 Timeline 上添加多个 Prompt 块，让角色在不同时间段做不同动作

---

## 常见问题

**Q: Connect 失败怎么办？**
A: 检查网络连接，确认 Animatica 账号密码正确，重新登录

**Q: 生成很慢？**
A: 云服务取决于网络，通常几秒到几十秒。如果太慢，可以尝试缩短 Prompt 时长

**Q: 想用自己的模型/角色？**
A: 在 **Main** 面板的 **Target armature** 中选择你自己的骨骼即可

---

## 参考资源

- [官方教程视频](https://www.youtube.com/watch?v=Wc349qOwjfM&list=PLAJ2UfUYhFQKZpFS8eh1eGUWJ0PAys1n1)
- [Animatica Discord 社区](https://discord.com/invite/A8CrURBewz)（英文求助）
- [Proscenium GitHub](https://github.com/animatica-ai/proscenium-blender)