import Testing
import AgentDomain
@testable import DashboardFeature
@testable import SessionFeature

/// task-1（コンポーザーフッター左右分割）受け入れテスト — PM 著・不変（実装役は編集禁止）。
///
/// 改訂（0037 F5、ユーザー承認「モックに合わせる」）: 05 Reply Area のモックはチップをすべて左に並べ、
/// 右はコンテキスト表示と送信ボタンだけにする。よって leading ＝ `composerControls(for:)` の全体（順序保持）、
/// trailing ＝ 空。分割は引き続き単一の真実源 `composerControls(for:side:)` から得て、単一表示と
/// グリッド表示の両コンポーザーが同じ関数を参照する。
/// 期待:
///   - .builtin(.codex)      leading [.model, .permission]          / trailing []
///   - .builtin(.claudeCode) leading [.model, .effort, .permission] / trailing []
///   - .builtin(.cursor)     leading [.model, .mode]                / trailing []
@Suite("ComposerFooterLayout acceptance")
struct ComposerFooterLayoutAcceptanceTests {

    @Test
    func claudeLeadingIsAllControlsInOrder() {
        #expect(composerControls(for: .builtin(.claudeCode), side: .leading) == [.model, .effort, .permission])
        #expect(composerControls(for: .builtin(.claudeCode), side: .trailing).isEmpty)
    }

    @Test
    func codexLeadingIsAllControlsInOrder() {
        #expect(composerControls(for: .builtin(.codex), side: .leading) == [.model, .permission])
        #expect(composerControls(for: .builtin(.codex), side: .trailing).isEmpty)
    }

    @Test
    func cursorLeadingIsAllControlsInOrder() {
        #expect(composerControls(for: .builtin(.cursor), side: .leading) == [.model, .mode])
        #expect(composerControls(for: .builtin(.cursor), side: .trailing).isEmpty)
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
