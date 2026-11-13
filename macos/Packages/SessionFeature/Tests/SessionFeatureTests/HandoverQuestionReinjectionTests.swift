import Foundation
import Testing
import AgentDomain
import CodexAppServerKit
import StructuredChatKit
@testable import SessionFeature

/// 計画的なホスト更新（ADR 0233）で、Codexの未回答の質問が新ホストで1件だけ、元のIDのまま、質問待ちとして残る。
/// 旧ホストが会話ログに保存したカードと、新ホストが再投入した同じ要求から作るカードが同じIDになることを、
/// 2つの画面状態と2つのブローカー（別のホスト役）で確かめる。

private let questionRequest = ToolRequestUserInputRequest(
    threadId: "t1", turnId: "turn-1", itemId: "question-item",
    questions: [ToolRequestUserInputQuestion(id: "choice", header: "確認", question: "続けますか？",
                                             options: [ToolRequestUserInputOption(label: "続ける", description: "")])])

private actor MemoryTranscriptStore: TranscriptStore {
    private var items: [ChatItem] = []
    func loadTranscript(for sessionID: SessionID) async throws -> [ChatItem] { items }
    func upsertTranscriptItems(_ items: [ChatItem], for sessionID: SessionID) async throws {
        for item in items {
            if let index = self.items.firstIndex(where: { $0.id == item.id }) { self.items[index] = item } else { self.items.append(item) }
        }
    }
    func replaceTranscript(for sessionID: SessionID, with items: [ChatItem]) async throws { self.items = items }
    func saveTurnUsageSnapshot(_ usage: TurnUsage, for sessionID: SessionID) async throws {}
}

/// 採用できるCodexクライアントの代役。`completeAdoption`で保存した要求を新しいブローカーへ再投入し、
/// `thread/read`は本物と同じく質問待ちを`active`＋`waitingOnUserInput`で返す。
private final class AdoptingCodexClient: StructuredAgentClient, CodexSettingsProviding, HandoverCapableClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    let threadEvents: AsyncStream<ThreadEvent>
    private let eventContinuation: AsyncStream<NormalizedChatEvent>.Continuation
    private let threadEventContinuation: AsyncStream<ThreadEvent>.Continuation
    private let reinject: @Sendable () -> Void
    /// 再投入した要求が画面へ届いてから`thread/read`に答える（本物も再投入した行が後続の応答より先に届く）。
    var beforeRead: (@Sendable () async -> Void)?

    init(reinject: @escaping @Sendable () -> Void) {
        self.reinject = reinject
        (events, eventContinuation) = AsyncStream.makeStream()
        (threadEvents, threadEventContinuation) = AsyncStream.makeStream()
    }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async {
        eventContinuation.finish()
        threadEventContinuation.finish()
    }

    func handoverGateReason() async -> String? { nil }
    func prepareHandover(fence: UUID) async throws -> HandoverPreparation { throw HandoverError.notReady("代役") }
    func cancelHandover() async {}
    func commitHandover(confirmedThrough: UInt64) async {}
    func completeAdoption() async throws { reinject() }

    func activeThreadId() async -> String? { "t1" }
    func initialize(_ params: InitializeParams) async throws -> InitializeResponse {
        try decode(#"{"codexHome":"/tmp","platformFamily":"macOS","platformOs":"macOS","userAgent":"test"}"#)
    }
    func threadStart(_ params: ThreadStartParams) async throws -> ThreadResponse { throw HandoverError.notReady("再発行しない") }
    func threadResume(_ params: ThreadResumeParams) async throws -> ThreadResponse { throw HandoverError.notReady("再発行しない") }
    func threadRead(_ params: ThreadReadParams) async throws -> ThreadReadResponse {
        await beforeRead?()
        return try decode(#"{"thread":{"id":"t1","status":{"type":"active","activeFlags":["waitingOnUserInput"]},"turns":[{"id":"turn-1","status":"inProgress","items":[]}]}}"#)
    }
    func listModels(_ params: ModelListParams) async throws -> ModelListResponse { try decode(#"{"data":[]}"#) }
    func listPermissionProfiles(_ params: PermissionProfileListParams) async throws -> PermissionProfileListResponse {
        try decode(#"{"data":[]}"#)
    }
    func listCollaborationModes(_ params: CollaborationModeListParams) async throws -> CollaborationModeListResponse {
        try decode(#"{"data":[]}"#)
    }
    func updateThreadSettings(_ params: ThreadSettingsUpdateParams) async throws -> ThreadSettingsUpdateResponse {
        ThreadSettingsUpdateResponse()
    }

    private func decode<T: Decodable>(_ json: String) throws -> T { try JSONDecoder().decode(T.self, from: Data(json.utf8)) }
}

/// ブローカーの待ちが決着した結果を1回だけ記録する。
private actor WireOutcome {
    private(set) var results: [JSONValue] = []
    func record(_ value: JSONValue) { results.append(value) }
}

@MainActor
private func waitUntil(_ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(3)
    while !condition() {
        guard ContinuousClock.now < deadline else { return false }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return true
}

private func pendingQuestionIDs(_ items: [ChatItem]) -> [String] {
    items.compactMap { if case .userQuestion(_, let id, _, _, .pending, _) = $0 { id } else { nil } }
}

@Test @MainActor
func adoptedCodexQuestion_isPresentedOnceWithTheOriginalIDAndStaysAwaiting() async throws {
    let sessionID = SessionID()
    let store = MemoryTranscriptStore()

    // 旧ホスト役: 質問を受けて会話ログに保存する（未回答のまま）。
    let oldBroker = ChatApprovalBroker()
    let oldVM = ChatSessionViewModel(id: sessionID, agentRef: .builtin(.codex), client: AdoptingCodexClient(reinject: {}),
                                     approvalBroker: oldBroker, workingDirectory: nil, transcriptStore: store)
    let oldWire = Task { _ = try? await oldBroker.serverRequestHandler(.userInputRequest(questionRequest)) }
    #expect(await waitUntil { pendingQuestionIDs(oldVM.transcript).count == 1 })
    let originalID = try #require(pendingQuestionIDs(oldVM.transcript).first)
    await oldVM.flushTranscriptNow()
    let saved = try await store.loadTranscript(for: sessionID)
    #expect(pendingQuestionIDs(saved) == [originalID])

    // 新ホスト役: 同じ保存先から採用し、同じ要求の原文を新しいブローカーへ再投入する。
    let newBroker = ChatApprovalBroker()
    let outcome = WireOutcome()
    let client = AdoptingCodexClient(reinject: {
        Task { if let value = try? await newBroker.serverRequestHandler(.userInputRequest(questionRequest)) { await outcome.record(value) } }
    })
    let newVM = ChatSessionViewModel(id: sessionID, agentRef: .builtin(.codex), client: client,
                                     approvalBroker: newBroker, workingDirectory: nil, transcriptStore: store)
    client.beforeRead = { @MainActor in
        _ = await waitUntil { newVM.status == .awaitingUserQuestion }
    }

    await newVM.adoptHandover(threadId: "t1")

    #expect(newVM.restoreState == .restored)
    #expect(pendingQuestionIDs(newVM.transcript) == [originalID], "再投入した質問が元のIDの1件にならない")
    #expect(newVM.status == .awaitingUserQuestion, "採用後の読み取りで質問待ちが上書きされた")
    #expect(!newVM.transcript.contains { if case .userQuestion(_, _, _, _, .expired, _) = $0 { true } else { false } })

    // 元のIDで答えると、再投入した要求が1回だけ回答で決着する。
    #expect(await newVM.respondToUserQuestion(requestId: originalID, answers: ["choice": ["続ける"]]))
    #expect(await newVM.respondToUserQuestion(requestId: originalID, answers: ["choice": ["続ける"]]) == false)
    let deadline = ContinuousClock.now + .seconds(3)
    while await outcome.results.isEmpty, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
    let results = await outcome.results
    #expect(results.count == 1)
    #expect(results.first?["answers"]?["choice"]?["answers"] == .array([.string("続ける")]))

    await newVM.terminate()
    await oldVM.terminate()
    _ = await oldWire.value
}

@Test
func codexQuestionID_isStableAcrossBrokersAndDistinctWhilePending() async throws {
    /// 要求を未回答のまま流し、ブローカーが付けたIDを届いた順に返す（期限付き。期限切れは空）。
    func ids(_ broker: ChatApprovalBroker, _ requests: [ToolRequestUserInputRequest]) async -> [UUID] {
        let stream = await broker.userInputRequests
        for request in requests { Task { _ = try? await broker.serverRequestHandler(.userInputRequest(request)) } }
        return await withTaskGroup(of: [UUID].self) { group in
            group.addTask {
                var found: [UUID] = []
                for await value in stream {
                    found.append(value.id)
                    if found.count == requests.count { break }
                }
                return found
            }
            group.addTask { try? await Task.sleep(for: .seconds(2)); return [] }
            let result = await group.next() ?? []
            group.cancelAll()
            return result
        }
    }
    var otherTurn = questionRequest
    otherTurn.turnId = "turn-2"
    let brokers = (0..<4).map { _ in ChatApprovalBroker() }

    let stable = try #require(await ids(brokers[0], [questionRequest]).first)
    #expect(await ids(brokers[1], [questionRequest]) == [stable], "別のブローカー（別のホスト）で同じ要求のIDが変わる")
    let other = try #require(await ids(brokers[2], [otherTurn]).first)
    #expect(other != stable)
    // 未回答の同じ要求が重なっても、待ちを上書きしない（後の要求は別のIDになる）。
    let duplicated = await ids(brokers[3], [questionRequest, questionRequest])
    #expect(duplicated.count == 2 && Set(duplicated).count == 2 && duplicated.contains(stable))

    for broker in brokers { await broker.cancelAll() }
}
