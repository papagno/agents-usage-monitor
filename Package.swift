// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FuelGauge",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0"),
    ],
    targets: [
        .target(name: "UsageCore"),
        .executableTarget(
            name: "FuelGauge",
            dependencies: ["UsageCore", .product(name: "Sparkle", package: "Sparkle")],
            // bundle.sh copies Sparkle.framework into Contents/Frameworks.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "UsageCoreTests", dependencies: ["UsageCore"]),
    ]
)
