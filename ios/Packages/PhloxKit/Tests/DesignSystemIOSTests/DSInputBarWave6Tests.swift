import Testing
@testable import DesignSystemIOS

@MainActor
@Suite struct DSInputBarWave6Tests {
    @Test func idleEmptyInputAlwaysShowsDisabledSendSlot() {
        let state = DSInputBar.actionState(text: "", isLoading: false, isRunning: false)

        #expect(state == DSInputBarActionState(showsStop: false, showsSend: true, sendIsEnabled: false))
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

    @Test func inputBarPublishesCompactNeutralPillContract() {
        #expect(DSInputBar.providesPillChrome)
        #expect(DSInputBar.providesInlineModelSelectorSlot)
        #expect(DSInputBar.usesNeutralFocusBorder)
        #expect(!DSInputBar.usesAccentFocusBorder)
        #expect(DSInputBar.maximumTextLineCount == 4)
        #expect(DSInputBar.stopButtonIconName == "stop.fill")
        #expect(DSInputBar.stopAccessibilityLabel == "停止")
    }
}
