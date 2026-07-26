// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SessionFeature",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SessionFeature", targets: ["SessionFeature"]),
    ],
    dependencies: [
        .package(path: "../AgentDomain"),
        .package(path: "../DesignSystem"),
        .package(path: "../HookServer"),
        .package(path: "../PTYKit"),
        .package(path: "../TerminalUI"),
        .package(path: "../CodexAppServerKit"),
        .package(path: "../StructuredChatKit"),
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "SessionFeature",
            dependencies: [
                "AgentDomain",
                "DesignSystem",
                "HookServer",
                "PTYKit",
                "TerminalUI",
                "CodexAppServerKit",
                "StructuredChatKit",
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
            ]
        ),
        .testTarget(
            name: "SessionFeatureTests",
            dependencies: [
                "SessionFeature",
                "AgentDomain",
                "PTYKit",
                "TerminalUI",
                "StructuredChatKit",
            ]
        ),
    ]
)
