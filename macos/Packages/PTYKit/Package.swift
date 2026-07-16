// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PTYKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PTYKit", targets: ["PTYKit"]),
        .library(name: "CPTYHelpers", targets: ["CPTYHelpers"]),
    ],
    dependencies: [
        .package(path: "../AgentDomain"),
    ],
    targets: [
        .target(
            name: "CPTYHelpers",
            publicHeadersPath: "include"
        ),
        .target(
            name: "PTYKit",
            dependencies: ["AgentDomain", "CPTYHelpers"]
        ),
        .testTarget(
            name: "PTYKitTests",
            dependencies: ["PTYKit"]
        ),
    ]
)
