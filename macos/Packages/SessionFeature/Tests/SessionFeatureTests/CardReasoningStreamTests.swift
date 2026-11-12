import AgentDomain
import Foundation
import StructuredChatKit
import Testing
@testable import SessionFeature

@Suite("カード内の思考ストリーム") @MainActor
struct CardReasoningStreamTests {
    private let time = Date(timeIntervalSince1970: 1_800_000_000)
    private let sessionID = SessionID()
    private let executionID = UUID()
    private let live = AgentStatusLiveState(isProcessing: true, activityState: .thinking,
        hangAssessment: nil, isAwaitingReply: false)

    @Test("Codex の思考要約だけを隠し、進捗文と作業は残す")
    func codexHidesSummaryWithoutChangingStoredItems() throws {
        let items: [ChatItem] = [input(completed: true), thought("summary", "Reviewing gate results"),
            .agentMessage(id: "progress", text: "検査中です", timestamp: time),
            .commandExecution(id: "work", command: "swift test", output: "ok", timestamp: time),
            .agentMessage(id: "answer", text: "完了しました", timestamp: time)]
        let idle = AgentStatusLiveState(isProcessing: false, activityState: .thinking,
            hangAssessment: nil, isAwaitingReply: false)

        let codex = AgentStatusCardRouting.blocks(items: items, agent: .codex, liveState: idle)
        let claude = AgentStatusCardRouting.blocks(items: items, agent: .claudeCode, liveState: idle)
        let codexCard = try #require(codex.compactMap { if case .statusCard(let card) = $0 { card } else { nil } }.first)
        let claudeCard = try #require(claude.compactMap { if case .statusCard(let card) = $0 { card } else { nil } }.first)

        #expect(codex.map(\.id) == ["input", "progress", "status-card-input", "answer"])
        #expect(entryIDs(codexCard) == ["work"])
        #expect(entryIDs(claudeCard) == ["summary", "progress", "work"])
        #expect(codex.last?.id == "answer")
        #expect(items.count == 5)
    }

    @Test("Codex の常駐読み取りは思考要約の追記後も進捗を表示する")
    func codexRuntimeReadKeepsProgressAfterHiddenSummaryUpdate() async throws {
        let store = RuntimeChatReadIndexStore()
        let first = [input(), thought("summary", "Reviewing")]
        _ = try await read(store, items: first, revision: 1, target: .chatReadTail, agent: .codex)
        store.invalidate(from: 1, itemIDs: ["summary"])
        let second = [input(), thought("summary", "Reviewing gate results"),
            .agentMessage(id: "progress", text: "検査中です", timestamp: time),
            .commandExecution(id: "work", command: "swift test", output: "ok", timestamp: time)]
        let response = try await read(store, items: second, revision: 2, target: .chatReadTail, agent: .codex)
        guard case .chatReadPage(let page) = response else { throw SessionRuntimeContentError.invalidRequest }
        #expect(page.blocks.map(\.id) == ["input", "progress", "status-card-input"])
        #expect(page.blocks.allSatisfy { $0.id != "summary" })
    }

    @Test("先頭思考から途中本文と作業までカード内の受信順を保つ")
    func leadingThoughtStartsTheCardBeforeProgressAndWork() throws {
        let items: [ChatItem] = [input(),
            .agentMessage(id: "intro", text: "確認します", timestamp: time),
            thought("thought", "先頭の思考\n\n二段落目"),
            .agentMessage(id: "progress", text: "調査中です", timestamp: time),
            .commandExecution(id: "work", command: "swift --version", output: "", timestamp: time)]

        let blocks = AgentStatusCardBuilder.build(items: items, liveState: live)
        let card = try #require(blocks.compactMap { if case .statusCard(let card) = $0 { card } else { nil } }.first)

        #expect(blocks.map(\.id) == ["input", "intro", "status-card-input"])
        #expect(entryIDs(card) == ["thought", "progress", "work"])
        #expect(AgentStatusCardBuilder.visibleSlice(items: items, liveState: live, blockLimit: 2).hiddenBlockCount == 1)
    }

    @Test("思考だけで終わる応答も完了後の思考をカード内に残す")
    func completedThoughtOnlyTurnKeepsThoughtInCardAndAnswerOutside() throws {
        let items: [ChatItem] = [input(completed: true), thought("thought", "判断の理由"),
            .agentMessage(id: "answer", text: "結論です", timestamp: time)]
        let idle = AgentStatusLiveState(isProcessing: false, activityState: .thinking,
            hangAssessment: nil, isAwaitingReply: false)

        let blocks = AgentStatusCardBuilder.build(items: items, liveState: idle)
        let card = try #require(blocks.compactMap { if case .statusCard(let card) = $0 { card } else { nil } }.first)

        #expect(blocks.map(\.id) == ["input", "status-card-input", "answer"])
        #expect(entryIDs(card) == ["thought"])
    }

    @Test("空白だけの思考と通常返答では不要なカードを作らない")
    func blankThoughtDoesNotCreateACompletedCard() {
        let idle = AgentStatusLiveState(isProcessing: false, activityState: .thinking,
            hangAssessment: nil, isAwaitingReply: false)
        let blocks = AgentStatusCardBuilder.build(items: [input(completed: true),
            thought("blank", " \n\t"), .agentMessage(id: "answer", text: "返答です", timestamp: time)], liveState: idle)

        #expect(!blocks.contains { if case .statusCard = $0 { true } else { false } })
    }

    @Test("常駐読み取りの初期生成でも先頭思考をカード所属として直接表示できる")
    func runtimeInitialReadRevealsThoughtInsideItsCard() async throws {
        let response = try await read(RuntimeChatReadIndexStore(), items: [input(),
            thought("thought", "最初の思考"), .agentMessage(id: "progress", text: "続けます", timestamp: time),
            .commandExecution(id: "work", command: "swift --version", output: "", timestamp: time)], revision: 1,
            target: .chatReadAroundItem(itemID: "thought"))
        guard case .chatReadPage(let page) = response else { throw SessionRuntimeContentError.invalidRequest }

        #expect(page.blocks.map(\.id) == ["status-card-input"])
        #expect(page.revealTarget?.cardID == "status-card-input")
        #expect(page.revealTarget?.entryID == "thought")
    }

    @Test("空の思考への同ID追記と後続思考がカード外へ漏れず最新全文を返す")
    func runtimeIncrementalStreamKeepsLatestThoughtBodyInCard() async throws {
        let store = RuntimeChatReadIndexStore()
        let empty = [input(), thought("thought", " ")]
        _ = try await read(store, items: empty, revision: 1, target: .chatReadTail)
        store.invalidate(from: 1, itemIDs: ["thought"])
        let first = [input(), thought("thought", "先頭")]
        _ = try await read(store, items: first, revision: 2, target: .chatReadTail)
        let appended = first + [thought("second", "次の思考")]
        let appendedReply = try await read(store, items: appended, revision: 3,
            target: .chatReadAroundItem(itemID: "second"))
        store.invalidate(from: 1, itemIDs: ["thought"])
        let final = [input(), thought("thought", "先頭\n\n追記した末尾"), thought("second", "次の思考")]
        let reveal = try await read(store, items: final, revision: 4, target: .chatReadAroundItem(itemID: "thought"))
        guard case .chatReadPage(let page) = reveal, case .chatReadPage(let appendedPage) = appendedReply else {
            throw SessionRuntimeContentError.invalidRequest
        }
        let rowID = try #require(page.revealTarget?.rowID)
        let detail = try await read(store, items: final, revision: 4,
            target: .chatRowEntries(inputID: "input", rowID: rowID, cursor: nil))
        guard case .cardEntriesPage(let entries) = detail else { throw SessionRuntimeContentError.invalidRequest }
        let texts = entries.entries.compactMap { entry -> String? in
            if case .item(.inline(.reasoning(_, let text, _))) = entry { text } else { nil }
        }

        #expect(appendedPage.revealTarget?.cardID == "status-card-input")
        #expect(page.revealTarget?.cardID == "status-card-input")
        #expect(texts == ["先頭\n\n追記した末尾", "次の思考"])
    }

    private func input(completed: Bool = false) -> ChatItem {
        .userMessage(id: "input", text: "内容を確認", timestamp: time, attachments: [],
            turnEnd: completed ? .init(outcome: .completed, at: time.addingTimeInterval(3)) : nil)
    }

    private func thought(_ id: String, _ text: String) -> ChatItem {
        .reasoning(id: id, text: text, timestamp: time)
    }

    private func entryIDs(_ card: AgentStatusCard) -> [String] {
        card.rows.flatMap { row in
            switch row {
            case .task(let task): task.entries.map(\.id)
            case .outside(let group): group.entries.map(\.id)
            }
        }
    }

    private func read(_ store: RuntimeChatReadIndexStore, items: [ChatItem], revision: Int,
        target: SessionRuntimeContentRequest.Target, agent: AgentKind = .claudeCode) async throws -> SessionRuntimeContentResponse {
        try await store.response(items: items, executionID: executionID, revision: revision,
            liveState: live, usesCards: true, agent: agent,
            request: .init(sessionID: sessionID, executionID: executionID, target: target), usage: [:])
    }
}
