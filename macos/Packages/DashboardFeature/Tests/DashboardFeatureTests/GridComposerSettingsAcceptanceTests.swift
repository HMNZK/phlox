import Testing
import AgentDomain
@testable import DashboardFeature
@testable import SessionFeature

/// task-1（バグ2）受け入れテスト — PM 著・不変（実装役は編集禁止）。
///
/// 契約: 単一表示コンポーザーとグリッドコンポーザーが、agentRef ごとに出す設定コントロール
/// （model / effort / permission / plan / mode）を**単一の真実源** `composerControls(for:)`
/// から得る。この純関数のマッピングを固定する。グリッド版が同じ関数を参照することで、
/// 「グリッドで model/effort/PLAN を選べない」を構造的に解消する（実際の描画は runtime 検証）。
///
/// 期待マッピング（task-2 で `.plan` は権限/モードメニューへ統合され本集合から除去）:
///   - .builtin(.codex)      → [.model, .permission]
///   - .builtin(.claudeCode) → [.model, .effort, .permission]
///   - .builtin(.cursor)     → [.model, .mode]
///   - その他                → []
@Suite("GridComposerSettings acceptance")
struct GridComposerSettingsAcceptanceTests {

    @Test
    func codexExposesModelPermission() {
        #expect(composerControls(for: .builtin(.codex)) == [.model, .permission])
    }

    @Test
    func claudeExposesModelEffortPermission() {
        #expect(composerControls(for: .builtin(.claudeCode)) == [.model, .effort, .permission])
    }

    @Test
    func cursorExposesModelMode() {
        #expect(composerControls(for: .builtin(.cursor)) == [.model, .mode])
    }

    /// codex は effort/mode を出さない（claude 専用の effort、cursor 専用の mode を混入させない）。
    @Test
    func controlSetsAreAgentSpecific() {
        #expect(!composerControls(for: .builtin(.codex)).contains(.effort))
        #expect(!composerControls(for: .builtin(.codex)).contains(.mode))
        #expect(!composerControls(for: .builtin(.claudeCode)).contains(.mode))
        #expect(!composerControls(for: .builtin(.cursor)).contains(.effort))
    }

    /// task-2: PLAN は独立コントロールから権限/モードメニューへ統合された。
    /// グリッドでも Plan を選べること（メニュー項目に plan が含まれること）を保証する。
    @Test
    func planSelectableViaModeMenuForAllBuiltins() {
        #expect(composerModeOptions(for: .builtin(.codex), codexProfileIDs: [":workspace"]).contains { $0.isPlan })
        #expect(composerModeOptions(for: .builtin(.claudeCode), codexProfileIDs: []).contains { $0.isPlan })
        #expect(composerModeOptions(for: .builtin(.cursor), codexProfileIDs: []).contains { $0.isPlan })
    }
}
