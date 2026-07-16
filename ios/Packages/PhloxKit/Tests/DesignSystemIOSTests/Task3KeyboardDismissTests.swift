import Testing
@testable import DesignSystemIOS

/// task-3 白箱テスト。wave-4 で「完了」ツールバー廃止を契約化（キーボード閉じはスクロール委譲）。
@Suite struct Task3KeyboardDismissTests {
    @Test func keyboardDismissToolbarRemoved() {
        #expect(!DSInputBar.providesKeyboardDismissToolbar)
        #expect(DSInputBar.providesInlineModelSelectorSlot)
    }

    @Test func focusStateContractUnchanged() {
        #expect(DSInputBar.usesFocusState)
    }

    @Test func sendBarInvariantsUnchanged() {
        #expect(DSInputBar.sendAccessibilityLabel == "送信")
        #expect(!DSInputBar.canSubmit(text: "", isLoading: false))
        #expect(DSInputBar.canSubmit(text: "hello", isLoading: false))
    }
}
