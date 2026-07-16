// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MobileProxy",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MobileProxy", targets: ["MobileProxy"]),
    ],
    targets: [
        .target(name: "MobileProxy"),
        .testTarget(
            name: "MobileProxyTests",
            dependencies: ["MobileProxy"]
        ),
    ]
)
