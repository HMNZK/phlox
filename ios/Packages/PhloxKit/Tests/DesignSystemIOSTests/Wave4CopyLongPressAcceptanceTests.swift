import Testing
@testable import DesignSystemIOS

/// wave-4 task-5 受け入れ（PM 著）。チャットバブルのコピーを「常時表示ボタン」から
/// 「長押し（contextMenu）」へ変更した契約を回帰ガードする。常時ボタンへ戻したり
/// 長押しコピーを外すと fail する。
@Suite struct Wave4CopyLongPressAcceptanceTests {
    @Test func bubbleCopyUsesLongPressNotAlwaysVisibleButton() {
        #expect(DSChatBubble.providesLongPressCopy)
        #expect(!DSChatBubble.providesAlwaysVisibleCopyButton)
    }
}
