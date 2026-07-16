// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeAgentKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ClaudeAgentKit", targets: ["ClaudeAgentKit"]),
    ],
    dependencies: [
        .package(path: "../StructuredChatKit"),
    ],
    targets: [
        .target(name: "ClaudeAgentKit", dependencies: ["StructuredChatKit"]),
        .testTarget(name: "ClaudeAgentKitTests", dependencies: ["ClaudeAgentKit"]),
    ]
)
