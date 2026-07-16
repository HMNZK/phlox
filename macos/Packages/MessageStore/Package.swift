// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MessageStore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MessageStore", targets: ["MessageStore"]),
    ],
    dependencies: [
        .package(path: "../AgentDomain"),
    ],
    targets: [
        .target(
            name: "MessageStore",
            dependencies: ["AgentDomain"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "MessageStoreTests",
            dependencies: ["MessageStore"]
        ),
    ]
)
