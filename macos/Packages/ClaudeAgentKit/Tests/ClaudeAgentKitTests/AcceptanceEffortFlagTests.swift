import Foundation
import Testing
import StructuredChatKit
@testable import ClaudeAgentKit

// task-22 受け入れテスト（PM 著・実装役は編集禁止）。
// 契約: `updateSettings(model:permissionMode:effort:)` の置換セマンティクスに effort を追加し、
// respawn 引数へ `--effort <low|medium|high|xhigh|max>` を反映する。
// 既存の respawn 引数選択（会話未確立=--session-id / 確立・resume 済み=--resume、ADR 0021）と共存する。

// MARK: - 1. effort 設定が respawn 引数に反映される（未確立 → --session-id と共存）

@Test func effortAppearsInRespawnArgumentsWithSessionId() async throws {
    let recorder = EffortTransportRecorder()
    let sid = "a1b2c3d4-1111-4111-8111-111111111111"
    let client = ClaudeChatClient(
        environment: ["PHLOX_SESSION_ID": sid],
        transportFactory: recorder.makeTransport
    )
    await client.start()
    var iterator = client.events.makeAsyncIterator()

    await client.updateSettings(model: "opus", permissionMode: "bypassPermissions", effort: "low")
    try await client.turnStart([.text("hello")])
    #expect(await iterator.next() == .turnStarted)

    #expect(recorder.starts.count == 2)
    let args = recorder.starts[1].arguments
    #expect(args.contains("--effort"))
    #expect(args.contains("low"))
    #expect(args.contains("--session-id"))
    #expect(!args.contains("--resume"))
    await client.close()
}

// MARK: - 2. 置換セマンティクス: effort=nil で次 respawn から --effort が外れる

@Test func effortNilClearsFlagOnNextRespawn() async throws {
    let recorder = EffortTransportRecorder()
    let sid = "a1b2c3d4-2222-4222-8222-222222222222"
    let client = ClaudeChatClient(
        environment: ["PHLOX_SESSION_ID": sid],
        transportFactory: recorder.makeTransport
    )
    await client.start()
    var iterator = client.events.makeAsyncIterator()

    await client.updateSettings(model: "opus", permissionMode: nil, effort: "xhigh")
    try await client.turnStart([.text("first")])
    #expect(await iterator.next() == .turnStarted)
    #expect(recorder.starts[1].arguments.contains("--effort"))

    recorder.transports[1].receive(
        #"{"type":"result","subtype":"success","session_id":"\#(sid)","is_error":false}"#
    )
    #expect(await iterator.next() == .turnCompleted(nativeSessionId: sid))

    await client.updateSettings(model: "opus", permissionMode: nil, effort: nil)
    try await client.turnStart([.text("second")])
    #expect(await iterator.next() == .turnStarted)

    #expect(recorder.starts.count == 3)
    let args = recorder.starts[2].arguments
    #expect(!args.contains("--effort"))
    #expect(!args.contains("xhigh"))
    // 会話確立後なので --resume 側に載る（既存セマンティクス維持）。
    #expect(args.contains("--resume"))
    await client.close()
}

// MARK: - 3. resume 済みセッションでも effort が --resume と共に載る

@Test func effortAppearsAlongsideResumeAfterCallerResume() async throws {
    let recorder = EffortTransportRecorder()
    let ref = "a1b2c3d4-3333-4333-8333-333333333333"
    let client = ClaudeChatClient(
        environment: [:],
        transportFactory: recorder.makeTransport
    )
    try await client.resume(sessionRef: ref)
    var iterator = client.events.makeAsyncIterator()

    await client.updateSettings(model: "sonnet", permissionMode: "bypassPermissions", effort: "max")
    try await client.turnStart([.text("hi")])
    #expect(await iterator.next() == .turnStarted)

    #expect(recorder.starts.count == 2)
    let args = recorder.starts[1].arguments
    #expect(args.contains("--resume"))
    #expect(args.contains(ref))
    #expect(args.contains("--effort"))
    #expect(args.contains("max"))
    #expect(!args.contains("--session-id"))
    await client.close()
}

// MARK: - 4. effort 未設定なら --effort を一切付けない（後方互換）

@Test func noEffortFlagWhenNeverConfigured() async throws {
    let recorder = EffortTransportRecorder()
    let sid = "a1b2c3d4-4444-4444-8444-444444444444"
    let client = ClaudeChatClient(
        environment: ["PHLOX_SESSION_ID": sid],
        transportFactory: recorder.makeTransport
    )
    await client.start()
    var iterator = client.events.makeAsyncIterator()

    await client.updateSettings(model: "opus", permissionMode: "bypassPermissions")
    try await client.turnStart([.text("hello")])
    #expect(await iterator.next() == .turnStarted)

    #expect(recorder.starts.count == 2)
    #expect(!recorder.starts[0].arguments.contains("--effort"))
    #expect(!recorder.starts[1].arguments.contains("--effort"))
    await client.close()
}

// MARK: - テストダブル（この受け入れファイル内で自己完結）

private struct EffortTransportStart: Sendable {
    var command: String
    var arguments: [String]
    var environment: [String: String]
    var workingDirectory: URL?
}

private final class EffortTransportRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedStarts: [EffortTransportStart] = []
    private var recordedTransports: [EffortMockTransport] = []

    var starts: [EffortTransportStart] {
        lock.lock()
        defer { lock.unlock() }
        return recordedStarts
    }

    var transports: [EffortMockTransport] {
        lock.lock()
        defer { lock.unlock() }
        return recordedTransports
    }

    func makeTransport(
        command: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: URL?
    ) -> any LineDelimitedTransport {
        let transport = EffortMockTransport()
        lock.lock()
        defer { lock.unlock() }
        recordedStarts.append(EffortTransportStart(
            command: command,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory
        ))
        recordedTransports.append(transport)
        return transport
    }
}

private final class EffortMockTransport: LineDelimitedTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<Data>.Continuation?
    private var sent: [Data] = []

    let receivedLines: AsyncStream<Data>

    init() {
        var captured: AsyncStream<Data>.Continuation?
        receivedLines = AsyncStream { continuation in
            captured = continuation
        }
        continuation = captured
    }

    func start() throws {}

    func send(_ data: Data) async throws {
        record(data)
    }

    private func record(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        sent.append(data)
    }

    func interrupt() async {}

    func close() async {
        continuation?.finish()
    }

    func receive(_ line: String) {
        continuation?.yield(Data(line.utf8))
    }
}
