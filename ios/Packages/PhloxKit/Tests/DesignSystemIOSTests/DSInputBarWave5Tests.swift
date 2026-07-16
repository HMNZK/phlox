import Testing
@testable import DesignSystemIOS

@MainActor
@Suite struct DSInputBarWave5Tests {
    @Test func inputBarPreservesWave5InteractionsWithoutLegacyCardChrome() {
        #expect(!DSInputBar.providesCardChrome)
        #expect(!DSInputBar.providesDragToDismiss)
        #expect(!DSInputBar.providesVoiceInput)
        #expect(DSInputBar.usesFocusState)
        #expect(DSInputBar.providesInlineModelSelectorSlot)
    }
}
