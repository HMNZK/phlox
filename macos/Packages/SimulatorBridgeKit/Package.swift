// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SimulatorBridgeKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SimulatorBridgeKit", targets: ["SimulatorBridgeKit"]),
    ],
    targets: [
        .target(name: "SimulatorBridgeKit"),
        .testTarget(name: "SimulatorBridgeKitTests", dependencies: ["SimulatorBridgeKit"]),
    ]
)
