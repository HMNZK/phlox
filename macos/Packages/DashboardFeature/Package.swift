// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DashboardFeature",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DashboardFeature", targets: ["DashboardFeature"]),
    ],
    dependencies: [
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
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "DashboardFeature",
            dependencies: [
                "AgentDomain",
                "SessionFeature",
                "HookServer",
                "MessageStore",
                "PTYKit",
                "TerminalUI",
                "DesignSystem",
                "CodexAppServerKit",
                "StructuredChatKit",
                "ClaudeAgentKit",
                "CursorAgentKit",
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
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
            ],
            resources: [.copy("Fixtures")]
        ),
    ]
)
