// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ControlServer",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ControlServer", targets: ["ControlServer"]),
    ],
    dependencies: [
        .package(path: "../AgentDomain"),
        .package(path: "../LocalHTTPServer"),
    ],
    targets: [
        .target(
            name: "ControlServer",
            dependencies: ["AgentDomain", "LocalHTTPServer"]
        ),
        .testTarget(
            name: "ControlServerTests",
            dependencies: ["ControlServer"]
        ),
    ]
)
