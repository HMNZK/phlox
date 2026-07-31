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
        #expect(
            DSInputBar.actionState(text: "", isLoading: false, isRunning: false)
                == DSInputBarActionState(showsStop: false, sendIsEnabled: false)
        )
        #expect(
            DSInputBar.actionState(text: "   ", isLoading: false, isRunning: false)
                == DSInputBarActionState(showsStop: false, sendIsEnabled: false)
        )
    }

    @Test("テキスト入力時は有効な送信ボタン")
    func enteredTextEnablesSend() {
        #expect(
            DSInputBar.actionState(text: "hi", isLoading: false, isRunning: false)
                == DSInputBarActionState(showsStop: false, sendIsEnabled: true)
        )
    }

    @Test("送信中（isLoading）は送信ボタンを無効化する")
    func loadingDisablesSend() {
        #expect(
            DSInputBar.actionState(text: "hi", isLoading: true, isRunning: false)
                == DSInputBarActionState(showsStop: false, sendIsEnabled: false)
        )
    }

    @Test("実行中は停止ボタンを併置しつつ、送信ボタンも残して追加指示を送れる")
    func runningKeepsSendAlongsideStop() {
        #expect(
            DSInputBar.actionState(text: "", isLoading: false, isRunning: true)
                == DSInputBarActionState(showsStop: true, sendIsEnabled: false)
        )
        #expect(
            DSInputBar.actionState(text: "draft", isLoading: false, isRunning: true)
                == DSInputBarActionState(showsStop: true, sendIsEnabled: true)
        )
    }

    @Test("モデルセレクタ差し込みスロットとフォーカス state は維持（凍結 Task3 と整合）")
    func keepsModelSelectorSlotAndFocusState() {
        #expect(DSInputBar.providesInlineModelSelectorSlot)
        #expect(DSInputBar.usesFocusState)
    }
}
