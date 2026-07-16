// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppBootstrap",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AppBootstrap", targets: ["AppBootstrap"]),
    ],
    dependencies: [
        .package(path: "../APNsClient"),
        .package(path: "../AgentDomain"),
        .package(path: "../ControlServer"),
        .package(path: "../DashboardFeature"),
        .package(path: "../SessionFeature"),
        .package(path: "../StructuredChatKit"),
    ],
    targets: [
        .target(
            name: "AppBootstrap",
            dependencies: [
                "APNsClient",
                "AgentDomain",
                "ControlServer",
                "DashboardFeature",
                "SessionFeature",
                "StructuredChatKit",
            ]
        ),
        .testTarget(
            name: "AppBootstrapTests",
            dependencies: ["APNsClient", "AppBootstrap", "AgentDomain", "SessionFeature", "StructuredChatKit"]
        ),
    ]
)
