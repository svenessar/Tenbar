// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tenbar",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "TenbarCore"),
        .executableTarget(name: "Tenbar", dependencies: ["TenbarCore"]),
        .testTarget(name: "TenbarCoreTests", dependencies: ["TenbarCore"]),
    ]
)
