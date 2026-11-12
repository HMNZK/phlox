import Foundation
import Testing
import PhloxCore
import ChatRenderKit
@testable import Features

@Suite struct MobileStatusCardPresentationTests {
    private func row(_ state: MobileStatusTranscript.RowState, auto: Bool) -> MobileStatusTranscript.Row {
        .init(id: "task", kind: .task, title: "確認", state: state, autoExpanded: auto,
              startedAt: nil, endedAt: nil, entries: [])
    }
    @Test func activeTaskFollowsServerUntilUserChooses() {
        var disclosure = MobileStatusCardDisclosure()
        let active = row(.inProgress, auto: true)
        let done = row(.completed, auto: false)
        #expect(disclosure.isExpanded(active))
        #expect(!disclosure.isExpanded(done))
        disclosure.toggle(active)
        #expect(!disclosure.isExpanded(active))
        disclosure.toggle(done)
        #expect(disclosure.isExpanded(done))
        #expect(disclosure.isExpanded(active))
    }
    @Test func actionDurationKeepsSubsecondWorkVisible() {
        #expect(ChatDurationFormat.action(0.04) == "<0.1s")
        #expect(ChatDurationFormat.action(0.9) == "0.9s")
        #expect(ChatDurationFormat.action(14.8) == "14s")
        #expect(ChatDurationFormat.action(72) == "1:12")
    }
    @Test func outsideProseIsNeverHiddenBehindDisclosure() {
        let prose = MobileStatusTranscript.Row(id: "outside", kind: .outside, title: "", state: .completed,
            autoExpanded: false, startedAt: nil, endedAt: nil, entries: [.message(id: "prose")])
        #expect(MobileStatusCardDisclosure.isTextOnly(prose))
    }
    @Test func projectionControlsConversationOrderWithoutDuplicatingFinalReply() {
        let messages: [ChatMessage] = [.agent(id: "final", text: "完了"), .user(id: "input", text: "調査"),
            .command(id: "work", command: "Read file", output: "result")]
        let transcript = MobileStatusTranscript(blocks: [.messages(ids: ["input"]),
            .card(.init(id: "card", state: .completed, title: "完了", startedAt: .distantPast,
                endedAt: .distantPast, activityState: .thinking, silence: nil,
                rows: [.init(id: "work-row", kind: .outside, title: "作業", state: .completed,
                    autoExpanded: false, startedAt: nil, endedAt: nil,
                    entries: [.message(id: "work")])])), .messages(ids: ["final"])])
        let blocks = SessionDetailToolCallGrouping.blocks(from: messages, statusTranscript: transcript)
        #expect(blocks.map(\.id) == ["input", "card", "final"])
        #expect(SessionDetailToolCallGrouping.scrollTargetID(containing: "work", in: messages, statusTranscript: transcript) == "card")
        let slice = SessionDetailToolCallGrouping.visibleSlice(from: messages, blockLimit: 2, statusTranscript: transcript)
        #expect(slice.blocks.map(\.id) == ["card", "final"])
        #expect(slice.hiddenBlockCount == 1)
        let windowed = SessionDetailTranscriptSlice(messages: messages, window: TranscriptWindow(), statusTranscript: transcript)
        #expect(Set(windowed.visibleMessages.map(\.id)) == ["input", "work", "final"])
        let orphan: ChatMessage = .error(id: "late", message: "遅れて届いたエラー")
        #expect(SessionDetailToolCallGrouping.blocks(from: messages + [orphan], statusTranscript: transcript).map(\.id) == ["input", "card", "final", "late"])
    }
}
