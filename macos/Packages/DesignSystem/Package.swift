// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DesignSystem",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
    ],
    dependencies: [
        .package(path: "../AgentDomain"),
    ],
    targets: [
        .target(
            name: "DesignSystem",
            dependencies: ["AgentDomain"],
            resources: [.process("Icons.xcassets")]
        ),
        .testTarget(
            name: "DesignSystemTests",
            dependencies: ["DesignSystem", "AgentDomain"]
        ),
    ]
)
