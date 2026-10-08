// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentsUsageMonitor",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "UsageCore"),
        .executableTarget(name: "AgentsUsageMonitor", dependencies: ["UsageCore"]),
        .testTarget(name: "UsageCoreTests", dependencies: ["UsageCore"]),
    ]
)
