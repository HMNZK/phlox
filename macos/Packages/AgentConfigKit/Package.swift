// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentConfigKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AgentConfigKit", targets: ["AgentConfigKit"]),
    ],
    targets: [
        .target(name: "AgentConfigKit"),
        .testTarget(name: "AgentConfigKitTests", dependencies: ["AgentConfigKit"]),
    ]
)
