// 自动验证使用独立存档；不会在菜单中暴露预览、召唤或立即提醒入口。
import AppKit
import AVFoundation
import ReminderCore

final class NativeVerification {
    unowned let app: AppController
    let output: URL
    var checks: [String] = []
    var media: [[String: Any]] = []
    init(app: AppController, output: URL) { self.app = app; self.output = output }
    struct Failure: Error, CustomStringConvertible { let description: String }
    func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw Failure(description: message) }
    }
    func passed(_ message: String) { checks.append(message); print("✓ \(message)"); fflush(stdout) }
    func delay(_ seconds: Double) async throws { try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000)) }
    func waitUntil(_ condition: () -> Bool, timeout: Double = 5) async throws {
        let end = app.monotonicNow + timeout
        while !condition() {
            if app.monotonicNow > end { throw Failure(description: "等待状态超时") }
            try await delay(0.05)
        }
    }
    func start() {
        Task { @MainActor in
            do {
                try await run()
                let report: [String: Any] = ["success": true, "checks": checks, "media": media,
                    "legacyDataPreserved": app.store.root["resident"] as? Bool == true,
                    "stateFile": app.store.url.path]
                try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                    .write(to: output.appendingPathComponent("native-qa.json"), options: .atomic)
                print("原生应用验证全部通过，共 \(checks.count) 项。")
                NSApp.terminate(nil)
            } catch {
                fputs("原生应用验证失败: \(error)\n", stderr)
                let report: [String: Any] = ["success": false, "error": String(describing: error), "checks": checks, "media": media]
                if let data = try? JSONSerialization.data(withJSONObject: report, options: .prettyPrinted) {
                    try? data.write(to: output.appendingPathComponent("native-qa.json"))
                }
                exit(1)
            }
        }
    }

    private func verifyMedia(_ kind: ReminderKind) async throws -> [String: Any] {
        let asset = AVURLAsset(url: app.assets.appendingPathComponent("gugugaga-\(kind.rawValue)-alpha.mov"))
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw Failure(description: "无视频轨道: \(kind)") }
        let duration = try await asset.load(.duration)
        let naturalSize = try await track.load(.naturalSize)
        let reader = try AVAssetReader(asset: asset)
        let frames = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        frames.alwaysCopiesSampleData = false; reader.add(frames)
        try require(reader.startReading(), "无法解码 \(kind): \(String(describing: reader.error))")
        var count = 0, minTop = Int.max, minClear = Int.max, maxOpaque = 0
        while let sample = frames.copyNextSampleBuffer() {
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
            let row = CVPixelBufferGetBytesPerRow(buffer)
            let data = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
            var top = height, clear = 0, opaque = 0
            for y in 0..<height {
                for x in 0..<width {
                    let alpha = data[y * row + x * 4 + 3]
                    if alpha == 0 { clear += 1 }
                    // HEVC Alpha 的系统解码会将部分 255 映射至 253；按近乎不透明计数。
                    if alpha >= 250 { opaque += 1 }
                    if alpha > 25 { top = min(top, y) }
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
            minTop = min(minTop, top); minClear = min(minClear, clear); maxOpaque = max(maxOpaque, opaque); count += 1
        }
        try require(reader.status == .completed, "完整视频解码失败: \(kind)")
        try require(count >= 190 && minClear > 50000 && maxOpaque > 50000, "透明或帧数异常: \(kind)，frames=\(count)，clear=\(minClear)，opaque=\(maxOpaque)")
        if kind == .water { try require(minTop >= 90, "喝水帽顶安全边距不足") }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
        for time in [0.5, 2.5, 3.5, 5.5, 7.5] {
            let cg = try generator.copyCGImage(at: CMTime(seconds: time, preferredTimescale: 600), actualTime: nil)
            let image = NSBitmapImageRep(cgImage: cg)
            try image.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent("\(kind.rawValue)-native-\(time).png"))
        }
        return ["kind": kind.rawValue, "frames": count, "minimumTop": minTop,
                "minimumTransparentPixels": minClear, "maximumNearOpaquePixels": maxOpaque,
                "duration": duration.seconds, "width": naturalSize.width, "height": naturalSize.height]
    }

    @MainActor private func run() async throws {
        try require(!app.characterWindow.isVisible && !app.cardWindow.isVisible && !app.settingsWindow.isVisible, "启动应隐藏所有窗口")
        try require(app.menu.items.filter { !$0.isSeparatorItem }.map(\.title) == ["提醒设置", "暂停提醒 1 小时", "恢复提醒", "退出"], "菜单范围变化")
        try require(app.store.root["resident"] as? Bool == true, "未保留旧存档")
        passed("启动隐藏、四项菜单及旧存档兼容")

        // 转码后从系统解码器检查每一帧的透明通道，避免黑底或静帧冒充动画。
        for kind in ReminderKind.allCases { media.append(try await verifyMedia(kind)) }
        passed("三套 HEVC Alpha 的系统透明解码、完整帧数及喝水帽顶安全边距")

        try await waitUntil({ app.session?.kind == .water }, timeout: 6)
        let original = app.session!
        app.startReminder(.eyes)
        try require(app.session === original, "重复事件重启动画")
        try await waitUntil({ app.session?.stage == .ready && app.animation.view.playerLayer.isReadyForDisplay }, timeout: 6)
        try require(app.cardWindow.isVisible && app.card.done.isEnabled && app.card.done.title == "喝好了", "入场后回应区异常")
        try require(!app.animation.usingStill && app.animation.player?.currentItem?.status == .readyToPlay, "系统播放器未真实播放")
        let screen = NSScreen.screens.first!.visibleFrame
        try require(screen.contains(app.characterWindow.frame), "角色窗口超出主显示器")
        app.updateClickThrough()
        let bounds = app.characterWindow.frame
        let hit = NSRect(x: bounds.minX + bounds.width * 0.08, y: bounds.minY + bounds.height * 0.03, width: bounds.width * 0.84, height: bounds.height * 0.94)
        try require(app.characterHit(at: NSPoint(x: hit.midX, y: hit.midY)) && !app.characterHit(at: NSPoint(x: bounds.minX - 1, y: bounds.minY - 1)), "桌面穿透区域异常")
        try require(app.characterWindow.ignoresMouseEvents && app.cardWindow.ignoresMouseEvents, "自动验证不应拦截用户鼠标")
        try require(!app.characterWindow.isOpaque && app.characterWindow.backgroundColor == .clear, "透明窗口异常")
        passed("真实定时到期、2.65 秒入场、AVPlayer 播放、主屏布局和点击穿透")
        try await waitUntil({ (app.animation.player?.currentTime().seconds ?? 0) >= 7.95 }, timeout: 7)
        try require(app.session != nil && app.characterWindow.isVisible, "视频结束前提前收起")
        passed("8 秒完整播放及末帧停留")
        app.card.later.performClick(nil)
        let next = app.clock.next[.water]!
        app.finish(snooze: false)
        try require(app.clock.next[.water] == next && abs(next - ReminderClock.now - 600000) < 2000, "稍后十分钟或重复回应异常")
        try await waitUntil({ app.session == nil })
        try require(!app.characterWindow.isVisible && !app.cardWindow.isVisible && app.animation.player == nil, "结束后有角色或播放器残留")
        passed("稍后十分钟、回应只保存一次、淡出后完全收起")

        let settingsItem = app.menu.items[0]
        NSApp.sendAction(settingsItem.action!, to: settingsItem.target, from: settingsItem)
        try require(app.settingsVisible && app.settingsWindow.isVisible, "设置未显示")
        app.settings.fields[.water]?.stringValue = "30"; app.settings.fields[.walk]?.stringValue = "45"; app.settings.fields[.eyes]?.stringValue = "20"
        app.settings.save.performClick(nil)
        try require(app.clock.intervals == [.water: 30, .walk: 45, .eyes: 20], "设置未应用")
        let reloaded = StateStore(url: app.store.url)
        try require(reloaded.clock.intervals == app.clock.intervals && reloaded.root["preferences"] as? [String] == ["旧版偏好"], "重新载入或历史字段丢失")
        app.settings.fields[.water]?.stringValue = "0"; app.settings.save.performClick(nil)
        try require(app.clock.intervals[.water] == 30 && app.settings.status.stringValue.contains("1–1440"), "非法设置未拒绝")
        passed("原生设置真实保存、重新加载、非法输入拒绝及历史字段保留")
        app.clock.finish(.walk, now: ReminderClock.now - 45 * 60000 - 1)
        app.checkDue()
        try require(app.session == nil, "设置打开时不应展示到期提醒")
        app.saveIntervals(["walk": 46])
        app.closeSettings()
        try require(app.session == nil, "修改间隔后不应展示旧到期提醒")
        app.openSettings()
        app.clock.finish(.walk, now: ReminderClock.now - 46 * 60000 - 1)
        app.closeSettings()
        try require(app.session?.kind == .walk, "关闭设置后应继续到期提醒")
        passed("设置期间暂缓、修改后取消旧到期、关闭后恢复展示")
        app.pause()
        try require(app.session == nil && app.clock.pausedUntil > ReminderClock.now && !app.characterWindow.isVisible, "暂停未收起")
        app.resume()
        try require(app.clock.pausedUntil == 0 && app.clock.due() == nil, "恢复未重新计时")
        app.startReminder(.water); app.woke()
        try require(app.session == nil && app.clock.due() == nil, "唤醒补播了积压")
        passed("暂停一小时、手动恢复、唤醒不补播")

        app.setReducedMotionForVerification(true)
        for kind in ReminderKind.allCases {
            app.startReminder(kind)
            try require(app.animation.usingStill && app.animation.player == nil && app.cardWindow.isVisible, "减少动态效果未用静帧")
            if kind == .eyes { try require(app.session?.remaining(now: app.monotonicNow) == 20 && !app.card.done.isEnabled, "静帧眼睛倒计时异常") }
            app.finish(snooze: true, animate: false)
            try require(abs(app.clock.next[kind]! - ReminderClock.now - Double(kind.snoozeMinutes) * 60000) < 2000, "稍后间隔异常")
        }
        let stillOnly = output.appendingPathComponent("still-only")
        try FileManager.default.createDirectory(at: stillOnly, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: app.assets.appendingPathComponent("gugugaga-water-rest.png"), to: stillOnly.appendingPathComponent("gugugaga-water-rest.png"))
        app.animation.start(kind: .water, reduced: false, assets: stillOnly)
        try require(app.animation.failed && app.animation.usingStill && app.character.stillView.image != nil, "播放失败未降级")
        app.animation.stop()
        passed("三类减少动态效果静帧、5/10 分钟稍后、播放失败降级")

        app.setReducedMotionForVerification(false)
        app.startReminder(.eyes)
        try await waitUntil({ app.session?.stage == .resting }, timeout: 5)
        try require(!app.card.done.isEnabled && app.session?.remaining(now: app.monotonicNow) == 20, "眼睛倒计时应从入场后开始")
        app.card.done.performClick(nil)
        try require(app.session?.stage == .resting, "未完成休息时不应能点完成")
        try await delay(10)
        try require(app.session.map { (9...10).contains($0.remaining(now: app.monotonicNow)) } ?? false, "20 秒倒计时中间值异常或提醒提前结束")
        try await waitUntil({ app.session?.stage == .ready }, timeout: 12)
        try require(app.card.done.isEnabled && app.card.titleText == "好啦，慢慢回来", "休息结束状态异常")
        passed("真实 20 秒眼睛休息、完成按钮禁用及结束反馈")
        try await waitUntil({ app.session == nil }, timeout: 4)
        try require(!app.characterWindow.isVisible && !app.cardWindow.isVisible, "眼睛休息未自动收起")
        passed("眼睛休息完成后自动淡出收起")

        app.startReminder(.walk)
        try await waitUntil({ app.session == nil }, timeout: 11)
        try require(abs(app.clock.next[.walk]! - ReminderClock.now - Double(app.clock.intervals[.walk]!) * 60000) < 2000, "无人回应不应短间隔重排")
        passed("走动无人回应自动收起并按正常间隔重排")

        app.startReminder(.water); app.openSettings()
        try require(app.session == nil && app.settingsVisible, "提醒中打开设置未正常结束")
        app.settingsWindow.cancelOperation(nil)
        try require(!app.settingsVisible, "Esc 未关闭设置")
        app.startReminder(.water); app.characterWindow.cancelOperation(nil)
        try await waitUntil({ app.session == nil })
        try require(abs(app.clock.next[.water]! - ReminderClock.now - 30 * 60000) < 2000, "Esc 未使用正常间隔")
        passed("提醒中打开设置、Esc 关闭与正常间隔重排")
    }
}
