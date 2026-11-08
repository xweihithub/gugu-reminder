import AppKit
import AVFoundation
import ReminderCore

final class AnimationPlayer {
    let view: CharacterView
    private(set) var player: AVPlayer?
    private var itemObservation: NSKeyValueObservation?
    private var layerObservation: NSKeyValueObservation?
    private(set) var usingStill = false
    private(set) var failed = false

    init(view: CharacterView) { self.view = view }
    func start(kind: ReminderKind, reduced: Bool, assets: URL) {
        stop()
        failed = false
        view.stillView.image = NSImage(contentsOf: assets.appendingPathComponent("gugugaga-\(kind.rawValue)-rest.png"))
        view.stillView.isHidden = false
        view.playerLayer.isHidden = true
        usingStill = true
        guard !reduced else { return }
        let url = assets.appendingPathComponent("gugugaga-\(kind.rawValue)-alpha.mov")
        guard FileManager.default.fileExists(atPath: url.path) else { failed = true; return }
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true; player.volume = 0; player.actionAtItemEnd = .pause
        self.player = player
        view.playerLayer.player = player
        itemObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            DispatchQueue.main.async { self?.showStill(failed: true) }
        }
        layerObservation = view.playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
            guard layer.isReadyForDisplay else { return }
            DispatchQueue.main.async {
                guard let self, self.player?.currentItem === item, !self.failed else { return }
                self.view.stillView.isHidden = true; self.view.playerLayer.isHidden = false; self.usingStill = false
            }
        }
        player.play()
    }
    func showStill(failed: Bool = false) {
        self.failed = failed; usingStill = true
        player?.pause(); view.playerLayer.isHidden = true; view.stillView.isHidden = false
    }
    func stop() {
        itemObservation = nil; layerObservation = nil
        player?.pause(); player?.replaceCurrentItem(with: nil); player = nil
        view.playerLayer.player = nil
        view.stillView.isHidden = true; view.playerLayer.isHidden = true
    }
}

final class AppController: NSObject, NSApplicationDelegate {
    let store: StateStore
    let assets: URL
    let verificationDirectory: URL?
    var clock: ReminderClock { store.clock }
    var statusItem: NSStatusItem!
    var menu: NSMenu!
    let characterWindow = FloatingPanel(frame: NSRect(x: 0, y: 0, width: 580, height: 580))
    let cardWindow = FloatingPanel(frame: NSRect(x: 0, y: 0, width: 320, height: 40))
    let settingsWindow = FloatingPanel(frame: NSRect(x: 0, y: 0, width: 390, height: 300))
    let character = CharacterView(frame: NSRect(x: 0, y: 0, width: 580, height: 580))
    let card = ReminderCardView(frame: NSRect(x: 0, y: 0, width: 320, height: 40))
    let settings = SettingsView(frame: NSRect(x: 0, y: 0, width: 390, height: 300))
    lazy var animation = AnimationPlayer(view: character)
    private(set) var session: ReminderSession?
    private var scheduler: Timer?
    private var playbackTimer: Timer?
    private var keyMonitor: Any?
    private var verification: NativeVerification?
    private var settingsOpen = false
    private var reducedMotionOverride: Bool?
    var reducedMotion: Bool { reducedMotionOverride ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    var monotonicNow: Double { ProcessInfo.processInfo.systemUptime }
    var settingsVisible: Bool { settingsOpen }

    init(stateURL: URL, assets: URL, verificationDirectory: URL? = nil) {
        store = StateStore(url: stateURL)
        self.assets = assets; self.verificationDirectory = verificationDirectory
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if verificationDirectory == nil,
           NSRunningApplication.runningApplications(withBundleIdentifier: "com.zoey.goldenpaw").contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            DistributedNotificationCenter.default().postNotificationName(Notification.Name("com.zoey.goldenpaw.show-settings"), object: nil, userInfo: nil, deliverImmediately: true)
            NSApp.terminate(nil); return
        }
        characterWindow.contentView = character; cardWindow.contentView = card; settingsWindow.contentView = settings
        if verificationDirectory != nil {
            // 自动验证显示真实画面，但不截获用户正在进行的鼠标操作。
            cardWindow.ignoresMouseEvents = true; settingsWindow.ignoresMouseEvents = true
        }
        settingsWindow.hasShadow = true
        characterWindow.title = "咕咕嘎嘎 · 定时提醒"
        cardWindow.title = "咕咕嘎嘎 · 提醒回应"
        settingsWindow.title = "咕咕提醒 · 提醒设置"
        settingsWindow.isExcludedFromWindowsMenu = true
        characterWindow.escape = { [weak self] in self?.finish(snooze: false) }
        cardWindow.escape = characterWindow.escape
        settingsWindow.escape = { [weak self] in self?.closeSettings() }
        character.onClick = { [weak self] in
            guard self?.session?.stage == .ready else { return }
            self?.finish(snooze: false)
        }
        card.done.onClick = character.onClick
        card.later.onClick = { [weak self] in self?.finish(snooze: true) }
        card.close.onClick = { [weak self] in self?.finish(snooze: false) }
        card.onSizeChange = { [weak self] in self?.layoutWindows() }
        settings.close.onClick = { [weak self] in self?.closeSettings() }
        settings.onSave = { [weak self] values in self?.saveIntervals(values) }
        settings.load(clock.intervals)
        configureMenus()
        layoutWindows()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, let self else { return event }
            if self.session != nil { self.finish(snooze: false); return nil }
            if self.settingsOpen { self.closeSettings(); return nil }
            return event
        }
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(woke), name: NSWorkspace.didWakeNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(openSettings), name: Notification.Name("com.zoey.goldenpaw.show-settings"), object: nil)
        persist()
        scheduler = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.checkDue() }
        RunLoop.main.add(scheduler!, forMode: .common)
        if let verificationDirectory {
            verification = NativeVerification(app: self, output: verificationDirectory)
            verification?.start()
        }
    }

    private func configureMenus() {
        menu = NSMenu()
        for (title, selector) in [("提醒设置", #selector(openSettings)), ("暂停提醒 1 小时", #selector(pause)), ("恢复提醒", #selector(resume))] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            item.target = self; menu.addItem(item)
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self; menu.addItem(quit)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🐧"; statusItem.button?.toolTip = "咕咕嘎嘎 · 定时提醒"
        statusItem.menu = menu
        let mainMenu = NSMenu()
        let appItem = NSMenuItem(); appItem.title = "咕咕提醒"; appItem.submenu = menu.copy() as? NSMenu
        mainMenu.addItem(appItem)
        let editItem = NSMenuItem(); editItem.title = "编辑"
        let edit = NSMenu(title: "编辑")
        for (title, selector, key) in [("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: Selector(selector), keyEquivalent: key)
        }
        editItem.submenu = edit; mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    func checkDue() {
        guard session == nil, !settingsOpen, let due = clock.due() else { return }
        startReminder(due)
    }

    // 仅由定时器和自动验证调用；产品不提供手动召唤或立即提醒入口。
    func startReminder(_ kind: ReminderKind) {
        guard session == nil, !settingsOpen else { return }
        let active = ReminderSession(kind: kind, reducedMotion: reducedMotion, now: monotonicNow)
        session = active
        card.update(session: active, now: monotonicNow)
        character.setAccessibilityLabel("\(kind.label)提醒，点击角色回应")
        layoutWindows()
        characterWindow.alphaValue = 1; characterWindow.ignoresMouseEvents = false
        characterWindow.orderFrontRegardless()
        cardWindow.orderOut(nil)
        animation.start(kind: kind, reduced: reducedMotion, assets: assets)
        playbackTimer = Timer(timeInterval: 0.03, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(playbackTimer!, forMode: .common)
        tick()
    }

    func tick() {
        guard let active = session, active.stage != .leaving else { return }
        let previous = active.stage
        let now = monotonicNow
        active.update(now: now)
        if previous == .entering, active.stage != .entering {
            cardWindow.alphaValue = reducedMotion ? 1 : 0
            cardWindow.orderFrontRegardless()
            if !reducedMotion {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.35; cardWindow.animator().alphaValue = 1
                }
            }
        }
        if active.stage != .entering { card.update(session: active, now: now) }
        updateClickThrough()
        if active.shouldAutoFinish(now: now) { finish(snooze: false) }
    }

    func updateClickThrough() {
        characterWindow.ignoresMouseEvents = verificationDirectory != nil || !characterHit(at: NSEvent.mouseLocation)
    }
    func characterHit(at point: NSPoint) -> Bool {
        let bounds = characterWindow.frame
        let clickable = NSRect(x: bounds.minX + bounds.width * 0.08, y: bounds.minY + bounds.height * 0.03,
                               width: bounds.width * 0.84, height: bounds.height * 0.94)
        return clickable.contains(point)
    }

    func finish(snooze: Bool, animate: Bool = true) {
        guard let active = session, active.beginLeaving() else { return }
        if verificationDirectory != nil { print("验证回应: \(active.kind.rawValue)，稍后=\(snooze)"); fflush(stdout) }
        clock.finish(active.kind, snooze: snooze)
        persist()
        playbackTimer?.invalidate(); playbackTimer = nil
        cardWindow.orderOut(nil)
        animation.player?.pause()
        if animate && !reducedMotion {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.35; characterWindow.animator().alphaValue = 0
            }, completionHandler: { [weak self, weak active] in
                guard let self, let active, self.session === active else { return }
                self.dismiss()
            })
        } else { dismiss() }
    }

    func dismiss() {
        playbackTimer?.invalidate(); playbackTimer = nil; session = nil
        animation.stop()
        characterWindow.orderOut(nil); cardWindow.orderOut(nil)
        characterWindow.ignoresMouseEvents = true
    }

    @objc func openSettings() {
        if session != nil { finish(snooze: false, animate: false) }
        settingsOpen = true
        settings.load(clock.intervals)
        layoutWindows()
        if verificationDirectory == nil {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            settingsWindow.makeFirstResponder(settings.pickers[.water])
        } else { settingsWindow.orderFrontRegardless() }
    }
    func closeSettings() {
        settingsOpen = false; settingsWindow.orderOut(nil)
        checkDue()
    }
    func saveIntervals(_ values: [String: Any]) {
        do {
            try clock.setIntervals(values)
            do { try store.save() }
            catch {
                // 无法写盘时反馈失败；内存计时继续有效，不向用户谎报已保存。
                settings.status.stringValue = "保存失败，请重试"
                NSLog("保存提醒设置失败: %@", error.localizedDescription)
                return
            }
            settings.status.stringValue = "已保存，重启后也会保留"
            // 保存生效后直接关闭设置界面；关闭会顺带恢复展示到期提醒。
            closeSettings()
        } catch {
            settings.status.stringValue = error.localizedDescription
        }
    }
    @objc func pause() { clock.pause(); persist(); dismiss() }
    @objc func resume() { clock.reset(); persist() }
    @objc func woke() { clock.reset(); persist(); dismiss() }
    @objc func quitApp() { NSApp.terminate(nil) }
    @objc func screenChanged() { layoutWindows() }

    func layoutWindows() {
        guard let screen = NSScreen.screens.first else { return }
        let area = screen.visibleFrame
        let bottom = min(240, max(180, area.height * 0.24))
        // 小屏幕也保留顶部余量，避免整个窗口超出显示区域。
        let size = max(1, min(580, area.height * 0.68, area.width * 0.92, area.height - bottom - 16))
        characterWindow.setFrame(NSRect(x: area.midX - size / 2, y: area.minY + bottom, width: size, height: size), display: true)
        // 文字气泡与 Windows 原生版一致：尺寸随内容收缩，位于动画正下方 6 点（8 DIU）处并水平居中。
        let cardSize = card.contentSize()
        cardWindow.setFrame(NSRect(x: characterWindow.frame.midX - cardSize.width / 2,
                                   y: characterWindow.frame.minY - 6 - cardSize.height,
                                   width: cardSize.width, height: cardSize.height), display: true)
        settingsWindow.setFrameOrigin(NSPoint(x: max(area.minX + 16, area.maxX - 35 - 390), y: area.maxY - 45 - 300))
    }
    private func persist() {
        do { try store.save() }
        catch { NSLog("保存提醒状态失败: %@", error.localizedDescription) }
    }
    func setReducedMotionForVerification(_ value: Bool?) { reducedMotionOverride = value }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openSettings(); return false }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        scheduler?.invalidate(); dismiss()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }
}
