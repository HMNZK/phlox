// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "APNsClient",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "APNsClient", targets: ["APNsClient"]),
    ],
    targets: [
        .target(name: "APNsClient"),
        .testTarget(
            name: "APNsClientTests",
            dependencies: ["APNsClient"]
        ),
    ]
)
