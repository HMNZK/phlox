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
                == DSInputBarActionState(showsStop: false, showsSend: true, sendIsEnabled: false)
        )
        #expect(
            DSInputBar.actionState(text: "   ", isLoading: false, isRunning: false)
                == DSInputBarActionState(showsStop: false, showsSend: true, sendIsEnabled: false)
        )
    }

    @Test("テキスト入力時は有効な送信ボタン")
    func enteredTextEnablesSend() {
        #expect(
            DSInputBar.actionState(text: "hi", isLoading: false, isRunning: false)
                == DSInputBarActionState(showsStop: false, showsSend: true, sendIsEnabled: true)
        )
    }

    @Test("送信中（isLoading）は送信ボタンを無効化する")
    func loadingDisablesSend() {
        #expect(
            DSInputBar.actionState(text: "hi", isLoading: true, isRunning: false)
                == DSInputBarActionState(showsStop: false, showsSend: true, sendIsEnabled: false)
        )
    }

    @Test("実行中は空入力なら停止のみ、打ち始めたら送信を併置して追加指示を送れる")
    func runningRevealsSendOnlyWhenTextEntered() {
        #expect(
            DSInputBar.actionState(text: "", isLoading: false, isRunning: true)
                == DSInputBarActionState(showsStop: true, showsSend: false, sendIsEnabled: false)
        )
        #expect(
            DSInputBar.actionState(text: "draft", isLoading: false, isRunning: true)
                == DSInputBarActionState(showsStop: true, showsSend: true, sendIsEnabled: true)
        )
    }

    @Test("実行中の送信直後は本文が空でも送信スロットを保つ（進捗表示が消えない）")
    func runningKeepsSendSlotWhileSending() {
        #expect(
            DSInputBar.actionState(text: "", isLoading: true, isRunning: true)
                == DSInputBarActionState(showsStop: true, showsSend: true, sendIsEnabled: false)
        )
    }

    @Test("モデルセレクタ差し込みスロットとフォーカス state は維持（凍結 Task3 と整合）")
    func keepsModelSelectorSlotAndFocusState() {
        #expect(DSInputBar.providesInlineModelSelectorSlot)
        #expect(DSInputBar.usesFocusState)
    }
}
