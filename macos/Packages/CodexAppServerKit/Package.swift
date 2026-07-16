// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexAppServerKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CodexAppServerKit", targets: ["CodexAppServerKit"]),
    ],
    dependencies: [
        .package(path: "../AgentDomain"),
        .package(path: "../StructuredChatKit"),
    ],
    targets: [
        .target(name: "CodexAppServerKit", dependencies: ["AgentDomain", "StructuredChatKit"]),
        .testTarget(
            name: "CodexAppServerKitTests",
            dependencies: ["CodexAppServerKit", "StructuredChatKit"]
        ),
    ]
)
