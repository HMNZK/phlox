import Testing
@testable import DesignSystemIOS

/// wave-7 入力欄整理の凍結受け入れテスト（PM 著・実装役は編集禁止）。
/// ドラッグバー廃止・音声入力ボタン廃止・送信/停止を右スロットに常設、を View 非依存で固定する。
@MainActor
@Suite struct Wave7InputBarContractTests {
    @Test("ドラッグで閉じる affordance を提供しない")
    func dropsDragToDismiss() {
        #expect(!DSInputBar.providesDragToDismiss)
    }

    @Test("音声入力ボタンを提供しない")
    func dropsVoiceInput() {
        #expect(!DSInputBar.providesVoiceInput)
    }

    @Test("空入力・実行外でも右スロットに送信ボタンを常設する（無効状態）")
    func idleEmptyStillPlacesDisabledSend() {
        #expect(DSInputBar.actionState(text: "", isLoading: false, isRunning: false) == .send(isEnabled: false))
        #expect(DSInputBar.actionState(text: "   ", isLoading: false, isRunning: false) == .send(isEnabled: false))
    }

    @Test("テキスト入力時は有効な送信ボタン")
    func enteredTextEnablesSend() {
        #expect(DSInputBar.actionState(text: "hi", isLoading: false, isRunning: false) == .send(isEnabled: true))
    }

    @Test("送信中（isLoading）は送信ボタンを無効化する")
    func loadingDisablesSend() {
        #expect(DSInputBar.actionState(text: "hi", isLoading: true, isRunning: false) == .send(isEnabled: false))
    }

    @Test("実行中は空でも入力中でも同じスロットに停止ボタン")
    func runningShowsStopInSameSlot() {
        #expect(DSInputBar.actionState(text: "", isLoading: false, isRunning: true) == .stop)
        #expect(DSInputBar.actionState(text: "draft", isLoading: false, isRunning: true) == .stop)
    }

    @Test("モデルセレクタ差し込みスロットとフォーカス state は維持（凍結 Task3 と整合）")
    func keepsModelSelectorSlotAndFocusState() {
        #expect(DSInputBar.providesInlineModelSelectorSlot)
        #expect(DSInputBar.usesFocusState)
    }
}
