import Testing
import PhloxCore
@testable import Features

@Suite("SessionDetail transcript windowing white-box")
struct SessionDetailWindowingWhiteboxTests {
    @Test("50ブロック超では末尾50ブロックだけを描画対象にする")
    func overLimitUsesTailOnly() {
        let messages = makeMessages(count: 120)
        let slice = SessionDetailTranscriptSlice(messages: messages, window: TranscriptWindow())

        #expect(slice.hiddenCount == 70)
        #expect(slice.visibleMessages.count == 50)
        #expect(slice.visibleMessages.first?.id == "m70")
        #expect(slice.visibleMessages.last?.id == "m119")
        #expect(slice.expansionAnchorID == "m70")
    }

    @Test("展開すると描画対象が50ブロック増え、従来の先頭がアンカーになる")
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

    @Test("巨大なcommandGroupは1ブロックとして数え、可視message列と一致する")
    func commandGroupUsesOneWindowBlock() {
        let messages =
            (0..<60).map { ChatMessage.user(id: "u\($0)", text: "message \($0)") } +
            (0..<500).map { ChatMessage.command(id: "c\($0)", command: "cmd", output: "out") }
        let slice = SessionDetailTranscriptSlice(messages: messages, window: TranscriptWindow())

        #expect(slice.hiddenCount == 11)
        #expect(slice.visibleBlocks.count == TranscriptWindow.defaultLimit)
        #expect(slice.visibleBlocks.first?.id == "u11")
        #expect(Array(slice.visibleMessages) == Array(messages[11...]))
        #expect(slice.expansionAnchorID == "u11")
    }

    @Test("可視message列はid逆引きに依存せずブロック列と一致する")
    func visibleMessagesDoNotDependOnMessageIDUniqueness() {
        let messages =
            [ChatMessage.agent(id: "dup", text: "old"), ChatMessage.agent(id: "x", text: "x")] +
            [ChatMessage.agent(id: "dup", text: "new")] +
            (0..<49).map { ChatMessage.agent(id: "a\($0)", text: "t\($0)") }
        let slice = SessionDetailTranscriptSlice(messages: messages, window: TranscriptWindow())
        let flattened = slice.visibleBlocks.flatMap { visible -> [ChatMessage] in
            switch visible.content {
            case .single(let message): [message]
            case .commandGroup(_, let items): items
            }
        }

        #expect(slice.visibleBlocks.count == TranscriptWindow.defaultLimit)
        #expect(Array(slice.visibleMessages) == flattened)
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
