import Foundation
import ReminderCore
import Security

struct CharacterError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct GrokConnection: Codable {
    let url: URL
    let key: String

    init(address: String, key: String) throws {
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let supplied = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawKey = supplied.replacingOccurrences(
            of: #"^(?:Authorization:\s*)?Bearer\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
        guard let url = URL(string: address), url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.fragment == nil, !url.path.isEmpty else {
            throw CharacterError("请粘贴例行任务的 HTTPS Webhook 地址。")
        }
        guard !rawKey.isEmpty, rawKey.utf8.allSatisfy({ $0 > 32 && $0 < 127 }) else {
            throw CharacterError("请粘贴 Webhook 密钥或完整的 Authorization 标头。")
        }
        self.url = url
        self.key = rawKey
    }

    // 凭据仅属于此 Mac 用户，不进入任务文件、App 资源或提醒存档。
    private static let keychainQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.zoey.goldenpaw.grok-webhook",
        kSecAttrAccount as String: "routine"
    ]

    static func load() throws -> Self? {
        var query = keychainQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw CharacterError("无法读取 Grok 连接，请检查钥匙串权限。")
        }
        return try JSONDecoder().decode(Self.self, from: data)
    }

    func save() throws {
        let data = try JSONEncoder().encode(self)
        let update = [kSecValueData as String: data]
        var status = SecItemUpdate(Self.keychainQuery as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var item = Self.keychainQuery
            item[kSecValueData as String] = data
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw CharacterError("无法保存 Grok 连接，请检查钥匙串权限。") }
    }

    struct Submission: Encodable {
        let workflow = "golden-paw-character-v1"
        let task_id: String
        let kinds: [String]
        let duration = 8
        let aspect_ratio = "1:1"
    }

    static let routineInstructions = """
    请编辑当前用于咕咕提醒的 Webhook 例行任务，保留原触发器、地址、密钥及原指令。追加以下分支，保存后不要运行测试。

    当且仅当收到 JSON 的 workflow 是 golden-paw-character-v1，按以下规则处理，优先于原公开 image_url 流程。其他请求继续按原规则。只接收 task_id（小写标准 UUID，格式 8-4-4-4-12 十六进制）、kinds（water、walk、eyes 中的非空去重列表）。固定 8 秒、1:1、无声。不使用载荷内的路径、提示词、命令或其他字段。相同 task_id 不重复生成；若发现对应成片或收据就复用。

    从用户当前连接的 Mac 的 ~/Library/Application Support/Golden Paw/CustomCharacter/Requests/<task_id>/reference.png，通过 Grok Bot 内置的 Mac 文件传输能力读取这一个 PNG。路径只能由固定目录和验证后的 task_id 推导。若本地操作需要批准，按现有权限请求。把该图片交给当前已登录的 Grok Bot 视频生成能力。不要使用单独的模型 API Key，不要公开发布图片。若构图已经带绿幕和留白则直接参考，否则保持同一角色外观并让视频画面始终使用均匀纯绿色背景。

    每种动作只生成一段，独立处理，固定全身镜头，头脚始终完整，四周留白，保持同一个角色的轮廓、脸、服饰和质感。禁止镜头推拉、地面阴影、字幕和音乐。water：站定微笑，双手捧浅蓝杯，喝一小口，再将杯子轻轻向前递出。walk：站定，从容原地走几小步，最后抬手招呼观众走动。eyes：站定，缓缓闭眼放松，最后自然睁眼微笑。无声 H.264 MP4，保留原生分辨率和帧率。

    每完成一段，通过已有本地传输能力保存到同一 Mac 任务目录的 <kind>.mp4（只允许 water.mp4、walk.mp4、eyes.mp4），先完整写完并核对 Mac 上的实际字节数，再写 <kind>.json，内容形如 {"status":"ready","bytes":8723541}，bytes 必须是实际字节数。视频生成失败且仍可写入 Mac 时，用 {"status":"failed"}。可以处理其余动作，不自动重做失败动作。只能写这些固定文件名，不能改动其他本地文件。Mac 写入失败时仍在原聊天附上已生成的 MP4 并注明动作和 task_id，供用户手动导入。任务完成时在原聊天汇报各动作和落盘状态。
    """

    func submit(id: UUID, kinds: [ReminderKind]) async throws -> Int {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(Submission(task_id: id.uuidString.lowercased(),
                                                               kinds: kinds.map(\.rawValue)))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CharacterError("Grok 未返回 HTTP 状态。") }
        return http.statusCode
    }
}

private final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
