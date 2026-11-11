// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeMonitor",
    platforms: [.macOS("27.0")],
    products: [
        .executable(name: "ClaudeMonitor", targets: ["ClaudeMonitor"])
    ],
    targets: [
        .executableTarget(
            name: "ClaudeMonitor",
            path: "Sources/ClaudeMonitor",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
