import Testing
@testable import DesignSystemIOS

/// 入力欄の右スロット（送信/停止）の出し分け。送信・停止の出方が変わると落ちる。
@MainActor
@Suite("DSInput bar action state") struct DSInputBarActionStateTests {
    @Test func idleEmptyInputAlwaysShowsDisabledSendSlot() {
        #expect(
            DSInputBar.actionState(text: "", isLoading: false, isRunning: false)
                == DSInputBarActionState(showsStop: false, showsSend: true, sendIsEnabled: false)
        )
        #expect(
            DSInputBar.actionState(text: "   ", isLoading: false, isRunning: false)
                == DSInputBarActionState(showsStop: false, showsSend: true, sendIsEnabled: false)
        )
    }

    @Test func enteredTextUsesEnabledSendSlot() {
        let state = DSInputBar.actionState(text: "Follow up", isLoading: false, isRunning: false)

        #expect(state == DSInputBarActionState(showsStop: false, showsSend: true, sendIsEnabled: true))
    }

    @Test func loadingTextKeepsSendSlotButDisablesIt() {
        let state = DSInputBar.actionState(text: "Follow up", isLoading: true, isRunning: false)

        #expect(state == DSInputBarActionState(showsStop: false, showsSend: true, sendIsEnabled: false))
    }

    @Test func runningRevealsSendOnlyWhenTextEntered() {
        #expect(
            DSInputBar.actionState(text: "", isLoading: false, isRunning: true)
                == DSInputBarActionState(showsStop: true, showsSend: false, sendIsEnabled: false)
        )
        #expect(
            DSInputBar.actionState(text: "draft", isLoading: false, isRunning: true)
                == DSInputBarActionState(showsStop: true, showsSend: true, sendIsEnabled: true)
        )
    }

    /// 実行中の送信直後は本文が空でも送信スロットを保つ（進捗表示が消えない）。
    @Test func runningKeepsSendSlotWhileSending() {
        #expect(
            DSInputBar.actionState(text: "", isLoading: true, isRunning: true)
                == DSInputBarActionState(showsStop: true, showsSend: true, sendIsEnabled: false)
        )
    }
}
