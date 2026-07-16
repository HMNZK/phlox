// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TerminalUI",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TerminalUI", targets: ["TerminalUI"]),
    ],
    dependencies: [
        // 一時的にローカル fork を参照。alt buffer の column shrink で古い cell が
        // trim されないバグ修正 (Sources/SwiftTerm/Buffer.swift) を当てている。
        // upstream 取り込み or 解消後は GitHub 参照に戻す。
        .package(path: "../../Vendor/SwiftTerm"),
    ],
    targets: [
        .target(
            name: "TerminalUI",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ]
        ),
        .testTarget(
            name: "TerminalUITests",
            dependencies: [
                "TerminalUI",
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ]
        ),
    ]
)
