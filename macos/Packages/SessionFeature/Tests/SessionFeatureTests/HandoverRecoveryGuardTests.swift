import Foundation
import Testing
import AgentDomain
import StructuredChatKit
@testable import SessionFeature

/// 計画的なホスト更新（ADR 0233）の画面側の守り。引き継ぎに失敗した実行は、元の子が生きたまま復旧待ちになる。
/// その状態で送信・設定変更で新しい子を起動してはならない。

/// 引き継ぎに対応するクライアントの最小の代役。各操作の呼び出し回数を数える。
private final class RecordingHandoverClient: HandoverCapableClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation
    private let lock = NSLock()
    private var counts: [String: Int] = [:]
    private let adoptionError: Error?

    init(adoptionError: Error? = nil) {
        var captured: AsyncStream<NormalizedChatEvent>.Continuation!
        events = AsyncStream { captured = $0 }
        continuation = captured
        self.adoptionError = adoptionError
    }

    func count(_ name: String) -> Int { lock.withLock { counts[name, default: 0] } }
    private func bump(_ name: String) { lock.withLock { counts[name, default: 0] += 1 } }

    func start() async throws { bump("start") }
    func turnStart(_ input: [ChatInput]) async throws { bump("turnStart") }
    func resume(sessionRef: String) async throws { bump("resume") }
    func interrupt() async throws {}
    func close() async { bump("close"); continuation.finish() }
    func resetConversation() async { bump("resetConversation") }
    func handoverGateReason() async -> String? { nil }
    func prepareHandover(fence: UUID) async throws -> HandoverPreparation {
        bump("prepareHandover")
        // 本物と同じく、フェンスを`events`へ流す（画面状態が処理し終えると確定点が完成する）。
        continuation.yield(.handoverFence(fence))
        return HandoverPreparation(holder: try Self.holderRecord(), appliedSeq: 3, clientState: Data(), fence: fence)
    }
    func cancelHandover() async { bump("cancelHandover") }
    func commitHandover(confirmedThrough: UInt64) async { bump("commitHandover") }

    private static func holderRecord() throws -> HolderRecord {
        let json = #"{"holderID":"h-g","protocolVersion":1,"holderPID":1,"childPID":2,"socketPath":"/tmp/phx-none/s/h-g.sock","startedAt":"2026-11-12T00:00:00Z","metadata":{}}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(HolderRecord.self, from: Data(json.utf8))
    }
    func completeAdoption() async throws {
        bump("completeAdoption")
        if let adoptionError { throw adoptionError }
    }
}

@MainActor
private func makeViewModel(_ client: RecordingHandoverClient, transcriptStore: (any TranscriptStore)? = nil) -> ChatSessionViewModel {
    ChatSessionViewModel(
        id: SessionID(), agentRef: .builtin(.claudeCode), client: client,
        approvalBroker: ChatApprovalBroker(), workingDirectory: "/tmp/work", transcriptStore: transcriptStore)
}

private actor FailingHandoverTranscriptStore: TranscriptStore {
    func loadTranscript(for sessionID: SessionID) async throws -> [ChatItem] {
        [.agentMessage(id: "saved", text: "conversation", timestamp: .now)]
    }
    func upsertTranscriptItems(_ items: [ChatItem], for sessionID: SessionID) async throws {}
    func replaceTranscript(for sessionID: SessionID, with items: [ChatItem]) async throws {
        throw CocoaError(.fileWriteNoPermission)
    }
}

@Test @MainActor
func failedAdoption_marksRecoveryNeededAndDisablesInput() async throws {
    let client = RecordingHandoverClient(adoptionError: HandoverError.adoptionFailed("holder unreachable"))
    let vm = makeViewModel(client)

    await vm.adoptHandover(threadId: "native-1")

    #expect(vm.isHandoverRecoveryNeeded)
    #expect(!vm.isReadyForInput)
    #expect(await vm.handoverGateReason() != nil)
}

@Test @MainActor
func failedAdoption_rejectsEverySendPathAndNeverTouchesTheClient() async throws {
    let client = RecordingHandoverClient(adoptionError: HandoverError.adoptionFailed("holder unreachable"))
    let vm = makeViewModel(client)
    await vm.adoptHandover(threadId: "native-1")

    var rejected = false
    do { try await vm.sendText("hello", submit: true) } catch is HandoverError { rejected = true }
    #expect(rejected, "復旧待ちのsendTextが拒否されない")
    rejected = false
    do { try await vm.sendTextWithControlImages("hello", submit: true, images: []) } catch is HandoverError { rejected = true }
    #expect(rejected, "復旧待ちのControl API送信が拒否されない")
    rejected = false
    do { try await vm.setModel(model: "m", effort: nil) } catch is HandoverError { rejected = true }
    #expect(rejected, "復旧待ちのモデル変更が拒否されない")
    #expect(await vm.revert(toUserMessageID: "none") == nil)

    // 新しい子を作る呼び出し（送信・再開・開始・リセット）は一度も起きない。
    for name in ["turnStart", "resume", "start", "resetConversation"] {
        #expect(client.count(name) == 0, "\(name) が呼ばれた")
    }
}

@Test @MainActor
func successfulAdoption_leavesInputEnabledAndNotRecoveryNeeded() async throws {
    let client = RecordingHandoverClient()
    let vm = makeViewModel(client)

    await vm.adoptHandover(threadId: "native-1")

    #expect(vm.restoreState == .restored)
    #expect(!vm.isHandoverRecoveryNeeded)
    #expect(vm.isReadyForInput)
    #expect(client.count("completeAdoption") == 1)
}

/// 引き継ぎに対応しない通常のクライアント（PTY以外の、holder経由でないもの）。
private final class PlainClient: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    init() { events = AsyncStream { _ in } }
    func start() async throws {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async {}
}

@Test @MainActor
func clientThatCannotHandOver_isNotAParticipantAndCannotAdoptOrPrepare() async throws {
    let vm = ChatSessionViewModel(
        id: SessionID(), agentRef: .builtin(.claudeCode), client: PlainClient(),
        approvalBroker: ChatApprovalBroker(), workingDirectory: "/tmp/work")

    #expect(!vm.isHandoverParticipant)
    #expect(await vm.handoverGateReason() != nil)
    var rejected = false
    do { _ = try await vm.prepareHandover() } catch HandoverError.notReady { rejected = true }
    #expect(rejected, "非対応のクライアントで確定点を作れてしまう")

    // 採用も、対応していなければ復旧待ちにする（新しい子を作らない）。
    await vm.adoptHandover(threadId: "native-1")
    #expect(vm.isHandoverRecoveryNeeded)
    #expect(vm.restoreState != .restored)
}

@Test @MainActor
func preparedHandover_refusesNewSendsUntilCancelled() async throws {
    let client = RecordingHandoverClient()
    let vm = makeViewModel(client)
    await vm.adoptHandover(threadId: "native-1")
    #expect(vm.isHandoverParticipant)
    #expect(await vm.handoverGateReason() == nil)

    // 確定点の作成中〜コミット後は、新しい送信を未受付にする（受け付けて失う・二重に送ることを避ける）。
    _ = try await vm.prepareHandover(fenceTimeout: .seconds(5))
    var rejected = false
    do { try await vm.sendText("hello", submit: true) } catch HandoverError.notReady { rejected = true }
    #expect(rejected, "確定点の作成後の送信が受け付けられた")
    #expect(client.count("turnStart") == 0)

    // 中止すると、送信できる状態に戻る。
    await vm.cancelHandover()
    #expect(client.count("cancelHandover") == 1)
    try await vm.sendText("hello", submit: true)
    #expect(client.count("turnStart") == 1)
}

@Test @MainActor
func failedTranscriptSave_cancelsHandoverBeforeCommit() async throws {
    let client = RecordingHandoverClient()
    let vm = makeViewModel(client, transcriptStore: FailingHandoverTranscriptStore())
    await vm.adoptHandover(threadId: "native-1")

    await #expect(throws: HandoverError.self) {
        _ = try await vm.prepareHandover()
    }
    #expect(client.count("cancelHandover") == 1)
    #expect(client.count("commitHandover") == 0)
}
