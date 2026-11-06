# Windows 原生版

分支：`feat/windows-native`。Electron 版本继续保留在 `feat/windows-desktop`。

采用 C#、WPF 原生透明窗口、Windows 托盘和系统自带的 .NET Framework 4.x。目标为 Windows 10/11 x64，无需安装 Node、Electron、WebView2 或额外视频解码器。安装后完全离线运行；不设置开机启动。

## 功能

- 喝水、走动、眼睛休息独立计时；默认 60、50、40 分钟。
- 粉色设置页、卡通字体、1–1440 分钟间隔设置、暂停一小时、恢复、退出。
- 透明动画和紧凑提示整体居中，主显示器适配；仅角色的不透明区域及提示条接收点击。
- 入场结束后显示回应；眼睛休息倒计时 20 秒。完成、关闭、Esc、无人回应使用正常间隔；稍后为护眼 5 分钟、其余 10 分钟。
- 唤醒后重新计时，不补播睡眠期间提醒；同一原生程序重复启动打开设置。
- `%APPDATA%/Golden Paw Native/state.json` 独立存档，首次启动从 `%APPDATA%/Golden Paw/state.json` 导入原版设置，保留原存档，不与正在运行的 Electron 版本共写文件。
- Electron 版和原生版可以分别安装。正常使用时请只启动其中一个，避免两套计时器各自提醒。

## 保留原始视频画质

运行时随包携带独立 FFmpeg 9.0.2/libvpx 解码器，直接解码原始 WebM。保留 **1080×1080、24 fps、VP9 alpha**；不重编码、不缩小、不做颜色量化。构建时逐文件校验视频 SHA-256，确保与仓库源素材完全相同。

FFmpeg 为独立后台进程，输出原尺寸 BGRA 帧到 WPF 位图。无需安装视频解码插件、WebView2 或 FFmpeg。仅播放提醒时启动解码器，结束后退出；内存只保留当前画面，不预展开所有帧。实测 EXE 安装包约 36.4 MB，免安装 ZIP 约 47.8 MB；相较 Electron 约 117.8 MB 的安装包缩小约 69%。安装后文件约 111 MB。

解码器来源、固定校验值、许可证及对应源码位置见 `prepare-decoder.ps1` 和 `THIRD-PARTY-NOTICES.txt`。再分发时须遵守随包附带的 FFmpeg GPLv3 许可证和对应源码提供要求。字体按 SIL OFL 授权，许可证随包附带。

## 构建

需要 Windows 自带 Framework C# 编译器、7-Zip 和 NSIS 3。`makensis.exe` 可加入 PATH；脚本也会查找 electron-builder 已下载的 NSIS 缓存。

```powershell
powershell -ExecutionPolicy Bypass -File native/prepare-decoder.ps1
powershell -ExecutionPolicy Bypass -File native/build.ps1
```

输出：

- `dist/Gugu-Reminder-Native-0.2.0-Setup.exe`：当前用户安装，创建桌面与开始菜单快捷方式，提供卸载入口，无需管理员权限。
- `dist/Gugu-Reminder-Native-0.2.0-win-x64.zip`：完整解压后打开 `GuguReminder.exe`，保留同目录 `assets` 文件夹。

安装包未签名。卸载保留用户设置，不删除 Electron 版本，也不卸载任何系统组件。

## 验证

`GuguReminder.exe --self-test` 检查计时、暂停恢复、间隔校验、存档读写、旧版导入、全部 576 帧解码、喝水顶部安全余量和视频重新播放，结果写入同目录 `self-test.txt`。构建脚本自动执行。

`GuguReminder.exe --smoke-test` 使用独立临时存档，自动检查实际设置窗口、暂停恢复、到期动画与稍后重排，生成 `qa/settings.png`、`qa/water.png`、`qa/result.txt` 后退出。不会修改正式存档。测试报告及截图不打入安装包或 ZIP。
