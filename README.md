# 咕咕提醒 · Gugu Reminder

macOS 菜单栏提醒工具。平时不显示角色，到喝水、走动或眼睛休息的时间，播放对应的咕咕嘎嘎透明动画，提醒结束后收起。

## 当前功能

- 喝水默认每 60 分钟、走动每 50 分钟、眼睛休息每 40 分钟，三项独立计时。
- 菜单栏 🐧 只提供提醒设置、暂停提醒 1 小时、恢复提醒和退出。
- 提醒设置可分别填写 1–1440 分钟的整数；保存后，修改项重新计时，未修改项保留原时间，重启后保留。
- 三种提醒各用已制作的本地透明视频，无声、离线播放；系统“减少动态效果”模式或播放失败时使用对应静帧。
- 入场约 2.65 秒后显示提示。喝水和走动无人回应会自动收起；眼睛休息从入场结束起倒计时 20 秒，再自动收起。
- 点击完成、角色、关闭或按 Esc 均按正常间隔重排；只有“稍后”使用短间隔，眼睛 5 分钟，其余 10 分钟。
- 只有提醒角色、回应区和已打开的设置面板接收点击，其余桌面保持穿透。设置面板打开时暂缓展示到期动画，关闭后继续。
- 唤醒后从正常间隔重新计时，不补播睡眠期间积压提醒。当前仅支持主显示器。

## 启动与打包

需要 macOS、Node.js 22.12 或更新版本及 npm。

```sh
git clone https://github.com/xweihithub/gugu-reminder.git
cd gugu-reminder
npm ci
npm start
```

构建本地应用包：

```sh
npm run package:mac
```

本地未签名开发包位于 `dist/mac-arm64/Golden Paw.app`，启动后平时只有菜单栏 🐧。不安装后台服务，不自动开机启动。

项目目录、应用包名及存储标识保留 Golden Paw，以继续使用原提醒设置。旧版常驻设置不再生效；已有历史数据保留在原存档，但当前界面和通信接口仅提供提醒功能。不需要本机控制台、模型接口或 API 密钥。

## 验证

- `npm test`：提醒计时、旧存档兼容、播放流程、倒计时、间隔设置及旧入口移除。
- `npm run check`：运行源码语法检查。
- `./node_modules/.bin/electron tools/verify-scheduled-reminder.cjs`：真实主进程、菜单、启动隐藏、旧常驻存档、实际到期播放、暂停和恢复，使用独立临时存档。可用 `GOLDEN_PAW_QA_KIND=walk` 或 `eyes` 选择验证种类；用 `GOLDEN_PAW_QA_MAIN` 指定打包主进程路径。
- `./node_modules/.bin/electron tools/verify-reminder-settings.cjs`：真实保存、重新载入及非法间隔拒绝，使用独立临时存档。
- `./node_modules/.bin/electron tools/verify-reminder-video.cjs`：真实透明解码、完整播放、切换与重复播放；`GOLDEN_PAW_QA_KIND=eyes` 可验证完整 20 秒休息倒计时。

## 项目结构

| 目录 | 内容 |
| --- | --- |
| `src/core/` | 提醒计时与间隔规则 |
| `src/desktop/` | Electron 主进程、菜单栏、存档及界面通信 |
| `src/renderer/` | 设置、提醒界面和透明视频播放器 |
| `src/renderer/assets/` | 三种提醒的透明视频及对应静帧 |
| `tests/` | 计时与界面自动化测试 |
| `tools/` | Electron 验证和透明视频处理工具 |
| `docs/` | 当前架构与素材说明 |

播放器构建产物由启动和打包命令自动生成，不提交 Git。验证工具生成的截图和报告写入本地 `artifacts/`，也不提交。

`tools/key-reminder-video.py` 是可选素材维护工具，运行应用无需 Python 或重新制作视频。使用它处理新素材时，需要 `/opt/homebrew/bin/ffmpeg` 以及 Python 的 `opencv-python`、`numpy`、`scipy`。

## 维护文档

- [当前架构](docs/architecture.md)
- [透明视频提醒](docs/reminder-animation.md)
- [角色素材](docs/character-assets.md)

仓库仅包含当前定时提醒工具。历史陪伴和工作助理原型、旧角色、实验与素材制作记录保留在开发者本地，不随仓库发布。
