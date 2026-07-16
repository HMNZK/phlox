import Foundation
import Testing
import AgentDomain
import CodexAppServerKit
@testable import DashboardFeature
@testable import SessionFeature

@Suite struct TeamTimelineStoreTests {
    @Test func inPlaceTranscriptReplacementChangesSignatureViaTranscriptRevision() {
        let sessionID = SessionID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!)
        let before = TeamTimelineSignature.make(
            selectedSessionID: sessionID,
            sessions: [
                session(id: sessionID, transcriptRevision: 1),
            ]
        )
        let after = TeamTimelineSignature.make(
            selectedSessionID: sessionID,
            sessions: [
                session(id: sessionID, transcriptRevision: 2),
            ]
        )

        #expect(before != after)
    }

    /// ステージ2レビュー [MUST] 対応: 実経路（イベントパイプライン）で in-place 置換が
    /// transcriptRevision を進めることを固定する。delta で作られた item と同一 ID の
    /// item/completed は appendOrReplace の in-place 分岐（count 不変・内容変化・
    /// lastOutputAt 非依存）を通る。この分岐から markTranscriptChanged() が消えると red になる。
    @Test @MainActor
    func inPlaceItemReplacementViaEventPipelineBumpsTranscriptRevision() async throws {
        let transport = ScriptedAppServerTransport()
        let broker = ChatApprovalBroker()
        let client = CodexAppServerClient(transport: transport, serverRequestHandler: broker.serverRequestHandler)
        let vm = ChatSessionViewModel(
            id: SessionID(),
            client: CodexStructuredAgentClient(client: client),
            approvalBroker: broker,
            workingDirectory: "/tmp/work",
            transcriptStore: RecordingTranscriptStore()
        )
        try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
        try await vm.sendText("質問", submit: true)
        transport.receive("""
        {"jsonrpc":"2.0","method":"item/agentMessage/delta","params":{"threadId":"thread-1","turnId":"turn-1","itemId":"agent-1","delta":"streamed"}}
        """)
        try await waitUntil {
            vm.transcript.contains { item in
                if case .agentMessage("agent-1", "streamed", _) = item { true } else { false }
            }
        }
        let countBefore = vm.transcript.count
        let revisionBefore = vm.transcriptRevision

        // 同一 itemId の完了イベント → in-place 置換（count は変わらず内容だけ変わる）
        transport.receive("""
        {"jsonrpc":"2.0","method":"item/completed","params":{"threadId":"thread-1","turnId":"turn-1","item":{"id":"agent-1","type":"agent_message","text":"streamed-final"}}}
        """)
        try await waitUntil {
            vm.transcript.contains { item in
                if case .agentMessage("agent-1", "streamed-final", _) = item { true } else { false }
            }
        }

        #expect(vm.transcript.count == countBefore)
        #expect(vm.transcriptRevision > revisionBefore)
    }

    /// ステージ1レビュー提案: セッション削除で signature が必ず変わる（集合の感度）。
    @Test func sessionRemovalChangesSignature() {
        let a = SessionID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!)
        let b = SessionID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!)
        let before = TeamTimelineSignature.make(
            selectedSessionID: a,
            sessions: [session(id: a, transcriptRevision: 1), session(id: b, transcriptRevision: 1)]
        )
        let after = TeamTimelineSignature.make(
            selectedSessionID: a,
            sessions: [session(id: a, transcriptRevision: 1)]
        )
        #expect(before != after)
    }

    /// ステージ1レビュー提案: pty の出力時刻更新で signature が必ず変わる（pty の感度）。
    @Test func ptyOutputTimestampChangesSignature() {
        let id = SessionID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!)
        let before = TeamTimelineSignature.make(
            selectedSessionID: id,
            sessions: [ptySession(id: id, lastOutputAt: Date(timeIntervalSince1970: 10))]
        )
        let after = TeamTimelineSignature.make(
            selectedSessionID: id,
            sessions: [ptySession(id: id, lastOutputAt: Date(timeIntervalSince1970: 11))]
        )
        #expect(before != after)
    }

    private func ptySession(id: SessionID, lastOutputAt: Date?) -> TeamTimelineSignatureSession {
        TeamTimelineSignatureSession(
            id: id,
            parentSessionID: nil,
            projectID: nil,
            launchContext: .interactive,
            status: .running,
            name: "Worker",
            displayName: "Worker",
            agentDescriptor: AgentRegistry.descriptor(for: .codex),
            content: .pty(lastOutputAt: lastOutputAt)
        )
    }

    private func session(
        id: SessionID,
        transcriptRevision: Int
    ) -> TeamTimelineSignatureSession {
        TeamTimelineSignatureSession(
            id: id,
            parentSessionID: nil,
            projectID: nil,
            launchContext: .interactive,
            status: .running,
            name: "Worker",
            displayName: "Worker",
            agentDescriptor: AgentRegistry.descriptor(for: .codex),
            content: .appServer(transcriptRevision: transcriptRevision)
        )
    }
}
