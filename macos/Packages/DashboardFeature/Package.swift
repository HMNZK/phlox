// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DashboardFeature",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DashboardFeature", targets: ["DashboardFeature"]),
    ],
    dependencies: [
        .package(path: "../SimulatorBridgeKit"),
        .package(path: "../AgentDomain"),
        .package(path: "../SessionFeature"),
        .package(path: "../HookServer"),
        .package(path: "../MessageStore"),
        .package(path: "../PTYKit"),
        .package(path: "../TerminalUI"),
        .package(path: "../DesignSystem"),
        .package(path: "../ControlServer"),
        .package(path: "../AppBootstrap"),
        .package(path: "../CodexAppServerKit"),
        .package(path: "../StructuredChatKit"),
        .package(path: "../ClaudeAgentKit"),
        .package(path: "../CursorAgentKit"),
        .package(path: "../LocalHTTPServer"),
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.0.0"),
        .package(url: "https://github.com/swiftlang/swift-cmark", exact: "0.8.0"),
    ],
    targets: [
        .target(
            name: "DashboardFeature",
            dependencies: [
                "SimulatorBridgeKit",
                "AgentDomain",
                .product(name: "ChatRenderKit", package: "AgentDomain"),
                "SessionFeature",
                "HookServer",
                "MessageStore",
                "PTYKit",
                "TerminalUI",
                "DesignSystem",
                "ControlServer",
                "CodexAppServerKit",
                "StructuredChatKit",
                "ClaudeAgentKit",
                "CursorAgentKit",
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "cmark-gfm", package: "swift-cmark"),
                .product(name: "cmark-gfm-extensions", package: "swift-cmark"),
            ],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "DashboardFeatureTests",
            dependencies: [
                "DashboardFeature",
                "SessionFeature",
                "ControlServer",
                "AppBootstrap",
                "CodexAppServerKit",
                "StructuredChatKit",
                "LocalHTTPServer",
            ],
            resources: [.copy("Fixtures")]
        ),
    ]
)
