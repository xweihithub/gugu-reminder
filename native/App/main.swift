import AppKit
import Foundation

let app = NSApplication.shared
let arguments = CommandLine.arguments
let verificationDirectory: URL? = arguments.firstIndex(of: "--verify").flatMap { index in
    guard index + 1 < arguments.count else { return nil }
    return URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
}
let stateURL: URL
if let verificationDirectory {
    stateURL = verificationDirectory.appendingPathComponent("state.json")
    try FileManager.default.createDirectory(at: verificationDirectory, withIntermediateDirectories: true)
    let now = Date().timeIntervalSince1970 * 1000
    let seed: [String: Any] = ["resident": true, "preferences": ["旧版偏好"],
        "reminders": ["intervals": ["water": 60, "walk": 50, "eyes": 40],
                      "next": ["water": now + 1500, "walk": now + 3600000, "eyes": now + 3600000]]]
    try JSONSerialization.data(withJSONObject: seed).write(to: stateURL, options: .atomic)
} else {
    stateURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Golden Paw/state.json")
}
let assets = Bundle.main.resourceURL!.appendingPathComponent("Assets", isDirectory: true)
CaptionFont.register(assets: assets)
let controller = AppController(stateURL: stateURL, assets: assets, verificationDirectory: verificationDirectory)
app.delegate = controller
app.run()
