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
        // Terminal.swift: DECRQCRAを中間文字 * のある要求に限定（ADR 0212）。
        // MacTerminalView.swift: 従来モードのOption単独＋左右矢印だけESC b/fへ変換。
        // Kittyでは左右矢印のOption修飾を保持し、押下・解放の記録は持たない（ADR 0212）。
        // 2026-10-15確認のupstream mainにもDECRQCRAの検査漏れが残るため、手元の局所修正。
        // DA1追加調査: 52MBのSGRを欠落なくfeedしても誤応答せず、途中のチャンク破棄で
        // ESC [ c が接続される再現を追加。DA1のパーサー修正は加えていない（ADR 0212追記）。
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
