// 契約の正本: tasks/task-2.md — ブランチ名の全文表示（不要な固定幅クランプの排除）。
// このファイルは PM が凍結する受け入れテスト。実装役は編集禁止（ハーネス欠陥は PM 承認の上でのみ修理可）。
//
// 契約: ブランチ名ラベルは layout によらず任意幅の上限クランプを持たない
// （省略は実領域が不足したときの SwiftUI の自然な圧縮でのみ起きる）。
// truncation は従来どおり .middle。

import SwiftUI
import Testing
@testable import SessionFeature

@Suite("Acceptance: ブランチ名の全文表示（task-2）")
struct AcceptanceBranchNameFullWidthTests {
    @Test func regularレイアウトは幅クランプなし() {
        #expect(ComposerIndicatorMetrics.branchNameMaxWidth(for: .regular) == nil)
    }

    @Test func compactレイアウトも幅クランプなし() {
        // 旧実装はグリッド列向けに固定 100pt を返し、領域が余っていても省略されていた（本不具合）。
        #expect(ComposerIndicatorMetrics.branchNameMaxWidth(for: .compact) == nil)
    }

    @Test func truncationは両レイアウトでmiddleを維持() {
        #expect(ComposerIndicatorMetrics.branchTruncationMode(for: .regular) == .middle)
        #expect(ComposerIndicatorMetrics.branchTruncationMode(for: .compact) == .middle)
    }
}
