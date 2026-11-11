import Foundation
import ReminderCore

@MainActor
final class CustomCharacterLibrary {
    static let kinds: [ReminderKind] = [.water, .walk, .eyes]
    private static let jobTimeout: TimeInterval = 25 * 60

    struct Character: Codable {
        var id = UUID()
        var clips: [String: UUID] = [:]
    }

    struct Job: Codable {
        var id = UUID()
        var outstanding: [String]
        var started = Date()
    }

    private struct State: Codable {
        var active: Character?
        var draft: Character?
        var useCustom = false
        var pending: Job?
        var errors: [String: String] = [:]
    }

    let root: URL
    private let files = FileManager.default
    private var state: State
    private var operation = false
    var onChange: (() -> Void)?
    private(set) var message = ""

    init(root: URL) {
        self.root = root
        state = (try? Data(contentsOf: root.appendingPathComponent("library.json")))
            .flatMap { try? JSONDecoder().decode(State.self, from: $0) } ?? State()
    }

    var hasDraft: Bool { state.draft != nil }
    var hasInstalled: Bool { state.active != nil }
    var usesCustom: Bool { state.useCustom && hasInstalled }
    var pending: Bool { state.pending != nil }
    var busy: Bool { operation || pending }
    var canStopWaiting: Bool { pending && !operation }
    var readyToActivate: Bool { Self.kinds.allSatisfy { draftAssets(for: $0) != nil } }
    var reference: URL? { (state.draft ?? state.active).map { profile($0).appendingPathComponent("reference.png") } }

    func removeUnusedProfiles() {
        // 仅在启动且确认没有旧版 App 在播放时清理已替换的形象。
        guard hasInstalled || hasDraft else { return }
        let retained = Set([state.active?.id, state.draft?.id].compactMap { $0 })
        let profiles = root.appendingPathComponent("Profiles", isDirectory: true)
        guard let folders = try? files.contentsOfDirectory(at: profiles, includingPropertiesForKeys: nil) else { return }
        for folder in folders {
            guard let id = UUID(uuidString: folder.lastPathComponent), !retained.contains(id) else { continue }
            try? files.removeItem(at: folder)
        }
    }

    func playbackAssets(for kind: ReminderKind) -> URL? {
        guard usesCustom else { return nil }
        return availableAssets(for: kind, in: state.active)
    }

    func draftAssets(for kind: ReminderKind) -> URL? {
        availableAssets(for: kind, in: state.draft)
    }

    func previewAssets(for kind: ReminderKind) -> URL? {
        hasDraft ? draftAssets(for: kind) : availableAssets(for: kind, in: state.active)
    }

    static func movie(in folder: URL, kind: ReminderKind) -> URL {
        folder.appendingPathComponent("gugugaga-\(kind.rawValue)-alpha.mov")
    }

    static func still(in folder: URL, kind: ReminderKind) -> URL {
        folder.appendingPathComponent("gugugaga-\(kind.rawValue)-rest.png")
    }

    func status(for kind: ReminderKind) -> String {
        if state.pending?.outstanding.contains(kind.rawValue) == true { return "等待 Grok 成片" }
        if state.errors[kind.rawValue] != nil {
            return draftAssets(for: kind) == nil ? "需重做" : "保留上一版"
        }
        if previewAssets(for: kind) != nil { return "可预览" }
        return "待生成"
    }

    func error(for kind: ReminderKind) -> String? { state.errors[kind.rawValue] }

    func chooseReference(_ source: URL) {
        guard !busy else { return }
        let next = Character()
        let folder = profile(next)
        let destination = folder.appendingPathComponent("reference.png")
        operation = true
        show("正在准备参考图…")
        Task {
            do {
                try createDirectory(folder)
                try await Task.detached(priority: .userInitiated) {
                    try CharacterMedia.prepareReference(from: source, to: destination)
                }.value
                let oldDraft = state.draft
                var updated = state
                updated.draft = next
                updated.errors = [:]
                try save(updated)
                if let oldDraft { try? files.removeItem(at: profile(oldDraft)) }
                message = "选图完成。确认主体完整后即可生成。"
            } catch {
                try? files.removeItem(at: folder)
                message = error.localizedDescription
            }
            operation = false
            onChange?()
        }
    }

    func generate(_ kinds: [ReminderKind], submit: @escaping (UUID, [ReminderKind]) async throws -> Int) {
        guard let draft = state.draft, !busy, !kinds.isEmpty else { return }
        let job = Job(outstanding: kinds.map(\.rawValue))
        let folder = request(job)
        do {
            try createDirectory(folder)
            try files.copyItem(at: profile(draft).appendingPathComponent("reference.png"),
                               to: folder.appendingPathComponent("reference.png"))
            var updated = state
            updated.pending = job
            for kind in kinds { updated.errors.removeValue(forKey: kind.rawValue) }
            // 先保存请求身份。退出、超时或断网后恢复等待同一任务，避免重复扣用量。
            try save(updated)
        } catch {
            try? files.removeItem(at: folder)
            show(error.localizedDescription)
            return
        }
        operation = true
        show("正在向 Grok 提交…")
        Task {
            defer {
                operation = false
                onChange?()
                checkForResults()
            }
            do {
                let status = try await submit(job.id, kinds)
                if status == 200 {
                    message = "Grok 已接收。若 Grok 请求本地文件权限，请在 Grok 中确认。"
                } else {
                    // 服务器错误可能发生在任务启动后。保留原任务等待，不自动重试。
                    if status < 500 {
                        try failJob(job, note: "Grok 返回 HTTP \(status)，请检查例行任务和 Webhook。")
                        try? files.removeItem(at: folder)
                    } else {
                        message = "Grok 返回 HTTP \(status)，接收状态未知。仍在等待本次任务。"
                    }
                }
            } catch {
                message = "暂时无法确认 Grok 是否已接收。仍在等待本次任务。"
            }
        }
    }

    func checkForResults() {
        guard !operation, let job = state.pending, let draft = state.draft else { return }
        for kind in job.outstanding.compactMap(ReminderKind.init(rawValue:)) {
            let folder = request(job)
            let source = folder.appendingPathComponent("\(kind.rawValue).mp4")
            let receipt = folder.appendingPathComponent("\(kind.rawValue).json")
            guard let info = try? receipt.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
                  info.isRegularFile == true, info.isSymbolicLink != true, let size = info.fileSize, size < 4096,
                  let record = try? Data(contentsOf: receipt), record.count < 4096,
                  let result = try? JSONDecoder().decode(ResultReceipt.self, from: record) else { continue }
            if result.status == "failed" {
                do { try finish(kind, in: job, issue: "Grok 未能生成该动作，请查看 Grok 聊天。") }
                catch { show(error.localizedDescription) }
                return
            }
            if result.status == "ready", let bytes = result.bytes, bytes > 0,
               isCompleteFile(source, bytes: bytes) {
                process(source, for: kind, draft: draft, job: job)
                return
            }
        }
        if Date().timeIntervalSince(job.started) >= Self.jobTimeout {
            do { try failJob(job, note: "等待 Grok 成片超时。可以查看 Grok 聊天或手动导入。") }
            catch { show(error.localizedDescription) }
        }
    }

    func importClip(_ source: URL, for kind: ReminderKind) {
        guard let draft = state.draft, !busy else { return }
        process(source, for: kind, draft: draft, job: nil)
    }

    func stopWaiting() {
        guard let job = state.pending, !operation else { return }
        do { try failJob(job, note: "已停止等待，Grok 端可能仍在处理。") }
        catch { show(error.localizedDescription) }
    }

    func activateDraft() {
        guard let draft = state.draft, readyToActivate, !busy else { return }
        do {
            var updated = state
            updated.active = draft
            updated.useCustom = true
            updated.draft = nil
            updated.errors = [:]
            try save(updated)
            show("已启用。下次定时提醒会使用新形象。")
        } catch { show(error.localizedDescription) }
    }

    func useInstalled(_ enabled: Bool) {
        guard hasInstalled else { return }
        var updated = state
        updated.useCustom = enabled
        do {
            try save(updated)
            show(enabled ? "已启用自定义形象。" : "已切回咕咕嘎嘎。")
        } catch { show(error.localizedDescription) }
    }

    private struct ResultReceipt: Decodable {
        let status: String
        let bytes: Int?
    }

    private func process(_ source: URL, for kind: ReminderKind, draft: Character, job: Job?) {
        let version = UUID()
        let folder = profile(draft).appendingPathComponent(version.uuidString, isDirectory: true)
        let movie = Self.movie(in: folder, kind: kind)
        let still = Self.still(in: folder, kind: kind)
        operation = true
        show("正在处理\(kind.label)的透明动画…")
        Task {
            defer {
                operation = false
                onChange?()
            }
            do {
                try createDirectory(folder)
                try await Task.detached(priority: .userInitiated) {
                    try await CharacterMedia.importClip(source, movie: movie, still: still)
                }.value
                let previous = state.draft?.clips[kind.rawValue]
                var updated = state
                updated.draft?.clips[kind.rawValue] = version
                updated.errors.removeValue(forKey: kind.rawValue)
                let ended = advance(kind, in: &updated)
                try save(updated)
                if let previous { try? files.removeItem(at: profile(draft).appendingPathComponent(previous.uuidString)) }
                if let ended { try? files.removeItem(at: request(ended)) }
                message = "\(kind.label)已准备好，可预览。"
            } catch {
                try? files.removeItem(at: folder)
                let note = error.localizedDescription
                if let job {
                    do { try finish(kind, in: job, issue: note) }
                    catch { message = error.localizedDescription }
                } else {
                    message = note
                }
            }
        }
    }

    private func finish(_ kind: ReminderKind, in job: Job, issue: String) throws {
        guard state.pending?.id == job.id else { return }
        var updated = state
        updated.errors[kind.rawValue] = issue
        _ = advance(kind, in: &updated)
        try save(updated)
        show("\(kind.label) · \(issue)")
    }

    private func failJob(_ job: Job, note: String) throws {
        var updated = state
        for kind in job.outstanding { updated.errors[kind] = note }
        updated.pending = nil
        try save(updated)
        show(note)
    }

    private func advance(_ kind: ReminderKind, in updated: inout State) -> Job? {
        updated.pending?.outstanding.removeAll { $0 == kind.rawValue }
        guard let job = updated.pending, job.outstanding.isEmpty else { return nil }
        updated.pending = nil
        return job
    }

    private func isCompleteFile(_ url: URL, bytes: Int) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]) else {
            return false
        }
        return values.isRegularFile == true && values.isSymbolicLink != true && values.fileSize == bytes
    }

    private func availableAssets(for kind: ReminderKind, in character: Character?) -> URL? {
        guard let character, let revision = character.clips[kind.rawValue] else { return nil }
        let folder = profile(character).appendingPathComponent(revision.uuidString, isDirectory: true)
        guard files.fileExists(atPath: Self.movie(in: folder, kind: kind).path),
              files.fileExists(atPath: Self.still(in: folder, kind: kind).path) else { return nil }
        return folder
    }

    private func profile(_ character: Character) -> URL {
        root.appendingPathComponent("Profiles", isDirectory: true).appendingPathComponent(character.id.uuidString, isDirectory: true)
    }

    private func request(_ job: Job) -> URL {
        root.appendingPathComponent("Requests", isDirectory: true).appendingPathComponent(job.id.uuidString.lowercased(), isDirectory: true)
    }

    private func createDirectory(_ url: URL) throws {
        try files.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }

    private func save(_ value: State) throws {
        try createDirectory(root)
        try JSONEncoder().encode(value).write(to: root.appendingPathComponent("library.json"), options: .atomic)
        state = value
    }

    private func show(_ text: String) {
        message = text
        onChange?()
    }
}
