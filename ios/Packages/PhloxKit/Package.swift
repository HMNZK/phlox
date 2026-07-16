// swift-tools-version: 6.0
import PackageDescription

// PhloxKit: Phlox-mobile の全 Swift ロジックを保持するローカル SwiftPM パッケージ。
// アプリターゲット（PhloxMobile.xcodeproj）は極薄に保ち、テスト可能なコードはすべてここに置く。
//
// 【ドメイン語彙の単一真実源（SSOT） / ADR 0001 — Architecture Y】
// SessionStatus / AgentKind 等は sibling Phlox リポジトリの `AgentDomain` を唯一の真実源として
// 共有する（path 依存）。当初の仮定 A1（PhloxKit 内に AgentDomain をコピー）は、A2（Phlox の
// DesignSystem を path 依存で再利用）と SPM レベルで両立しない:
//   DesignSystem → (依存) → Phlox AgentDomain（product 名 "AgentDomain"）
// のため、PhloxKit 側に同名 `AgentDomain` ターゲットを置くと「product 名重複」で解決不能になる。
// よって A2 と design-system.md §0（状態語彙の二重定義を避ける = SSOT）を優先し、A1 を
// 「Phlox の AgentDomain を共有」へ更新した（詳細は doc/adr/0001-shared-agent-domain.md）。
//
// 【プラットフォーム】
// アプリの対象は iOS 17+ のみ。ただし `swift test` は macOS ホスト上で実行されるため、
// マクロ/ホストビルドで AgentDomain（macOS .v14）を解決できるよう .macOS(.v14) も宣言する。
// AgentDomain には iOS .v17 を追加済み（ADR 0001）。
//
// 【DesignSystem の扱い】
// E2-1 で sibling DesignSystem に .iOS(.v17) を追加し、macOS 専用 API（hover/NSCursor・
// NSViewRepresentable スピナー）を #if os(macOS) で隔離した。これにより iOS でも
// DSColor / DSSpacing / StatusBadge 等のコアトークンが import 可能になったため、
// Features ターゲットが DesignSystem product に依存する。
let package = Package(
    name: "PhloxKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PhloxCore", targets: ["PhloxCore"]),
        .library(name: "PhloxNetworking", targets: ["PhloxNetworking"]),
        .library(name: "PhloxSecurity", targets: ["PhloxSecurity"]),
        .library(name: "PhloxReachability", targets: ["PhloxReachability"]),
        .library(name: "DesignSystemIOS", targets: ["DesignSystemIOS"]),
        .library(name: "Features", targets: ["Features"]),
    ],
    dependencies: [
        .package(path: "../../../macos/Packages/AgentDomain"),
        .package(path: "../../../macos/Packages/DesignSystem"),
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.0.0"),
    ],
    targets: [
        // PhloxCore: Domain 層。AgentDomain（共有 SSOT）を再エクスポートし、
        // iOS 集約モデル（Session / Approval / ConnectionConfig 等）と Repository プロトコルを置く。
        .target(
            name: "PhloxCore",
            dependencies: [
                .product(name: "AgentDomain", package: "AgentDomain"),
            ]
        ),
        .target(name: "PhloxNetworking", dependencies: ["PhloxCore"]),
        .target(name: "PhloxSecurity", dependencies: ["PhloxCore"]),
        .target(name: "PhloxReachability", dependencies: ["PhloxCore"]),

        // DesignSystemIOS: iOS 向けデザインシステム層。共有 DesignSystem（コアトークン・状態語彙）を
        // 再エクスポートし、iOS 固有トークン（DSTouch/DSMotion/DSIcon）と Atoms/Molecules を足す。
        .target(
            name: "DesignSystemIOS",
            dependencies: [
                "PhloxCore",
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "AgentDomain", package: "AgentDomain"),
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
            ]
        ),

        .target(
            name: "Features",
            dependencies: [
                "PhloxCore",
                "PhloxNetworking",
                "DesignSystemIOS",
                .product(name: "DesignSystem", package: "DesignSystem"),
            ]
        ),

        .testTarget(name: "PhloxCoreTests", dependencies: ["PhloxCore"]),
        .testTarget(name: "PhloxNetworkingTests", dependencies: ["PhloxNetworking", "PhloxCore"]),
        .testTarget(name: "PhloxSecurityTests", dependencies: ["PhloxSecurity", "PhloxCore"]),
        .testTarget(name: "PhloxReachabilityTests", dependencies: ["PhloxReachability", "PhloxCore"]),
        .testTarget(name: "DesignSystemIOSTests", dependencies: ["DesignSystemIOS", "PhloxCore"]),
        .testTarget(name: "FeaturesTests", dependencies: ["Features", "PhloxCore", "PhloxNetworking"]),
        .testTarget(name: "E2ETests", dependencies: ["PhloxNetworking", "PhloxCore"]),
    ],
    swiftLanguageModes: [.v6]
)
