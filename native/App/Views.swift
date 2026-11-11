import AppKit
import AVFoundation
import CoreText
import ReminderCore

// 动画下方文字气泡与 Windows 原生版一致：奶油底圆角气泡、站酷快乐体、标题与按钮同一行。
enum CaptionPalette {
    static let bubble = NSColor(srgbRed: 1, green: 0.9804, blue: 0.9412, alpha: 1)       // #FFFAF0
    static let title = NSColor(srgbRed: 0.3647, green: 0.2902, blue: 0.2078, alpha: 1)   // #5D4A35
    static let counter = NSColor(srgbRed: 0.5490, green: 0.3882, blue: 0.4588, alpha: 1) // #8C6375
    static let ink = NSColor(srgbRed: 0.3490, green: 0.2353, blue: 0.2980, alpha: 1)     // #593C4C
    static let line = NSColor(srgbRed: 0.9412, green: 0.8627, blue: 0.9020, alpha: 1)    // #F0DCE6
    static let doneFill = NSColor(srgbRed: 0.8824, green: 0.9216, blue: 0.8275, alpha: 1) // #E1EBD3
    static let doneInk = NSColor(srgbRed: 0.3294, green: 0.4392, blue: 0.2667, alpha: 1) // #547044
}

enum CaptionFont {
    private static var attempted = false
    // 启动时从应用包 Assets/fonts 注册站酷快乐体（OFL 授权，许可文本随包携带）；失败回退系统字体。
    static func register(assets: URL) {
        guard !attempted else { return }
        attempted = true
        let url = assets.appendingPathComponent("fonts/ZCOOLKuaiLe-Regular.ttf")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
            NSLog("注册提醒气泡字体失败: %@", error?.takeRetainedValue().localizedDescription ?? "未知错误")
        }
    }
    static func font(_ size: CGFloat) -> NSFont {
        NSFont(name: "ZCOOL KuaiLe", size: size)
            ?? NSFont(name: "ZCOOLKuaiLe-Regular", size: size)
            ?? NSFont.systemFont(ofSize: size)
    }
}

enum Palette {
    static let ink = NSColor(srgbRed: 0.286, green: 0.216, blue: 0.165, alpha: 1)
    static let muted = NSColor(srgbRed: 0.592, green: 0.514, blue: 0.427, alpha: 1)
    static let paper = NSColor(srgbRed: 1, green: 0.98, blue: 0.94, alpha: 1)
    static let line = NSColor(srgbRed: 0.91, green: 0.86, blue: 0.78, alpha: 1)
    static let green = NSColor(srgbRed: 0.32, green: 0.40, blue: 0.28, alpha: 1)
    static let cream = NSColor(srgbRed: 1, green: 0.96, blue: 0.84, alpha: 1)
}

// 清爽绿仅用于设置面板；提醒回应区保持原有暖色，避免角色画面旁出现两套视觉。
// 所有文字与按钮配色经对比度检查：正文 ≥ 5.2:1，按钮文字 ≥ 6.2:1。
enum SettingsPalette {
    static let ink = NSColor(srgbRed: 0.071, green: 0.239, blue: 0.153, alpha: 1)      // #123D27
    static let muted = NSColor(srgbRed: 0.271, green: 0.435, blue: 0.345, alpha: 1)    // #456F58
    static let accent = NSColor(srgbRed: 0.169, green: 0.451, blue: 0.314, alpha: 1)   // #2B7350
    static let top = NSColor(srgbRed: 0.929, green: 0.976, blue: 0.945, alpha: 1)      // #EDF9F1
    static let bottom = NSColor(srgbRed: 0.984, green: 0.996, blue: 0.988, alpha: 1)   // #FBFEFC
    static let line = NSColor(srgbRed: 0.749, green: 0.902, blue: 0.820, alpha: 1)     // #BFE6D1
    static let primaryFill = NSColor(srgbRed: 0.263, green: 0.788, blue: 0.541, alpha: 1)  // #43C98A
    static let primaryInk = NSColor(srgbRed: 0.043, green: 0.220, blue: 0.129, alpha: 1)   // #0B3821
    static let primaryBorder = NSColor(srgbRed: 0.082, green: 0.478, blue: 0.294, alpha: 1) // #157A4B
    static let softFill = NSColor(srgbRed: 0.910, green: 0.969, blue: 0.929, alpha: 1) // #E8F7ED
    static let softInk = NSColor(srgbRed: 0.184, green: 0.373, blue: 0.286, alpha: 1)  // #2F5F49
    static let softBorder = NSColor(srgbRed: 0.663, green: 0.851, blue: 0.737, alpha: 1) // #A9D9BC
}

final class ActionButton: NSButton {
    var onClick: (() -> Void)?
    var fill = Palette.paper
    var ink = Palette.ink
    var border = Palette.line
    var pill = true
    var cornerRadius: CGFloat = 8
    var hover = false
    private var hoverTracking: NSTrackingArea?

    init(_ title: String, frame: NSRect = .zero, fill: NSColor = Palette.paper, ink: NSColor = Palette.ink) {
        super.init(frame: frame)
        self.title = title; self.fill = fill; self.ink = ink
        isBordered = false; target = self; action = #selector(invoke)
        font = NSFont.systemFont(ofSize: 11)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func invoke() { onClick?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let tracking = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(tracking); hoverTracking = tracking
    }
    override func mouseEntered(with event: NSEvent) { hover = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hover = false; needsDisplay = true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: isEnabled ? .pointingHand : .arrow) }
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: pill ? rect.height / 2 : cornerRadius, yRadius: pill ? rect.height / 2 : cornerRadius)
        if fill.alphaComponent > 0 {
            (hover && isEnabled ? fill.blended(withFraction: 0.08, of: .white)! : fill).withAlphaComponent(isEnabled ? 0.96 : 0.65).setFill()
            path.fill()
        }
        border.withAlphaComponent(0.75).setStroke(); path.lineWidth = 1; path.stroke()
        let attrs: [NSAttributedString.Key: Any] = [.font: font!, .foregroundColor: ink.withAlphaComponent(isEnabled ? 1 : 0.65)]
        let size = title.size(withAttributes: attrs)
        title.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attrs)
        if window?.firstResponder === self {
            NSColor.keyboardFocusIndicatorColor.setStroke()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 8, yRadius: 8).stroke()
        }
    }
}

final class FloatingPanel: NSPanel {
    var escape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { escape?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { escape?() } else { super.keyDown(with: event) }
    }
    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        backgroundColor = .clear; isOpaque = false; hasShadow = false
        level = .statusBar; hidesOnDeactivate = false; isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovable = false; animationBehavior = .none
    }
}

final class CharacterView: NSView {
    let playerLayer = AVPlayerLayer()
    let stillView = NSImageView()
    var onClick: (() -> Void)?
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        playerLayer.backgroundColor = NSColor.clear.cgColor
        playerLayer.isOpaque = false
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
        stillView.imageScaling = .scaleProportionallyUpOrDown
        stillView.isHidden = true
        addSubview(stillView)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        playerLayer.frame = bounds; stillView.frame = bounds
        CATransaction.commit()
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func accessibilityPerformPress() -> Bool { onClick?(); return true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}

// 动画下方的文字气泡与 Windows 原生版一致：奶油底圆角气泡内一行排开
// 标题、倒计时（仅眼睛休息）、完成、稍后和关闭；尺寸随内容收缩，贴在动画正下方。
final class ReminderCardView: NSView {
    let title = NSTextField(labelWithString: "")
    let counter = NSTextField(labelWithString: "")
    let done = ActionButton("喝好了", fill: CaptionPalette.doneFill, ink: CaptionPalette.doneInk)
    let later = ActionButton("稍后", fill: .clear, ink: CaptionPalette.ink)
    let close = ActionButton("×", fill: .clear, ink: CaptionPalette.ink)
    var kind: ReminderKind = .water
    var titleText = "喝口水吧"
    var remaining = 20
    var ready = false
    var onEscape: (() -> Void)?
    var onSizeChange: (() -> Void)?

    private let bubbleRadius: CGFloat = 13.5      // 18 DIU
    private let padLeading: CGFloat = 9           // 12 DIU
    private let padY: CGFloat = 6                 // 8 DIU
    private let padTrailing: CGFloat = 6          // 8 DIU
    private let titleGap: CGFloat = 7             // 9 DIU
    private let itemGap: CGFloat = 6              // 8 DIU
    private let titleSize: CGFloat = 14.25        // 19 DIU
    private let controlSize: CGFloat = 10.5       // 14 DIU

    override init(frame: NSRect) {
        super.init(frame: frame)
        title.textColor = CaptionPalette.title
        counter.textColor = CaptionPalette.counter
        [done, later, close].forEach {
            $0.pill = false; $0.cornerRadius = 7.5; $0.border = CaptionPalette.line
        }
        [title, counter, done, later, close].forEach(addSubview)
        close.setAccessibilityLabel("关闭提醒")
        setAccessibilityRole(.group)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private struct Row {
        var title: NSSize = .zero, counter: NSSize = .zero, button: NSSize = .zero
        var doneWidth: CGFloat = 0, laterWidth: CGFloat = 0, closeWidth: CGFloat = 0
        var counterVisible = false
        var total: NSSize = .zero
    }
    private func measure() -> Row {
        title.font = CaptionFont.font(titleSize)
        counter.font = CaptionFont.font(controlSize)
        [done, later, close].forEach { $0.font = CaptionFont.font(controlSize) }
        title.stringValue = titleText
        title.sizeToFit()
        var row = Row()
        row.title = title.fittingSize
        row.counterVisible = kind == .eyes
        if row.counterVisible {
            counter.stringValue = remaining == 0 ? "✓" : "\(remaining) 秒"
            counter.sizeToFit()
            row.counter = counter.fittingSize
        }
        let line = title.font!.boundingRectForFont.height
        row.button = NSSize(width: 0, height: ceil(CaptionFont.font(controlSize).boundingRectForFont.height) + 8)
        func buttonWidth(_ button: NSButton, _ padX: CGFloat) -> CGFloat {
            ceil(button.title.size(withAttributes: [.font: button.font!]).width) + padX * 2 + 2
        }
        row.doneWidth = buttonWidth(done, 7)   // 9 DIU
        row.laterWidth = buttonWidth(later, 5) // 7 DIU
        row.closeWidth = buttonWidth(close, 3) // 4 DIU
        let rowHeight = max(line, row.button.height)
        var width = padLeading + row.title.width + titleGap + row.doneWidth + itemGap + row.laterWidth + itemGap + row.closeWidth + padTrailing
        if row.counterVisible { width += row.counter.width + itemGap }
        row.total = NSSize(width: ceil(width), height: ceil(rowHeight + padY * 2))
        return row
    }
    func contentSize() -> NSSize { measure().total }

    override func layout() {
        super.layout()
        let row = measure()
        counter.isHidden = !row.counterVisible
        let rowY = (bounds.height - max(row.title.height, row.button.height)) / 2
        var x = padLeading
        title.frame = NSRect(x: x, y: (bounds.height - row.title.height) / 2, width: row.title.width, height: row.title.height)
        x += row.title.width + titleGap
        if row.counterVisible {
            counter.frame = NSRect(x: x, y: (bounds.height - row.counter.height) / 2, width: row.counter.width, height: row.counter.height)
            x += row.counter.width + itemGap
        }
        done.frame = NSRect(x: x, y: rowY, width: row.doneWidth, height: row.button.height)
        later.frame = NSRect(x: done.frame.maxX + itemGap, y: rowY, width: row.laterWidth, height: row.button.height)
        close.frame = NSRect(x: later.frame.maxX + itemGap, y: rowY, width: row.closeWidth, height: row.button.height)
    }
    func update(session: ReminderSession, now: Double) {
        kind = session.kind; ready = session.stage == .ready
        titleText = kind == .eyes && ready ? "好啦，慢慢回来" : kind.title
        remaining = session.remaining(now: now)
        done.title = kind == .eyes && !ready ? "陪你休息中…" : kind.doneTitle
        done.isEnabled = ready
        done.setAccessibilityLabel(done.title)
        later.toolTip = "\(kind.snoozeMinutes) 分钟后提醒"
        later.setAccessibilityLabel(later.toolTip)
        setAccessibilityLabel(kind == .eyes ? "\(titleText)，剩余 \(remaining) 秒" : titleText)
        let size = contentSize()
        if size != bounds.size { onSizeChange?() } else { needsLayout = true }
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        CaptionPalette.bubble.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bubbleRadius, yRadius: bubbleRadius).fill()
    }
}

final class SettingsView: NSView {
    // 下拉档位覆盖常用提醒节奏；存档中的其他历史数值作为附加项保留显示，不被吞掉。
    static let presets = [5, 10, 15, 20, 25, 30, 40, 45, 50, 60, 90, 120]
    var pickers: [ReminderKind: NSPopUpButton] = [:]
    let status = NSTextField(labelWithString: "修改的项目从保存时重新计时")
    let save = ActionButton("保存", fill: SettingsPalette.primaryFill, ink: SettingsPalette.primaryInk)
    let close = ActionButton("×", fill: SettingsPalette.softFill, ink: SettingsPalette.softInk)
    let customCharacter = ActionButton("自定义形象", fill: SettingsPalette.softFill, ink: SettingsPalette.softInk)
    private let background = CAGradientLayer()
    var onSave: (([String: Any]) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        // 面板为固定的浅色设计，系统深色外观下也要保留下拉框的浅色可读样式。
        appearance = NSAppearance(named: .aqua)
        background.colors = [SettingsPalette.top.cgColor, SettingsPalette.bottom.cgColor]
        background.startPoint = CGPoint(x: 0.5, y: 1); background.endPoint = CGPoint(x: 0.5, y: 0)
        background.cornerRadius = 24; background.masksToBounds = true
        background.borderWidth = 1; background.borderColor = SettingsPalette.line.cgColor
        layer?.addSublayer(background)
        func label(_ text: String, _ frame: NSRect, size: CGFloat, color: NSColor, weight: NSFont.Weight = .regular) {
            let field = NSTextField(labelWithString: text); field.frame = frame
            field.font = .systemFont(ofSize: size, weight: weight); field.textColor = color
            addSubview(field)
        }
        label("GUGUGAGA", NSRect(x: 24, y: 262, width: 200, height: 14), size: 9, color: SettingsPalette.accent, weight: .medium)
        label("提醒设置", NSRect(x: 24, y: 223, width: 220, height: 32), size: 23, color: SettingsPalette.ink, weight: .semibold)
        customCharacter.frame = NSRect(x: 254, y: 211, width: 112, height: 28)
        customCharacter.border = SettingsPalette.softBorder
        addSubview(customCharacter)
        label("平时安静等待，到时间再出来提醒你。", NSRect(x: 24, y: 188, width: 342, height: 18), size: 11, color: SettingsPalette.muted)
        label("提醒间隔", NSRect(x: 24, y: 153, width: 180, height: 20), size: 12, color: SettingsPalette.ink, weight: .semibold)
        for (i, kind) in [ReminderKind.water, .walk, .eyes].enumerated() {
            let x = CGFloat(24 + i * 117)
            let emoji = kind == .water ? "💧" : kind == .walk ? "🐧" : "👀"
            label("\(emoji) \(kind.label)", NSRect(x: x, y: 124, width: 110, height: 18), size: 10, color: SettingsPalette.ink)
            let picker = NSPopUpButton(frame: NSRect(x: x, y: 81, width: 108, height: 28), pullsDown: false)
            picker.font = .systemFont(ofSize: 13)
            picker.setAccessibilityLabel("\(kind.label)提醒间隔（分钟）")
            pickers[kind] = picker; addSubview(picker)
        }
        pickers[.water]?.nextKeyView = pickers[.walk]
        pickers[.walk]?.nextKeyView = pickers[.eyes]
        pickers[.eyes]?.nextKeyView = save
        save.nextKeyView = customCharacter
        customCharacter.nextKeyView = close
        status.frame = NSRect(x: 24, y: 25, width: 260, height: 32)
        status.font = .systemFont(ofSize: 10); status.textColor = SettingsPalette.muted
        status.maximumNumberOfLines = 2; status.setAccessibilityRole(.staticText)
        addSubview(status)
        save.frame = NSRect(x: 310, y: 27, width: 56, height: 31); save.pill = false
        save.border = SettingsPalette.primaryBorder
        save.onClick = { [weak self] in self?.submit() }
        addSubview(save)
        close.frame = NSRect(x: 338, y: 252, width: 29, height: 29)
        close.border = SettingsPalette.softBorder
        close.setAccessibilityLabel("关闭设置"); addSubview(close)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        background.frame = bounds
        CATransaction.commit()
    }
    func load(_ intervals: [ReminderKind: Int]) {
        for (kind, picker) in pickers {
            picker.removeAllItems()
            let minutes = intervals[kind]!
            let options = Self.presets.contains(minutes) ? Self.presets : (Self.presets + [minutes]).sorted()
            for option in options {
                picker.addItem(withTitle: "\(option) 分钟")
                picker.lastItem?.representedObject = option
            }
            select(minutes, for: kind)
        }
        status.stringValue = "修改的项目从保存时重新计时"
    }
    func select(_ minutes: Int, for kind: ReminderKind) {
        guard let item = pickers[kind]?.itemArray.first(where: { $0.representedObject as? Int == minutes }) else { return }
        pickers[kind]?.select(item)
    }
    func submit() {
        var values: [String: Any] = [:]
        for (kind, picker) in pickers {
            guard let minutes = picker.selectedItem?.representedObject as? Int else { return }
            values[kind.rawValue] = minutes
        }
        onSave?(values)
    }
}
