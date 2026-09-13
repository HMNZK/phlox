import Testing
import AgentDomain
@testable import DashboardFeature
@testable import SessionFeature

/// task-2（Plan を権限/モードメニューへ統合）受け入れテスト — PM 著・不変（実装役は編集禁止）。
///
/// 契約: 独立した Plan コントロールを廃し、Plan を「権限/モード」ドロップダウンの**末尾の1項目**として
/// 統合する（排他単一選択）。メニュー項目は単一真実源の純関数 `composerModeOptions(for:codexProfileIDs:)`
/// から得る。Claude/Cursor は静的、Codex は動的プロフィール（id 配列）＋末尾 Plan。
/// isPlan フラグで Plan 項目を識別し、選択中表示（isPlanMode 時は "Plan"）や排他解除は runtime 側で扱う。
///
/// 併せて `composerControls(for:)` から `.plan` を除去する（＝Plan は独立コントロールでなくなる）。
/// 「Plan が選択可能」という旧 GridComposerSettings 契約は、本ファイルの composerModeOptions 検証で再表現する。
@Suite("ComposerModeMenu acceptance")
struct ComposerModeMenuAcceptanceTests {

    // MARK: - Plan は独立コントロールではなくなる（menu へ統合）

    @Test
    func planIsNoLongerASeparateControl() {
        #expect(!composerControls(for: .builtin(.codex)).contains(.plan))
        #expect(!composerControls(for: .builtin(.claudeCode)).contains(.plan))
        #expect(!composerControls(for: .builtin(.cursor)).contains(.plan))
    }

    // MARK: - 権限/モードメニュー項目（Plan を末尾に統合）

    @Test
    func claudeModeOptionsAppendPlan() {
        let optionsEN = composerModeOptions(for: .builtin(.claudeCode), codexProfileIDs: [])
        #expect(optionsEN.map(\.value) == [
            "acceptEdits", "auto", "bypassPermissions", "manual", "dontAsk", "plan",
        ])
        #expect(optionsEN.map(\.isPlan) == [false, false, false, false, false, true])
        #expect(optionsEN.last?.title == expectedPlanTitle(languageCode: "en"))
        #expect(expectedPlanTitle(languageCode: "ja") == "計画")
    }

    @Test
    func cursorModeOptionsAppendPlan() {
        let optionsEN = composerModeOptions(for: .builtin(.cursor), codexProfileIDs: [])
        #expect(optionsEN.map(\.value) == [nil, "ask", "plan"])
        #expect(optionsEN.map(\.isPlan) == [false, false, true])
        #expect(optionsEN.last?.title == expectedPlanTitle(languageCode: "en"))
        #expect(expectedPlanTitle(languageCode: "ja") == "計画")
    }

    @Test
    func codexModeOptionsMapProfilesThenAppendPlan() {
        let optionsEN = composerModeOptions(
            for: .builtin(.codex),
            codexProfileIDs: [":read-only", ":workspace", ":danger-full-access"]
        )
        #expect(optionsEN.map(\.value) == [":read-only", ":workspace", ":danger-full-access", "plan"])
        #expect(optionsEN.map(\.isPlan) == [false, false, false, true])
        #expect(optionsEN.last?.title == expectedPlanTitle(languageCode: "en"))
        #expect(expectedPlanTitle(languageCode: "ja") == "計画")
    }
}

private func expectedPlanTitle(languageCode: String) -> String {
    let primary = languageCode.split { $0 == "-" || $0 == "_" }.first.map(String.init)?.lowercased() ?? ""
    return primary == "en" ? "Plan" : "計画"
}
