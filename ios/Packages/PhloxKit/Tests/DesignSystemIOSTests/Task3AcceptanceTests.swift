import Testing
@testable import DesignSystemIOS

/// task-3 受け入れテスト（PM 著）。wave-4 で契約を更新: 送信ボタンと重なる
/// キーボード上「完了」ツールバーは廃止し（閉じるはスクロールに委譲）、入力欄内に
/// モデルセレクタ用スロットを設ける（decision-log「task-3 波及テスト処理」）。
@Suite struct Task3AcceptanceTests {
    @Test func inputBarRemovesKeyboardDismissToolbarAndProvidesModelSlot() {
        #expect(!DSInputBar.providesKeyboardDismissToolbar)
        #expect(DSInputBar.providesInlineModelSelectorSlot)
    }

    /// 前提の不変条件: focus 管理は @FocusState ベースのまま（既存契約 DS-AUDIT-4）。
    @Test func inputBarKeepsFocusStateContract() {
        #expect(DSInputBar.usesFocusState)
    }
}
