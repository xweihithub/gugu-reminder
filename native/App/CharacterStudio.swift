import AppKit
import ReminderCore
import UniformTypeIdentifiers

@MainActor
final class CharacterStudio: NSWindowController, NSWindowDelegate {
    private let library: CustomCharacterLibrary
    private let preview = CharacterView(frame: NSRect(x: 0, y: 0, width: 266, height: 266))
    private lazy var player = AnimationPlayer(view: preview)
    private let kindPicker = NSSegmentedControl(labels: CustomCharacterLibrary.kinds.map(\.label),
                                                trackingMode: .selectOne, target: nil, action: nil)
    private let backdrop = NSSegmentedControl(labels: ["浅色", "深色"], trackingMode: .selectOne, target: nil, action: nil)
    private let headline = NSTextField(labelWithString: "")
    private let previewCaption = NSTextField(labelWithString: "")
    private let feedback = NSTextField(wrappingLabelWithString: "")
    private var rows: [ReminderKind: NSTextField] = [:]
    private let choose = ActionButton("选参考图", fill: SettingsPalette.softFill, ink: SettingsPalette.softInk)
    private let generate = ActionButton("生成三段动画", fill: SettingsPalette.primaryFill, ink: SettingsPalette.primaryInk)
    private let regenerate = ActionButton("重做所选动作", fill: SettingsPalette.softFill, ink: SettingsPalette.softInk)
    private let importMovie = ActionButton("导入所选成片", fill: SettingsPalette.softFill, ink: SettingsPalette.softInk)
    private let stop = ActionButton("停止等待", fill: SettingsPalette.softFill, ink: SettingsPalette.softInk)
    private let apply = ActionButton("启用新形象", fill: SettingsPalette.primaryFill, ink: SettingsPalette.primaryInk)
    private let toggle = ActionButton("切回咕咕嘎嘎", fill: SettingsPalette.softFill, ink: SettingsPalette.softInk)
    private let replay = ActionButton("重播预览", fill: SettingsPalette.softFill, ink: SettingsPalette.softInk)
    private var presented: URL?
    private var localFeedback: String?

    init(library: CustomCharacterLibrary) {
        self.library = library
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 618, height: 502),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "自定义形象"
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.isFloatingPanel = true
        window.autorecalculatesKeyViewLoop = true
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = SettingsPalette.bottom
        super.init(window: window)
        window.delegate = self
        build(window.contentView!)
        library.onChange = { [weak self] in
            self?.localFeedback = nil
            self?.refresh()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func open(interactive: Bool) {
        guard let window else { return }
        if !window.isVisible { window.center() }
        if interactive {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            window.ignoresMouseEvents = true
            window.orderFrontRegardless()
        }
        refresh(forcePreview: true)
    }

    func windowWillClose(_ notification: Notification) {
        player.stop()
        presented = nil
    }

    private var kind: ReminderKind { CustomCharacterLibrary.kinds[max(0, kindPicker.selectedSegment)] }

    private func build(_ content: NSView) {
        func place(_ view: NSView, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) {
            view.frame = NSRect(x: x, y: y, width: width, height: height)
            content.addSubview(view)
        }
        func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, muted: Bool = false) -> NSTextField {
            let view = NSTextField(labelWithString: text)
            view.font = .systemFont(ofSize: size, weight: weight)
            view.textColor = muted ? SettingsPalette.muted : SettingsPalette.ink
            return view
        }
        func button(_ button: ActionButton, x: CGFloat, y: CGFloat, width: CGFloat, action: @escaping () -> Void) {
            button.pill = false
            button.border = button.fill == SettingsPalette.primaryFill ? SettingsPalette.primaryBorder : SettingsPalette.softBorder
            button.onClick = action
            place(button, x, y, width, 30)
        }
        let title = label("提醒形象", size: 28, weight: .semibold)
        title.font = CaptionFont.font(28)
        place(title, 24, 449, 260, 36)
        headline.font = .systemFont(ofSize: 12, weight: .medium)
        headline.textColor = SettingsPalette.muted
        place(headline, 26, 422, 365, 22)
        let connect = ActionButton("配置 Grok", fill: SettingsPalette.softFill, ink: SettingsPalette.softInk)
        button(connect, x: 486, y: 448, width: 108) { [weak self] in self?.configure() }

        let previewCard = NSView(frame: .zero)
        previewCard.wantsLayer = true
        previewCard.layer?.cornerRadius = 18
        previewCard.layer?.masksToBounds = true
        previewCard.layer?.borderWidth = 1
        previewCard.layer?.borderColor = SettingsPalette.line.cgColor
        previewCard.addSubview(preview)
        place(previewCard, 24, 133, 266, 266)
        previewCaption.font = .systemFont(ofSize: 11, weight: .medium)
        previewCaption.textColor = SettingsPalette.muted
        place(previewCaption, 26, 103, 126, 20)
        backdrop.selectedSegment = 0
        backdrop.setAccessibilityLabel("预览背景")
        backdrop.target = self
        backdrop.action = #selector(changeBackdrop)
        place(backdrop, 183, 103, 108, 22)
        changeBackdrop()
        button(replay, x: 24, y: 61, width: 95) { [weak self] in self?.refresh(forcePreview: true) }

        place(label("动作", size: 14, weight: .semibold), 315, 379, 195, 22)
        kindPicker.selectedSegment = 0
        kindPicker.setAccessibilityLabel("选择预览或重做的动作")
        kindPicker.target = self
        kindPicker.action = #selector(changeKind)
        place(kindPicker, 315, 347, 280, 25)
        for (index, kind) in CustomCharacterLibrary.kinds.enumerated() {
            let y = CGFloat(312 - index * 26)
            place(label(kind.label, size: 12, weight: .medium), 317, y, 92, 20)
            let status = label("", size: 11, muted: true)
            rows[kind] = status
            place(status, 414, y, 178, 20)
        }
        button(choose, x: 315, y: 218, width: 110) { [weak self] in self?.chooseImage() }
        button(generate, x: 436, y: 218, width: 159) { [weak self] in self?.generateSet() }
        button(regenerate, x: 315, y: 178, width: 132) { [weak self] in
            guard let self else { return }
            self.send([self.kind])
        }
        button(importMovie, x: 458, y: 178, width: 137) { [weak self] in self?.chooseMovie() }
        button(stop, x: 315, y: 139, width: 99) { [weak self] in self?.library.stopWaiting() }
        feedback.font = .systemFont(ofSize: 11)
        feedback.textColor = SettingsPalette.muted
        feedback.maximumNumberOfLines = 4
        place(feedback, 316, 61, 280, 70)

        let rule = NSBox()
        rule.boxType = .separator
        place(rule, 24, 52, 570, 1)
        button(toggle, x: 24, y: 11, width: 122) { [weak self] in
            guard let self else { return }
            self.library.useInstalled(!self.library.usesCustom)
        }
        button(apply, x: 445, y: 11, width: 150) { [weak self] in self?.library.activateDraft() }
    }

    @objc private func changeBackdrop() {
        preview.superview?.layer?.backgroundColor = (backdrop.selectedSegment == 1
            ? NSColor(white: 0.13, alpha: 1) : SettingsPalette.top).cgColor
    }

    @objc private func changeKind() { refresh(forcePreview: true) }

    private func refresh(forcePreview: Bool = false) {
        guard window?.isVisible == true else { return }
        headline.stringValue = library.usesCustom ? "当前使用 · 自定义形象" : "当前使用 · 咕咕嘎嘎"
        for (kind, status) in rows {
            status.stringValue = library.status(for: kind)
            status.toolTip = library.error(for: kind)
        }
        choose.isEnabled = !library.busy
        let remaining = CustomCharacterLibrary.kinds.filter { library.draftAssets(for: $0) == nil }.count
        generate.isEnabled = library.hasDraft && !library.busy && remaining > 0
        generate.title = remaining == 3 ? "生成三段动画" : "生成剩余动画"
        generate.setAccessibilityLabel(generate.title)
        regenerate.isEnabled = library.hasDraft && !library.busy
        regenerate.title = library.draftAssets(for: kind) == nil ? "只生成所选动作" : "重做所选动作"
        regenerate.setAccessibilityLabel(regenerate.title)
        importMovie.isEnabled = library.hasDraft && !library.busy
        stop.isHidden = !library.pending
        stop.isEnabled = library.canStopWaiting
        apply.isEnabled = library.readyToActivate && !library.busy
        toggle.isHidden = !library.hasInstalled
        toggle.title = library.usesCustom ? "切回咕咕嘎嘎" : "启用已保存形象"
        toggle.setAccessibilityLabel(toggle.title)
        let detail = localFeedback ?? library.error(for: kind) ?? library.message
        feedback.stringValue = detail.isEmpty ? "选择一张主体完整的 PNG 或 JPG。生成时参考图会交给已连接的 Grok Bot。" : detail

        let assets = library.previewAssets(for: kind)
        let image = library.reference
        let identity = assets ?? image
        replay.isEnabled = assets != nil
        previewCaption.stringValue = assets == nil ? (image == nil ? "尚未选图" : "参考图") : "\(kind.label) · 透明预览"
        guard forcePreview || presented != identity else { return }
        presented = identity
        if let assets {
            player.start(kind: kind, reduced: false, assets: assets)
        } else {
            player.stop()
            preview.stillView.image = image.flatMap { NSImage(contentsOf: $0) }
            preview.stillView.isHidden = preview.stillView.image == nil
        }
    }

    private func chooseImage() {
        selectFile(title: "选择参考图", types: [.png, .jpeg]) { [weak self] source in self?.library.chooseReference(source) }
    }

    private func chooseMovie() {
        let selected = kind
        selectFile(title: "导入\(selected.label)成片", types: [.mpeg4Movie, .quickTimeMovie]) { [weak self] source in
            self?.library.importClip(source, for: selected)
        }
    }

    private func selectFile(title: String, types: [UTType], handler: @escaping (URL) -> Void) {
        guard let window else { return }
        let picker = NSOpenPanel()
        picker.title = title
        picker.allowedContentTypes = types
        picker.canChooseDirectories = false
        picker.allowsMultipleSelection = false
        picker.beginSheetModal(for: window) { response in
            if response == .OK, let url = picker.url { handler(url) }
        }
    }

    private func generateSet() {
        send(CustomCharacterLibrary.kinds.filter { library.draftAssets(for: $0) == nil })
    }

    private func send(_ kinds: [ReminderKind]) {
        do {
            guard let connection = try GrokConnection.load() else { configure(); return }
            library.generate(kinds, submit: connection.submit)
        } catch {
            localFeedback = error.localizedDescription
            refresh()
        }
    }

    private func configure() {
        guard let window else { return }
        let old = try? GrokConnection.load()
        let address = NSTextField(string: old?.url.absoluteString ?? "")
        address.placeholderString = "Webhook HTTPS 地址"
        address.setAccessibilityLabel("Webhook HTTPS 地址")
        let key = NSSecureTextField()
        key.placeholderString = old == nil ? "Webhook 密钥或 Authorization 标头" : "留空可沿用同一地址的密钥"
        key.setAccessibilityLabel("Webhook 密钥")
        let alert = NSAlert()
        alert.messageText = "连接已登录的 Grok Bot"
        alert.informativeText = "在 Grok 例行任务里加入配置说明，再复制该任务的 Webhook 地址和密钥。连接存入 Mac 钥匙串。"
        alert.addButton(withTitle: "保存连接")
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: "复制配置说明")
        let fields = NSView(frame: NSRect(x: 0, y: 0, width: 330, height: 67))
        address.frame = NSRect(x: 0, y: 37, width: 330, height: 24)
        key.frame = NSRect(x: 0, y: 5, width: 330, height: 24)
        fields.addSubview(address)
        fields.addSubview(key)
        alert.accessoryView = fields
        alert.window.initialFirstResponder = address
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            if response == .alertThirdButtonReturn {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(GrokConnection.routineInstructions, forType: .string)
                self.localFeedback = "已复制配置说明，粘贴给 Grok 编辑现有例行任务。"
            } else if response == .alertFirstButtonReturn {
                do {
                    let value = address.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    let secret = key.stringValue.isEmpty && old?.url.absoluteString == value ? old?.key ?? "" : key.stringValue
                    try GrokConnection(address: value, key: secret).save()
                    self.localFeedback = "Grok 连接已保存。"
                } catch { self.localFeedback = error.localizedDescription }
            }
            self.refresh()
        }
    }
}
