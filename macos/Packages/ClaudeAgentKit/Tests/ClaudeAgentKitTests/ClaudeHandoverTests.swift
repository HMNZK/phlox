import Foundation
import Testing
import StructuredChatKit
@testable import ClaudeAgentKit

/// 計画的なホスト更新（ADR 0233）のClaudeクライアント。引き継ぎに失敗した実行は、元の子が生きたまま復旧待ちになる。
/// 送信・再開・リセットで新しい子（2つ目のCLI）を起動してはならない。

/// 何も流さない子の代役。`start`の回数（＝子の起動要求）を`StartRecorder`が数える。
private final class IdleTransport: LineDelimitedTransport, @unchecked Sendable {
    let receivedLines: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation

    init() {
        var captured: AsyncStream<Data>.Continuation!
        receivedLines = AsyncStream { captured = $0 }
        continuation = captured
    }

    func start() throws {}
    func send(_ data: Data) async throws {}
    func interrupt() async {}
    func close() async { continuation.finish() }
}

private final class StartRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var launches: [[String]] = []
    var starts: [[String]] { lock.withLock { launches } }

    func makeTransport(
        command: String, arguments: [String], environment: [String: String], workingDirectory: URL?
    ) -> any LineDelimitedTransport {
        lock.withLock { launches.append(arguments) }
        return IdleTransport()
    }
}

private func unreachableHolder() throws -> HolderTransport {
    let json = #"{"holderID":"h-x","protocolVersion":1,"holderPID":1,"childPID":1,"socketPath":"/tmp/phx-none/s/h-x.sock","startedAt":"2026-11-12T00:00:00Z","metadata":{}}"#
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return HolderTransport(source: .adopt(record: try decoder.decode(HolderRecord.self, from: Data(json.utf8)), fromSeq: 0))
}

private func makeClient(_ recorder: StartRecorder) -> ClaudeChatClient {
    ClaudeChatClient(
        environment: ["PHLOX_SESSION_ID": "11111111-1111-4111-8111-111111111111"],
        transportFactory: recorder.makeTransport)
}

/// 新しい子を作るあらゆる入口を叩く。どれも失敗し、子の起動は一度も要求されない。
private func attemptEveryRespawnPath(_ client: ClaudeChatClient) async {
    await #expect(throws: (any Error).self) { try await client.turnStart([.text("hello")]) }
    await #expect(throws: (any Error).self) { try await client.resume(sessionRef: "native-1") }
    await #expect(throws: (any Error).self) { try await client.start() }
    await client.resetConversation()
}

@Test func turnStartAfterFailedAdoptionNeverSpawns() async throws {
    let recorder = StartRecorder()
    let client = makeClient(recorder)
    // 状態が読めない採用は、子へ接続する前に失敗する。
    await client.prepareAdoption(state: Data("not json".utf8), transport: try unreachableHolder())
    await #expect(throws: HandoverError.self) { try await client.completeAdoption() }

    await attemptEveryRespawnPath(client)

    #expect(recorder.starts.isEmpty, "復旧待ちのクライアントが新しい子を起動した")
}

@Test func turnStartAfterAdoptionThatCannotReachTheHolderNeverSpawns() async throws {
    let recorder = StartRecorder()
    let client = makeClient(recorder)
    let handoverState = await client.makeHandoverState()
    let state = try JSONEncoder().encode(handoverState)
    await client.prepareAdoption(state: state, transport: try unreachableHolder())
    await #expect(throws: HandoverError.self) { try await client.completeAdoption() }

    await attemptEveryRespawnPath(client)

    #expect(recorder.starts.isEmpty)
}

@Test func clientThatWasPreparedForAdoptionButNeverCompletedNeverSpawns() async throws {
    // 画面側が`completeAdoption`へ進む前に失敗した場合（会話ログの復元の失敗など）。
    let recorder = StartRecorder()
    let client = makeClient(recorder)
    await client.prepareAdoption(state: Data(), transport: try unreachableHolder())

    await attemptEveryRespawnPath(client)

    #expect(recorder.starts.isEmpty)
}

@Test func aClientThatWasNotPreparedForAdoptionStillSpawnsNormally() async throws {
    let recorder = StartRecorder()
    let client = makeClient(recorder)

    try await client.start()

    #expect(recorder.starts.count == 1)
    await client.close()
}

// MARK: - 採用時の受信番号の連続性（欠落した行は引き継がない）

/// 子が5行（seq 1〜5）を出し、旧ホストがseq 5まで確認した（holderは破棄済み）状態のholderを作る。
private func holderWithFiveConfirmedLines() async throws -> (holder: ProcessHolder, record: HolderRecord, root: String) {
    let root = "/tmp/phx-cl-" + UUID().uuidString.prefix(8).lowercased()
    let spec = HolderSpawnSpec(
        command: "/bin/sh", arguments: ["-c", "printf 'a\\nb\\nc\\nd\\ne\\n'; exec sleep 30"],
        environment: ProcessInfo.processInfo.environment, workingDirectory: nil, metadata: [:],
        recordDirectory: root + "/r", socketDirectory: root + "/s")
    let holder = ProcessHolder(spec: spec, orphanLinger: 5)
    let record = try holder.start()
    let first = HolderTransport(source: .adopt(record: record, fromSeq: 0))
    try first.start()
    var lines = first.receivedLines.makeAsyncIterator()
    for _ in 0..<5 { _ = await lines.next() }
    first.confirm(through: 5)
    _ = await first.stderrTail()
    first.releaseForHandover()
    return (holder, record, root)
}

@Test func adoptionWithAMissingSequenceRangeFailsAndLeavesTheChildAlone() async throws {
    let (holder, record, root) = try await holderWithFiveConfirmedLines()
    defer {
        kill(record.childPID, SIGKILL)
        try? FileManager.default.removeItem(atPath: root)
        withExtendedLifetime(holder) {}
    }
    let recorder = StartRecorder()
    let client = makeClient(recorder)
    let handoverState = await client.makeHandoverState()
    let transport = HolderTransport(source: .adopt(record: record, fromSeq: 2))
    await client.prepareAdoption(state: try JSONEncoder().encode(handoverState), transport: transport)

    await #expect(throws: HandoverError.self) { try await client.completeAdoption() }

    #expect(kill(record.childPID, 0) == 0)
    #expect(recorder.starts.isEmpty)
    // 手放しただけで確認は送っていない: 続きの番号（5）での採用は連続性の検査を通る。
    let retry = HolderTransport(source: .adopt(record: record, fromSeq: 5))
    try retry.start()
    #expect(retry.adoptionContinuityFault() == nil)
    #expect(retry.attachInfo?.lastSeq == 5)
    retry.releaseForHandover()
}
