import AppKit
import AVFoundation
import ReminderCore

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
    static let field = NSColor(srgbRed: 0.957, green: 0.992, blue: 0.969, alpha: 1)    // #F4FDF7
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
        let path = NSBezierPath(roundedRect: rect, xRadius: pill ? rect.height / 2 : 8, yRadius: pill ? rect.height / 2 : 8)
        (hover && isEnabled ? fill.blended(withFraction: 0.08, of: .white)! : fill).withAlphaComponent(isEnabled ? 0.96 : 0.65).setFill()
        path.fill()
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

final class ReminderCardView: NSView {
    let done = ActionButton("喝好了", fill: NSColor(srgbRed: 0.60, green: 0.88, blue: 0.86, alpha: 1), ink: NSColor(srgbRed: 0.09, green: 0.29, blue: 0.28, alpha: 1))
    let later = ActionButton("稍后")
    let close = ActionButton("×", fill: NSColor(srgbRed: 0.27, green: 0.21, blue: 0.15, alpha: 0.7), ink: Palette.paper)
    var kind: ReminderKind = .water
    var titleText = "喝口水吧"
    var remaining = 20
    var progress = 0.0
    var ready = false
    var onEscape: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        [done, later, close].forEach(addSubview)
        close.setAccessibilityLabel("关闭提醒")
        setAccessibilityRole(.group)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        let width: CGFloat = kind == .eyes && !ready ? 116 : 88
        done.frame = NSRect(x: (bounds.width - width - 76) / 2, y: 1, width: width, height: 32)
        later.frame = NSRect(x: done.frame.maxX + 10, y: 1, width: 66, height: 32)
        close.frame = NSRect(x: bounds.width - 28, y: bounds.height - 28, width: 27, height: 27)
    }
    func update(session: ReminderSession, now: Double) {
        kind = session.kind; ready = session.stage == .ready
        titleText = kind == .eyes && ready ? "好啦，慢慢回来" : kind.title
        remaining = session.remaining(now: now); progress = session.progress(now: now)
        done.title = kind == .eyes && !ready ? "陪你休息中…" : kind.doneTitle
        done.isEnabled = ready
        done.setAccessibilityLabel(done.title)
        later.toolTip = "\(kind.snoozeMinutes) 分钟后提醒"
        later.setAccessibilityLabel(later.toolTip)
        setAccessibilityLabel(kind == .eyes ? "\(titleText)，剩余 \(remaining) 秒" : titleText)
        needsLayout = true; needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        let shadow = NSShadow(); shadow.shadowColor = NSColor(srgbRed: 0.29, green: 0.18, blue: 0.11, alpha: 0.8)
        shadow.shadowOffset = NSSize(width: 0, height: -2); shadow.shadowBlurRadius = 4
        let fontSize = min(46, max(30, (window?.screen?.visibleFrame.width ?? 1200) * 0.04))
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont(name: "Songti SC Bold", size: fontSize) ?? NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: Palette.cream, .shadow: shadow,
            .strokeColor: NSColor(srgbRed: 0.58, green: 0.40, blue: 0.24, alpha: 1), .strokeWidth: -1,
            .kern: 3
        ]
        let size = titleText.size(withAttributes: attrs)
        titleText.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: bounds.height - size.height - 3), withAttributes: attrs)
        if kind == .eyes {
            let track = NSRect(x: (bounds.width - 190) / 2, y: 51, width: 126, height: 3)
            NSColor.gray.withAlphaComponent(0.4).setFill()
            NSBezierPath(roundedRect: track, xRadius: 2, yRadius: 2).fill()
            NSColor(srgbRed: 0.72, green: 0.95, blue: 0.91, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: track.minX, y: track.minY, width: track.width * progress, height: 3), xRadius: 2, yRadius: 2).fill()
            let text = remaining == 0 ? "✓ 秒" : "\(remaining) 秒"
            text.draw(at: NSPoint(x: track.maxX + 12, y: 45), withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium), .foregroundColor: Palette.cream, .shadow: shadow])
        }
    }
}

final class SettingsView: NSView {
    var fields: [ReminderKind: NSTextField] = [:]
    let status = NSTextField(labelWithString: "修改的项目从保存时重新计时")
    let save = ActionButton("保存", fill: SettingsPalette.primaryFill, ink: SettingsPalette.primaryInk)
    let close = ActionButton("×", fill: SettingsPalette.softFill, ink: SettingsPalette.softInk)
    private let background = CAGradientLayer()
    var onSave: (([String: Any]) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
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
        label("平时安静等待，到时间再出来提醒你。", NSRect(x: 24, y: 188, width: 342, height: 18), size: 11, color: SettingsPalette.muted)
        label("提醒间隔", NSRect(x: 24, y: 153, width: 180, height: 20), size: 12, color: SettingsPalette.ink, weight: .semibold)
        label("单位：分钟", NSRect(x: 300, y: 155, width: 70, height: 16), size: 9, color: SettingsPalette.muted)
        for (i, kind) in [ReminderKind.water, .walk, .eyes].enumerated() {
            let x = CGFloat(24 + i * 117)
            let emoji = kind == .water ? "💧" : kind == .walk ? "🐧" : "👀"
            label("\(emoji) \(kind.label)", NSRect(x: x, y: 124, width: 110, height: 18), size: 10, color: SettingsPalette.ink)
            let field = NSTextField(frame: NSRect(x: x, y: 78, width: 108, height: 35))
            field.font = .systemFont(ofSize: 13); field.textColor = SettingsPalette.ink
            field.backgroundColor = SettingsPalette.field; field.isBezeled = true; field.bezelStyle = .roundedBezel
            field.setAccessibilityLabel("\(kind.label)提醒间隔（分钟）")
            fields[kind] = field; addSubview(field)
        }
        fields[.water]?.nextKeyView = fields[.walk]
        fields[.walk]?.nextKeyView = fields[.eyes]
        fields[.eyes]?.nextKeyView = save
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
        for (kind, field) in fields { field.stringValue = String(intervals[kind]!) }
    }
    func submit() {
        var values: [String: Any] = [:]
        for (kind, field) in fields {
            let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let number = Int(text), (1...1440).contains(number) else {
                status.stringValue = ReminderError.invalidInterval.localizedDescription
                window?.makeFirstResponder(field); return
            }
            values[kind.rawValue] = number
        }
        onSave?(values)
    }
}
