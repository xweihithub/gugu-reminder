# 咕咕提醒 · Gugu Reminder

macOS 原生菜单栏提醒工具，使用 Swift、AppKit 和 AVFoundation。平时只有菜单栏企鹅，到喝水、走动或眼睛休息的时间，播放对应的咕咕嘎嘎透明动画，提醒结束后收起。

## 当前功能

- 喝水默认每 60 分钟、走动每 50 分钟、眼睛休息每 40 分钟，三项独立计时。
- 菜单栏提供提醒设置、暂停提醒 1 小时、恢复提醒和退出。
- 提醒设置用下拉框选择间隔，提供 5–120 分钟常用档位；已保存的其他历史数值保留可选。保存生效后设置界面自动关闭，只重排修改项，未修改项保留原时间；重启保留设置。
- 三种本地透明视频，无声、离线播放。系统“减少动态效果”或播放失败时显示对应静帧。
- 「提醒设置 → 自定义形象」可选一张参考图，通过已登录的 Grok Bot 生成三段动作。预览满意后整套启用，也可切回内置咕咕嘎嘎。首次使用需要连接例行任务，已启用的动画可离线播放。
- 入场约 2.65 秒后显示提示；喝水、走动无人回应会自动收起；眼睛休息从入场结束起倒计时 20 秒，再自动收起。
- 点击完成、角色、关闭或按 Esc 均按正常间隔重排；“稍后”使用短间隔：眼睛 5 分钟，其余 10 分钟。
- 只有角色、回应区和已打开的设置面板接收点击，其余桌面保持穿透。设置打开时暂缓展示到期提醒，关闭后继续。
- 暂停 1 小时后从正常间隔重新计时；手动恢复和睡眠唤醒也重新计时，不补播积压提醒。
- 仅在主显示器展示；不安装后台服务，不自动开机启动，无常驻角色或手动召唤入口。

## 视频质量与体积

原生版保留原素材的 **1080×1080、24 fps、完整帧数及透明效果**，使用系统 HEVC with Alpha 播放。颜色质量和透明通道质量均设为最高 1.0，不降分辨率、不减帧、不缩短动画。

三套视频共抽检 15 个时间点，在黑、灰、白背景上对比原 VP9 素材，最低 SSIM 为 0.99769、最低 PSNR 为 39.57 dB，并检查完整透明解码、帽顶余量和真实播放。转码有微小误差，不属于数学无损。

当前 Apple Silicon 应用约 **98 MiB**，相比旧 Electron 版约 306 MiB 缩小约 68%。剩余体积主要是最高质量视频；原生程序不携带 Chromium 或 Node.js。

## 构建与运行

需要 macOS 13 或更新版本、Xcode 15 / Swift 5.9 或更新版本。已在 Apple Silicon Mac 验证；Intel 构建路径已提供，尚未实机验证。

```sh
git clone https://github.com/xweihithub/gugu-reminder.git
cd gugu-reminder
make build
make run
```

Apple Silicon 输出为 `dist/mac-arm64/Golden Paw.app`，Intel 输出为 `dist/mac-x64/Golden Paw.app`。构建只需 Apple 开发工具，无外部 Swift 依赖、npm 或 FFmpeg。现为本地 ad-hoc 签名构建，未做 Developer ID 签名及公证。

启动新版前请先退出旧版。菜单栏版使用 Bundle ID `com.zoey.goldenpaw.menubar`。应用包名和存档路径 `~/Library/Application Support/Golden Paw/state.json` 保持兼容；已有提醒设置自动沿用，历史无关字段保留但不参与运行。构建替换前的应用会存为本地 `artifacts/local-builds/previous-app.tar`。

## 验证与素材维护

```sh
make test     # 10 项核心计时、存档和会话测试
make verify   # 构建并运行 15 项原生应用集成检查，约 1–2 分钟
make media    # 可选：从原始 VP9 透明视频重建原生 MOV，需要 FFmpeg
```

集成检查使用独立临时存档，覆盖实际到期播放、完整解码、末帧停留、倒计时、回应、设置保存、暂停/唤醒、减少动态效果、自定义成片校验、手动导入和整套切换。验证使用本地成片，避免消耗 Grok 用量。验证会短暂显示测试画面，但不抢焦点或截获鼠标。结果位于忽略提交的 `artifacts/native-qa/`。

## 项目结构

| 路径 | 内容 |
| --- | --- |
| `native/Core/` | 计时、间隔、会话与兼容存档 |
| `native/App/` | AppKit 菜单、设置、透明窗口和系统视频播放器 |
| `native/Tests/` | 核心自动测试 |
| `Assets/` | 三套原生 HEVC Alpha MOV 及 PNG 静帧，随应用打包 |
| `SourceAssets/` | 当前三套 VP9 Alpha 原素材，用于维护对比，不随应用打包 |
| `tools/` | 构建、验证、原生转码与可选抠像工具 |
| `docs/` | 架构、角色与视频说明 |

`tools/key-reminder-video.py` 是可选绿幕素材处理工具，需要 FFmpeg、Python 的 opencv-python、numpy 和 scipy；正常构建及运行无需它们。旧 Electron 实现、旧角色、生成原片、实验和制作过程保留在本地归档与 Git 历史，不进入当前应用包。

## 维护文档

- [当前架构](docs/architecture.md)
- [透明视频提醒](docs/reminder-animation.md)
- [角色素材](docs/character-assets.md)
- [自定义形象与 Grok 配置](docs/custom-character.md)
