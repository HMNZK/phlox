// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StructuredChatKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "StructuredChatKit", targets: ["StructuredChatKit"]),
    ],
    targets: [
        .target(name: "StructuredChatKit"),
        .testTarget(name: "StructuredChatKitTests", dependencies: ["StructuredChatKit"]),
    ]
)
