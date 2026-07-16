import Testing
@testable import DesignSystemIOS

@MainActor
@Suite struct DSInputBarWave6Tests {
    @Test func idleEmptyInputAlwaysShowsDisabledSendSlot() {
        let state = DSInputBar.actionState(text: "", isLoading: false, isRunning: false)

        #expect(state == .send(isEnabled: false))
    }

    @Test func enteredTextUsesEnabledSendSlot() {
        let state = DSInputBar.actionState(text: "Follow up", isLoading: false, isRunning: false)

        #expect(state == .send(isEnabled: true))
    }

    @Test func loadingTextKeepsSendSlotButDisablesIt() {
        let state = DSInputBar.actionState(text: "Follow up", isLoading: true, isRunning: false)

        #expect(state == .send(isEnabled: false))
    }

    @Test func runningAlwaysReplacesSendWithStopInTheSameSlot() {
        #expect(DSInputBar.actionState(text: "", isLoading: false, isRunning: true) == .stop)
        #expect(DSInputBar.actionState(text: "draft", isLoading: false, isRunning: true) == .stop)
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
