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
        #expect(composerModeOptions(for: .builtin(.claudeCode), codexProfileIDs: []) == [
            ComposerModeOption(value: "acceptEdits", title: "Accept Edits", isPlan: false),
            ComposerModeOption(value: "bypassPermissions", title: "Bypass", isPlan: false),
            ComposerModeOption(value: "plan", title: "Plan", isPlan: true),
        ])
    }

    @Test
    func cursorModeOptionsAppendPlan() {
        #expect(composerModeOptions(for: .builtin(.cursor), codexProfileIDs: []) == [
            ComposerModeOption(value: nil, title: "Run Everything", isPlan: false),
            ComposerModeOption(value: "ask", title: "Ask", isPlan: false),
            ComposerModeOption(value: "plan", title: "Plan", isPlan: true),
        ])
    }

    @Test
    func codexModeOptionsMapProfilesThenAppendPlan() {
        #expect(composerModeOptions(
            for: .builtin(.codex),
            codexProfileIDs: [":read-only", ":workspace", ":danger-full-access"]
        ) == [
            ComposerModeOption(value: ":read-only", title: "Read Only", isPlan: false),
            ComposerModeOption(value: ":workspace", title: "Auto", isPlan: false),
            ComposerModeOption(value: ":danger-full-access", title: "Full Access", isPlan: false),
            ComposerModeOption(value: "plan", title: "Plan", isPlan: true),
        ])
    }
}
