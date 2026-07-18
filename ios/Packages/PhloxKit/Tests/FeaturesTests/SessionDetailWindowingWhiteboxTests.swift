import Testing
import PhloxCore
@testable import Features

@Suite("SessionDetail transcript windowing white-box")
struct SessionDetailWindowingWhiteboxTests {
    @Test("50件超では末尾50件だけを描画対象にする")
    func overLimitUsesTailOnly() {
        let messages = makeMessages(count: 120)
        let slice = SessionDetailTranscriptSlice(messages: messages, window: TranscriptWindow())

        #expect(slice.hiddenCount == 70)
        #expect(slice.visibleMessages.count == 50)
        #expect(slice.visibleMessages.first?.id == "m70")
        #expect(slice.visibleMessages.last?.id == "m119")
        #expect(slice.expansionAnchorID == "m70")
    }

    @Test("展開すると描画対象が50件増え、従来の先頭がアンカーになる")
    func expansionAddsFiftyMessages() {
        let messages = makeMessages(count: 120)
        var window = TranscriptWindow()
        let before = SessionDetailTranscriptSlice(messages: messages, window: window)

        window.expand()
        let after = SessionDetailTranscriptSlice(messages: messages, window: window)

        #expect(after.hiddenCount == 20)
        #expect(after.visibleMessages.count == 100)
        #expect(after.visibleMessages.first?.id == "m20")
        #expect(before.expansionAnchorID == "m70")
    }

    @Test("展開操作は従来の先頭を保持し、世代を進め、末尾追従を選ばない")
    func expansionDecisionPreservesViewportAnchor() {
        let messages = makeMessages(count: 120)

        let decision = SessionDetailTranscriptExpansionPolicy.expand(
            messages: messages,
            window: TranscriptWindow(),
            scrollGeneration: 7
        )

        #expect(decision.scrollTarget == .anchor("m70"))
        #expect(decision.scrollGeneration == 8)
        #expect(decision.scrollTarget != .bottom)
        let expandedSlice = SessionDetailTranscriptSlice(messages: messages, window: decision.window)
        #expect(expandedSlice.visibleMessages.first?.id == "m20")
    }

    @Test("50件以下では全件を描画し、折りたたみ情報を出さない")
    func withinLimitUsesAllMessages() {
        let messages = makeMessages(count: 50)
        let slice = SessionDetailTranscriptSlice(messages: messages, window: TranscriptWindow())

        #expect(slice.hiddenCount == 0)
        #expect(Array(slice.visibleMessages) == messages)
        #expect(slice.expansionAnchorID == nil)
    }

    @Test("reset後は末尾50件へ戻る")
    func resetReturnsToDefaultSlice() {
        let messages = makeMessages(count: 120)
        var window = TranscriptWindow()
        window.expand()
        window.reset()

        let slice = SessionDetailTranscriptSlice(messages: messages, window: window)

        #expect(slice.hiddenCount == 70)
        #expect(slice.visibleMessages.count == 50)
        #expect(slice.visibleMessages.first?.id == "m70")
    }

    private func makeMessages(count: Int) -> [ChatMessage] {
        (0..<count).map { .user(id: "m\($0)", text: "message \($0)") }
    }
}
