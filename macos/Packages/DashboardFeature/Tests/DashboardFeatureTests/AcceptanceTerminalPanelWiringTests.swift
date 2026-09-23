// task-3 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-3.md — ターミナルパネルの容器プロトタイプとホットキー配線。
// ソーススキャン形式（ADR 0136 の先例に倣う）: UI の実挙動はゲート②の実機確認と
// フェーズ4の XCUITest が担い、ここでは配線の存在と設計制約を機械固定する。
// アサーションは変更禁止。テストハーネスの欠陥を発見した場合は、PM に報告し
// 承認を得たうえでハーネス部分に限り修理してよい。

import Foundation
import Testing

@Suite("Terminal panel wiring acceptance (task-3)")
struct AcceptanceTerminalPanelWiringTests {

    /// #filePath: <root>/macos/Packages/DashboardFeature/Tests/DashboardFeatureTests/本ファイル
    private var repoRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { url.deleteLastPathComponent() }
        return url
    }

    private func source(_ relativePath: String) throws -> String {
        let url = repoRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    // 02 C（UI 再設計・ユーザー承認）でドロワーを廃止し、⌃⌘T は「ターミナルタブを開く／前に出す」へ変わった。
    // トグル呼び出しの検査は新しい配線（openChildTab）に置き換える。
    @Test("⌃⌘T のホットキーが Commands に登録され、ターミナルタブを開く配線になっている")
    func hotkeyIsRegistered() throws {
        let app = try source("macos/App/PhloxApp.swift")
        #expect(app.contains(#"keyboardShortcut("t", modifiers: [.command, .control])"#))
        #expect(app.contains("openChildTab(.terminal)"))
    }

    // ターミナルの置き場はドロワーからタブの入れ物（SessionTabsContainer）へ移った。検査対象のファイルだけを差し替える。
    @Test("タブ方式: タブの入れ物がターミナルをレイアウトフローで組み込む")
    func drawerIsEmbeddedInDashboard() throws {
        let dashboard = try source(
            "macos/Packages/DashboardFeature/Sources/DashboardFeature/Tabs/SessionTabsContainer.swift")
        #expect(dashboard.contains("TerminalPanelView"))
        // ADR 0136 §3: AppKit NSView は SwiftUI overlay より前面に出るため、
        // ターミナルパネルを .overlay で重ねる配置は禁止（レイアウトフロー内に置く）。
        let overlayLines = dashboard
            .components(separatedBy: .newlines)
            .filter { $0.contains("TerminalPanelView") && $0.contains(".overlay") }
        #expect(overlayLines.isEmpty, "TerminalPanelView を .overlay に置いてはならない: \(overlayLines)")
    }

    @Test("ターミナルパネルの View に XCUITest 用の accessibilityIdentifier がある")
    func panelHasAccessibilityIdentifier() throws {
        let panel = try source(
            "macos/Packages/DashboardFeature/Sources/DashboardFeature/UserTerminal/TerminalPanelView.swift")
        #expect(panel.contains(#"accessibilityIdentifier("user-terminal-panel")"#))
    }

    // 「独立ウィンドウ方式のプロトタイプが隔離ファイルに存在する」テストは、
    // ゲート②（2026-07-31・ドロワー確定）でプロトタイプ撤去が確定したため PM が撤去した。
    // 撤去の検査は AcceptancePanelIntegrationTests.prototypeIsRemoved（task-5）が担う。
    // （task-3 時点の存在要求と task-5 の撤去要求が矛盾する契約欠陥の解消。decision-log 参照）
}
