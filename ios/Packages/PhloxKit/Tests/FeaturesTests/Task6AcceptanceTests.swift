import Testing
import PhloxNetworking
@testable import Features

/// task-6 受け入れテスト（PM 著・凍結。実装役は編集禁止 — tasks/task-6.md）。
/// 契約: セッション詳細の入力バー付近にモデル選択チップを置き、タップでモデル選択シート
/// （一覧＋checkmark）を開き、選択で POST sessions/{id}/model を叩く。
/// ワイヤ定数は macOS 側 ControlModelWireContract と一字一句一致（シーム契約）。
@MainActor
@Suite struct Task6AcceptanceTests {
    // sessionDetailProvidesModelSelectorChip（モデルチップ提供の表明）は wave-3 で一旦撤去（メニューへ集約）→
    // wave-4 task-4 で入力欄内チップを復活。現行契約は Wave3SessionDetailChromeAcceptanceTests.modelSelectorChipRestoredInInputBar
    // （providesModelSelectorChip == true）に集約（decision-log 参照）。

    @Test func apiClientImplementsModelSelection() {
        #expect(PhloxModelWireContract.implemented)
    }

    /// ワイヤ形状の凍結（変更はシーム契約違反 — macOS 側と同時に壊れる）。
    @Test func wireContractShapeFrozen() {
        #expect(PhloxModelWireContract.settingsPathSuffix == "settings")
        #expect(PhloxModelWireContract.modelPathSuffix == "model")
        #expect(PhloxModelWireContract.selectedModelKey == "selectedModel")
        #expect(PhloxModelWireContract.availableModelsKey == "availableModels")
        #expect(PhloxModelWireContract.modelIDKey == "id")
        #expect(PhloxModelWireContract.modelDisplayNameKey == "displayName")
        #expect(PhloxModelWireContract.modelKey == "model")
    }
}
