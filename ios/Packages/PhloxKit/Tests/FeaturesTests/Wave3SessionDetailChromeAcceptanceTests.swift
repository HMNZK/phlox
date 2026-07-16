import Testing
@testable import Features

/// wave-3 受け入れテスト（PM 著・凍結。実装役は編集禁止 — tasks/task-2.md）。
///
/// 契約（wave-4 で更新）: 入力欄内にモデル選択チップを提供する（Image #10/#11）。
/// wave-3 で一旦チップを撤去し右上メニューへ集約したが、wave-4 task-4 で入力欄内チップを
/// 復活させた（モデル変更は「入力欄チップ」と「右上メニュー」の両導線から到達可能）。
/// 静的フラグ `SessionDetailView.providesModelSelectorChip` で固定する（decision-log 参照）。
///
/// 注: トップバー・入力欄がタブバー上・メニュー項目・rename 反映・ピッカーシートの見た目は
/// SwiftUI View 層で自動テストの網羅対象外＝phase-4（実機/シミュレータ）で確認する。
@MainActor
@Suite struct Wave3SessionDetailChromeAcceptanceTests {
    @Test func modelSelectorChipRestoredInInputBar() {
        #expect(SessionDetailView.providesModelSelectorChip == true)
    }
}
