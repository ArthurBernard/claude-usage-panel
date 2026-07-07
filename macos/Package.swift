// swift-tools-version: 5.9
import PackageDescription

// The SwiftUI menu-bar app is macOS-only; the pure ClaudeUsageCore library
// (Foundation only) builds and unit-tests on any platform, including Linux CI.
var targets: [Target] = [
    .target(name: "ClaudeUsageCore"),
    .testTarget(name: "ClaudeUsageCoreTests", dependencies: ["ClaudeUsageCore"]),
]

#if os(macOS)
    targets.append(
        .executableTarget(name: "ClaudeUsagePanel", dependencies: ["ClaudeUsageCore"]))
#endif

let package = Package(
    name: "ClaudeUsagePanel",
    platforms: [.macOS(.v13)],
    targets: targets
)
