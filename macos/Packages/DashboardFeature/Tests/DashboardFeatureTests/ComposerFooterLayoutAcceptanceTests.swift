import Testing
import AgentDomain
@testable import DashboardFeature
@testable import SessionFeature

/// task-1（コンポーザーフッター左右分割）受け入れテスト — PM 著・不変（実装役は編集禁止）。
///
/// 契約: チャット入力欄フッターの設定コントロールを「左（leading）＝権限系」「右（trailing）＝
/// モデル/effort」の2グループに分割する。分割は単一の真実源 `composerControls(for:side:)`（純関数）
/// から得て、単一表示（ChatComposer）とグリッド表示（GridComposerBar）の両コンポーザーが同じ関数を
/// 参照する。実際の左右描画位置・見た目（枠なしテキスト化）は runtime 検証で確認する。
///
/// 分割規則: trailing = 全体のうち {.model, .effort}（元の順序保持）、leading = 残り（元の順序保持）。
/// task-2 で `.plan` は `composerControls(for:)` から除去され、権限/モードメニューへ統合された
/// （→ ComposerModeMenuAcceptanceTests）。よって leading は権限/モードの単一コントロールになる。
/// 期待（`composerControls(for:)` の全体集合を過不足なく2分割する）:
///   - .builtin(.codex)      全体 [.model, .permission]          → leading [.permission] / trailing [.model]
///   - .builtin(.claudeCode) 全体 [.model, .effort, .permission] → leading [.permission] / trailing [.model, .effort]
///   - .builtin(.cursor)     全体 [.model, .mode]                → leading [.mode]        / trailing [.model]
@Suite("ComposerFooterLayout acceptance")
struct ComposerFooterLayoutAcceptanceTests {

    // MARK: - Claude（model + effort を右へ、permission を左へ。plan は permission メニューへ統合）

    @Test
    func claudeLeadingIsPermissionOnly() {
        #expect(composerControls(for: .builtin(.claudeCode), side: .leading) == [.permission])
    }

    @Test
    func claudeTrailingIsModelThenEffort() {
        #expect(composerControls(for: .builtin(.claudeCode), side: .trailing) == [.model, .effort])
    }

    // MARK: - Codex（effort は独立コントロールを持たない＝右はモデルのみ）

    @Test
    func codexLeadingIsPermissionOnly() {
        #expect(composerControls(for: .builtin(.codex), side: .leading) == [.permission])
    }

    @Test
    func codexTrailingIsModelOnly() {
        #expect(composerControls(for: .builtin(.codex), side: .trailing) == [.model])
    }

    // MARK: - Cursor（mode が権限相当＝左、effort なし＝右はモデルのみ）

    @Test
    func cursorLeadingIsModeOnly() {
        #expect(composerControls(for: .builtin(.cursor), side: .leading) == [.mode])
    }

    @Test
    func cursorTrailingIsModelOnly() {
        #expect(composerControls(for: .builtin(.cursor), side: .trailing) == [.model])
    }

    // MARK: - 不変条件（分割は全体を過不足なく保存する）

    @Test
    func claudePartitionPreservesFullSetWithoutOverlap() {
        let leading = composerControls(for: .builtin(.claudeCode), side: .leading)
        let trailing = composerControls(for: .builtin(.claudeCode), side: .trailing)
        #expect(Set(leading).isDisjoint(with: Set(trailing)))
        #expect(Set(leading).union(Set(trailing)) == Set(composerControls(for: .builtin(.claudeCode))))
    }

    @Test
    func codexPartitionPreservesFullSetWithoutOverlap() {
        let leading = composerControls(for: .builtin(.codex), side: .leading)
        let trailing = composerControls(for: .builtin(.codex), side: .trailing)
        #expect(Set(leading).isDisjoint(with: Set(trailing)))
        #expect(Set(leading).union(Set(trailing)) == Set(composerControls(for: .builtin(.codex))))
    }

    @Test
    func cursorPartitionPreservesFullSetWithoutOverlap() {
        let leading = composerControls(for: .builtin(.cursor), side: .leading)
        let trailing = composerControls(for: .builtin(.cursor), side: .trailing)
        #expect(Set(leading).isDisjoint(with: Set(trailing)))
        #expect(Set(leading).union(Set(trailing)) == Set(composerControls(for: .builtin(.cursor))))
    }
}
