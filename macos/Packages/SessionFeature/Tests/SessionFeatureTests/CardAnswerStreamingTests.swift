import AgentDomain
import Foundation
import StructuredChatKit
import Testing
@testable import SessionFeature

@Suite("末尾回答は生成中からカード外") @MainActor
struct CardAnswerStreamingTests {
    private let time = Date(timeIntervalSince1970: 1_800_000_000)
    private let sessionID = SessionID()
    private let executionID = UUID()
    private let live = AgentStatusLiveState(isProcessing: true, activityState: .thinking,
        hangAssessment: nil, isAwaitingReply: false)
    private let idle = AgentStatusLiveState(isProcessing: false, activityState: .thinking,
        hangAssessment: nil, isAwaitingReply: false)

    @Test("途中の進捗と思考は内側、末尾回答は生成中も完了後も同じ外側の位置")
    func builderKeepsStreamingAnswerOutsideWithoutMovingProgress() throws {
        let items = base + [message("progress", "次を確認します"), command("second"), message("answer", "結論です")]

        let running = AgentStatusCardBuilder.build(items: items, liveState: live)
        let finished = AgentStatusCardBuilder.build(items: items, liveState: idle)
        let card = try #require(running.compactMap { if case .statusCard(let card) = $0 { card } else { nil } }.first)
        let slice = AgentStatusCardBuilder.visibleSlice(items: items, liveState: live, blockLimit: 2)

        #expect(running.map(\.id) == ["input", "status-card-input", "answer"])
        #expect(finished.map(\.id) == ["input", "status-card-input", "answer"])
        #expect(card.rows.flatMap { row -> [String] in
            switch row {
            case .task(let task): task.entries.map(\.id)
            case .outside(let group): group.entries.map(\.id)
            }
        } == ["thought", "work", "progress", "second"])
        #expect(slice.hiddenBlockCount == 1)
        #expect(slice.blocks.map(\.id) == ["status-card-input", "answer"])
    }

    @Test("常駐読み取りの初期生成でも回答へカード外の項目としてジャンプできる")
    func initialReadTreatsTheStreamingAnswerAsAnExternalItem() async throws {
        let response = try await read(RuntimeChatReadIndexStore(), items: base + [message("answer", "結論の先頭")],
            revision: 1, target: .chatReadAroundItem(itemID: "answer"))
        guard case .chatReadPage(let page) = response else { throw SessionRuntimeContentError.invalidRequest }

        #expect(page.blocks.map(\.id) == ["answer"])
        #expect(page.revealTarget?.cardID == nil)
        #expect(page.revealTarget?.scrollTargetID == "answer")
        #expect(answerText(page) == "結論の先頭")
    }

    @Test("回答の追加と同ID追記は外側、後続作業が来た途中文章だけを内側へ戻す")
    func incrementalReadUpdatesAnExternalAnswerAndReclassifiesOnlySupersededProgress() async throws {
        let store = RuntimeChatReadIndexStore()
        _ = try await read(store, items: base, revision: 1)
        let firstItems = base + [message("draft", "途中")]
        let first = try await read(store, items: firstItems, revision: 2)
        store.invalidate(from: 3, itemIDs: ["draft"])
        let updatedItems = base + [message("draft", "途中の追記")]
        let updated = try await read(store, items: updatedItems, revision: 3)
        let following = updatedItems + [command("second")]
        _ = try await read(store, items: following, revision: 4)
        let finalItems = following + [message("answer", "最終回答")]
        let final = try await read(store, items: finalItems, revision: 5)
        let entries = try await read(store, items: finalItems, revision: 5,
            target: .chatRowEntries(inputID: "input", rowID: "outside-thought", cursor: nil))
        guard case .chatReadPage(let firstPage) = first, case .chatReadPage(let updatedPage) = updated,
            case .chatReadPage(let finalPage) = final, case .cardEntriesPage(let entryPage) = entries else {
            throw SessionRuntimeContentError.invalidRequest
        }

        #expect(firstPage.blocks.map(\.id) == ["input", "status-card-input", "draft"])
        #expect(updatedPage.blocks.map(\.id) == ["input", "status-card-input", "draft"])
        #expect(answerText(updatedPage) == "途中の追記")
        #expect(finalPage.blocks.map(\.id) == ["input", "status-card-input", "answer"])
        #expect(answerText(finalPage) == "最終回答")
        #expect(entryPage.entries.map(\.id) == ["thought", "work", "draft", "second"])
    }

    @Test("カード外の回答への追記は、変更していないカード詳細を無効にしない")
    func answerDeltaDoesNotInvalidateUnchangedCardDetails() async throws {
        let store = RuntimeChatReadIndexStore()
        let before = try await read(store, items: base + [message("answer", "結論")], revision: 1)
        store.invalidate(from: 3, itemIDs: ["answer"])

        let after = try await read(store, items: base + [message("answer", "結論の追記")], revision: 2)
        guard case .chatReadPage(let first) = before, case .chatReadPage(let second) = after else {
            throw SessionRuntimeContentError.invalidRequest
        }
        let firstCard = try #require(first.blocks.compactMap { if case .card(let card) = $0.content { card } else { nil } }.first)
        let secondCard = try #require(second.blocks.compactMap { if case .card(let card) = $0.content { card } else { nil } }.first)

        #expect(secondCard.contentRevision == firstCard.contentRevision)
        #expect(secondCard.revision == firstCard.revision)
        #expect(answerText(second) == "結論の追記")
    }

    private var base: [ChatItem] {
        [.userMessage(id: "input", text: "点検してください", timestamp: time, attachments: []),
         .reasoning(id: "thought", text: "判断するための思考", timestamp: time), command("work")]
    }

    private func command(_ id: String) -> ChatItem {
        .commandExecution(id: id, command: "swift --version", output: "確認済み", timestamp: time, completedAt: time)
    }

    private func message(_ id: String, _ text: String) -> ChatItem {
        .agentMessage(id: id, text: text, timestamp: time)
    }

    private func answerText(_ page: SessionRuntimeChatReadPage) -> String? {
        page.blocks.compactMap { if case .item(.inline(.agentMessage(_, let text, _))) = $0.content { text } else { nil } }.last
    }

    private func read(_ store: RuntimeChatReadIndexStore, items: [ChatItem], revision: Int,
        target: SessionRuntimeContentRequest.Target = .chatReadTail) async throws -> SessionRuntimeContentResponse {
        try await store.response(items: items, executionID: executionID, revision: revision,
            liveState: live, usesCards: true,
            request: .init(sessionID: sessionID, executionID: executionID, target: target), usage: [:])
    }
}
