import Foundation
import Testing
@testable import SessionFeature

@Suite(.serialized)
struct ChatTextSelectionPolicyWhiteboxTests {
    /// 選択可能な `Text` 1 個あたり約 1.8ms かかるため、1 ブロックあたりの個数が
    /// 有界でない diff 行だけは選択を無効にする（実測: 2447ms → 554ms）。
    /// この 2 値が入れ替わると切替が 4 倍遅くなるので、既定値として固定する。
    @Test
    func defaultsKeepProseSelectableAndDisableDiffLineSelection() {
        #expect(ChatTextSelectionPolicy.prose)
        #expect(!ChatTextSelectionPolicy.diffLines)
    }
}
