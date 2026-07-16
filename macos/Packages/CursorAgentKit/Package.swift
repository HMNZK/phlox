// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CursorAgentKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CursorAgentKit", targets: ["CursorAgentKit"]),
    ],
    dependencies: [
        .package(path: "../StructuredChatKit"),
    ],
    targets: [
        .target(name: "CursorAgentKit", dependencies: ["StructuredChatKit"]),
        .testTarget(name: "CursorAgentKitTests", dependencies: ["CursorAgentKit"]),
    ]
)
