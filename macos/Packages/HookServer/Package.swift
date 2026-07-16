// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HookServer",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HookServer", targets: ["HookServer"]),
    ],
    dependencies: [
        .package(path: "../AgentDomain"),
        .package(path: "../LocalHTTPServer"),
    ],
    targets: [
        .target(
            name: "HookServer",
            dependencies: ["AgentDomain", "LocalHTTPServer"]
        ),
        .testTarget(
            name: "HookServerTests",
            dependencies: ["HookServer"]
        ),
    ]
)
