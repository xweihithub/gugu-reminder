// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GuguReminder",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "GuguReminder", targets: ["GuguReminder"])],
    targets: [
        .target(name: "ReminderCore", path: "native/Core"),
        .executableTarget(name: "GuguReminder", dependencies: ["ReminderCore"], path: "native/App"),
        .testTarget(name: "ReminderCoreTests", dependencies: ["ReminderCore"], path: "native/Tests")
    ]
)
