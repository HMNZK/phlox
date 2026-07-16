import Testing
@testable import ControlServer

/// task-5 受け入れテスト（PM 著・凍結。実装役は編集禁止 — tasks/task-5.md）。
/// 契約: モバイル向けモデル選択 API を ControlServer に追加する。
///   GET  /sessions/{id}/settings → 200 {"selectedModel": String?, "availableModels": [{"id","displayName"}]}
///   POST /sessions/{id}/model   body {"model": String} → 200（適用）/ 404（未知 id）/ 400（不正 body）
/// ワイヤ定数は iOS 側 PhloxModelWireContract と一字一句一致（シーム契約）。
@Suite struct Task5AcceptanceTests {
    @Test func modelSelectionAPIImplemented() {
        #expect(ControlModelWireContract.implemented)
    }

    /// ワイヤ形状の凍結（変更はシーム契約違反 — iOS 側と同時に壊れる）。
    @Test func wireContractShapeFrozen() {
        #expect(ControlModelWireContract.settingsPathSuffix == "/settings")
        #expect(ControlModelWireContract.modelPathSuffix == "/model")
        #expect(ControlModelWireContract.selectedModelKey == "selectedModel")
        #expect(ControlModelWireContract.availableModelsKey == "availableModels")
        #expect(ControlModelWireContract.modelIDKey == "id")
        #expect(ControlModelWireContract.modelDisplayNameKey == "displayName")
        #expect(ControlModelWireContract.modelKey == "model")
    }
}
