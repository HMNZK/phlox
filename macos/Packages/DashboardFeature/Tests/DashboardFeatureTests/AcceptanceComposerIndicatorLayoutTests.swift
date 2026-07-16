// task-3 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-3.md — ComposerContextIndicator の layout 契約面。
// 注意: GridComposerBar への実配線は自動テストでは検証しない（レビュー Rubric と
// フェーズ4の実機確認で担保する）。アサーションは変更禁止。テストハーネスの欠陥を
// 発見した場合は、PM に報告し承認を得たうえでハーネス部分に限り修理してよい。

import StructuredChatKit
import SwiftUI
import Testing
@testable import SessionFeature

@Test func composerIndicator_acceptsBothLayouts() {
    _ = ComposerContextIndicator(usage: nil, workspacePath: "", layout: .regular)
    _ = ComposerContextIndicator(usage: nil, workspacePath: "", layout: .compact)
}

@Test func composerIndicator_defaultLayoutIsRegular_keepsExistingCallSites() {
    // シングルビュー（ChatComposer）の既存呼び出し `(usage:workspacePath:)` を壊さない。
    let view = ComposerContextIndicator(usage: nil, workspacePath: "")
    #expect(view.layout == .regular)
}

@MainActor
@Test func composerIndicator_compact_rendersOffscreen() {
    let usage = TurnUsage(contextUsedTokens: 50_000, contextWindowTokens: 200_000)
    let renderer = ImageRenderer(
        content: ComposerContextIndicator(usage: usage, workspacePath: "", layout: .compact)
            .frame(width: 120, height: 30)
    )
    #expect(renderer.nsImage != nil)
}
