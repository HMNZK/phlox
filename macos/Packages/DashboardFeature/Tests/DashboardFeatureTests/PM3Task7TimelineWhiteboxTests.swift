import Foundation
import Testing
import AgentDomain
import PTYKit
import TerminalUI
import CodexAppServerKit
@testable import DashboardFeature
@testable import SessionFeature

// task-7 実装役の白箱テスト（自分で追加）。契約の正本は tasks/task-7.md。
// 1) TeamTimelineNodeOrdering.ordered の Dictionary 化が O(n²) へ退行していないことの回帰ガード。
// 2) 「ストリーミング中に signature が毎 tick 変わり続けるか」の実測（コードでの観測）。
//    appServer 経路は ChatSessionViewModel.appendDelta → markTranscriptChanged() が
//    デルタ毎に transcriptRevision を進める（ChatSessionViewModel.swift:1719-1750）。
//    pty 経路は SessionViewModel の出力ループが chunk 毎に lastOutputAt を更新する
//    （SessionViewModel.swift:369-374）。どちらも TeamTimelineSignatureContent の成分に
//    直結するため、ストリーミング中は毎 tick signature が変わり続ける（再構築が走り続ける）。

private struct PM3Task7WhiteboxItem: Equatable {
    let id: SessionID
    let tag: String
}

@Suite(.serialized)
struct PM3Task7TimelineWhiteboxTests {

    // MARK: - O(n) 化の回帰ガード

    @Test
    func ordered_completesWithinBudgetForLargeInput() {
        let n = 20_000
        var items: [PM3Task7WhiteboxItem] = []
        var ids: [SessionID] = []
        items.reserveCapacity(n)
        ids.reserveCapacity(n)
        for i in 0..<n {
            let id = SessionID()
            items.append(PM3Task7WhiteboxItem(id: id, tag: "t\(i)"))
            ids.append(id)
        }
        // 逆順 + 末尾に欠落 id を混ぜた最悪寄りの要求列。
        var requested = Array(ids.reversed())
        requested.append(SessionID())

        let start = Date()
        let result = TeamTimelineNodeOrdering.ordered(ids: requested, items: items, id: \.id)
        let elapsed = Date().timeIntervalSince(start)

        #expect(result.count == n)
        #expect(result.map(\.tag) == items.map(\.tag).reversed())
        // O(n) 実装なら 20,000 要素は十分速い。O(n²) へ退行すると要素数二乗のオーダーになり
        // このバジェットを大きく超える（回帰検出用の緩いガード。厳密な時間保証ではない）。
        #expect(elapsed < 2.0, "20,000 要素の解決に \(elapsed)s かかった。O(n²) への退行を疑う")
    }

    @Test
    func ordered_stillMatchesNaiveOnHeavilyDuplicatedIDs() {
        // 受け入れテストと異なる分布（items 側に大量重複 + ids 側にも大量重複）で
        // Dictionary 化後もセマンティクスが崩れていないことを追加確認する。
        let shared = SessionID()
        var items: [PM3Task7WhiteboxItem] = [
            PM3Task7WhiteboxItem(id: shared, tag: "first"),
        ]
        for i in 0..<50 {
            items.append(PM3Task7WhiteboxItem(id: shared, tag: "dup-\(i)"))
        }
        let other = SessionID()
        items.append(PM3Task7WhiteboxItem(id: other, tag: "other"))

        let requested = [shared, other, shared, SessionID(), shared]
        let naive = requested.compactMap { target in items.first { $0.id == target } }
        let result = TeamTimelineNodeOrdering.ordered(ids: requested, items: items, id: \.id)

        #expect(result == naive)
        #expect(result.map(\.tag) == ["first", "other", "first", "first"])
    }

    // MARK: - ストリーミング中の signature 実測

    private func appServerSignature(sessionID: SessionID, transcriptRevision: Int) -> TeamTimelineSignature {
        TeamTimelineSignature.make(
            selectedSessionID: sessionID,
            sessions: [
                TeamTimelineSignatureSession(
                    id: sessionID,
                    parentSessionID: nil,
                    projectID: nil,
                    launchContext: .interactive,
                    status: .running,
                    name: "Worker",
                    displayName: "Worker",
                    agentDescriptor: AgentRegistry.descriptor(for: .codex),
                    content: .appServer(transcriptRevision: transcriptRevision)
                ),
            ]
        )
    }

    /// 実測: appServer セッションで delta イベントが連続するたびに transcriptRevision が
    /// 進み、それを反映した signature も毎回変わる（= 350ms tick のたびに毎回再構築対象になる）。
    @Test @MainActor
    func appServerSignatureChangesOnEveryStreamingDelta() async throws {
        let transport = ScriptedAppServerTransport()
        let broker = ChatApprovalBroker()
        let client = CodexAppServerClient(transport: transport, serverRequestHandler: broker.serverRequestHandler)
        let sessionID = SessionID()
        let vm = ChatSessionViewModel(
            id: sessionID,
            client: CodexStructuredAgentClient(client: client),
            approvalBroker: broker,
            workingDirectory: "/tmp/work",
            transcriptStore: RecordingTranscriptStore()
        )
        try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
        try await vm.sendText("質問", submit: true)

        let sig0 = appServerSignature(sessionID: sessionID, transcriptRevision: vm.transcriptRevision)

        transport.receive("""
        {"jsonrpc":"2.0","method":"item/agentMessage/delta","params":{"threadId":"thread-1","turnId":"turn-1","itemId":"agent-1","delta":"a"}}
        """)
        try await waitUntil { vm.transcript.contains { if case .agentMessage("agent-1", "a", _) = $0 { true } else { false } } }
        let sig1 = appServerSignature(sessionID: sessionID, transcriptRevision: vm.transcriptRevision)

        transport.receive("""
        {"jsonrpc":"2.0","method":"item/agentMessage/delta","params":{"threadId":"thread-1","turnId":"turn-1","itemId":"agent-1","delta":"b"}}
        """)
        try await waitUntil { vm.transcript.contains { if case .agentMessage("agent-1", "ab", _) = $0 { true } else { false } } }
        let sig2 = appServerSignature(sessionID: sessionID, transcriptRevision: vm.transcriptRevision)

        #expect(sig0 != sig1, "1件目の delta で signature が変わらない＝再構築が起きない")
        #expect(sig1 != sig2, "2件目の delta でも signature が変わり続ける＝毎 tick 再構築対象になる実測")
    }

    /// 実測: pty セッションでも出力チャンクが届くたびに lastOutputAt が更新され、
    /// それを反映した signature も毎回変わる（appServer と同じく毎 tick 再構築対象）。
    @Test @MainActor
    func ptySignatureChangesOnEveryOutputChunk() async throws {
        let sessionID = SessionID()
        let ptyManager = MockPTYManager()
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let spawnRequest = SessionViewModel.SpawnRequest(
            command: "/usr/local/bin/codex",
            args: [],
            env: [:],
            workingDirectory: "/tmp/workspace",
            kind: .codex,
            statusBootstrap: .idleOnSpawnComplete
        )
        let vm = SessionViewModel(
            id: sessionID,
            ptyManager: ptyManager,
            hookEvents: hookStream,
            terminalCoordinator: TerminalCoordinator(),
            spawnRequest: spawnRequest
        )
        await vm.start()
        await vm.spawnEager()
        try await waitUntil { ptyManager.spawnCalls.count == 1 }

        func signature() -> TeamTimelineSignature {
            TeamTimelineSignature.make(
                selectedSessionID: sessionID,
                sessions: [
                    TeamTimelineSignatureSession(
                        id: sessionID,
                        parentSessionID: nil,
                        projectID: nil,
                        launchContext: .interactive,
                        status: .running,
                        name: "Worker",
                        displayName: "Worker",
                        agentDescriptor: AgentRegistry.descriptor(for: .codex),
                        content: .pty(lastOutputAt: vm.lastOutputAt)
                    ),
                ]
            )
        }

        let sig0 = signature()

        ptyManager.emitOutput(for: sessionID, data: Data("chunk-1\n".utf8))
        try await waitUntil { vm.hasProducedOutput }
        let afterFirstChunk = vm.lastOutputAt
        let sig1 = signature()

        try await Task.sleep(nanoseconds: 5_000_000)
        ptyManager.emitOutput(for: sessionID, data: Data("chunk-2\n".utf8))
        try await waitUntil { vm.lastOutputAt != afterFirstChunk }
        let sig2 = signature()

        #expect(sig0 != sig1, "1件目の出力 chunk で signature が変わらない＝再構築が起きない")
        #expect(sig1 != sig2, "2件目の出力 chunk でも signature が変わり続ける＝毎 tick 再構築対象になる実測")
    }
}
