// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LocalHTTPServer",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LocalHTTPServer", targets: ["LocalHTTPServer"]),
    ],
    targets: [
        .target(name: "LocalHTTPServer"),
        .testTarget(
            name: "LocalHTTPServerTests",
            dependencies: ["LocalHTTPServer"]
        ),
    ]
)
