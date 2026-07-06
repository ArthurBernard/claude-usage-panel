// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeUsagePanel",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "ClaudeUsagePanel")
    ]
)
