// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentDomain",
    // iOS を追加（Phlox-mobile が SSOT として共有: ADR 0001 / Architecture Y）。
    // AgentDomain は Foundation のみに依存するため iOS でそのままコンパイル可能。
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "AgentDomain", targets: ["AgentDomain"]),
    ],
    targets: [
        .target(name: "AgentDomain"),
        .testTarget(name: "AgentDomainTests", dependencies: ["AgentDomain"]),
    ]
)
