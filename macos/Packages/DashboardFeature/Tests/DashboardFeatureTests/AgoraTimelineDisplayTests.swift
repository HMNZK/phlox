// task-4 白箱テスト: フィルタ適用点・Thinking 行の決定ロジック。
// 契約の正本: tasks/task-4.md

import Foundation
import Testing
import AgentDomain
import SessionFeature
@testable import DashboardFeature

private let t0 = Date(timeIntervalSince1970: 2_000_000)

@Suite("AgoraTimelineDisplay whitebox (task-4)")
struct AgoraTimelineDisplayTests {
    // MARK: - 表示内容フィルタ

    @Test func filteredTranscriptは発言とエラーのみ残す() {
        let input: [ChatItem] = [
            .userMessage(id: "u", text: "議題", timestamp: t0, attachments: []),
            .agentMessage(id: "a", text: "回答", timestamp: t0),
            .reasoning(id: "r", text: "思考", timestamp: t0),
            .commandExecution(id: "c", command: "ls", output: "out", timestamp: t0),
            .error(id: "e", message: "失敗", timestamp: t0),
        ]
        let filtered = AgoraTimelineContentPolicy.filteredTranscript(input)
        #expect(filtered.count == 3)
        #expect(filtered.contains(.userMessage(id: "u", text: "議題", timestamp: t0, attachments: [])))
        #expect(filtered.contains(.agentMessage(id: "a", text: "回答", timestamp: t0)))
        #expect(filtered.contains(.error(id: "e", message: "失敗", timestamp: t0)))
    }

    @Test func filteredTranscriptは入力順を維持する() {
        let input: [ChatItem] = [
            .agentMessage(id: "a1", text: "1", timestamp: t0),
            .reasoning(id: "r", text: "skip", timestamp: t0),
            .agentMessage(id: "a2", text: "2", timestamp: t0),
        ]
        let filtered = AgoraTimelineContentPolicy.filteredTranscript(input)
        #expect(filtered.map(\.id) == ["a1", "a2"])
    }

    // MARK: - Thinking 行の参加者決定

    @Test func thinkingSessionIDsはrunningの参加者だけをsources順で返す() {
        let running = SessionID()
        let idle = SessionID()
        let starting = SessionID()
        let descriptor = AgentRegistry.descriptor(for: .claudeCode)
        let sources = [
            TeamTimelineSource(id: idle, displayName: "Idle", agentDescriptor: descriptor, messages: []),
            TeamTimelineSource(id: running, displayName: "Running", agentDescriptor: descriptor, messages: []),
            TeamTimelineSource(id: starting, displayName: "Starting", agentDescriptor: descriptor, messages: []),
        ]
        let statuses: [SessionID: SessionStatus] = [
            idle: .idle,
            running: .running,
            starting: .starting,
        ]

        #expect(
            AgoraThinkingPolicy.thinkingSessionIDs(sources: sources, statusesByID: statuses) == [running]
        )
    }

    @Test func thinkingSessionIDsはstatus未知の参加者を除外する() {
        let known = SessionID()
        let unknown = SessionID()
        let descriptor = AgentRegistry.descriptor(for: .codex)
        let sources = [
            TeamTimelineSource(id: known, displayName: "Known", agentDescriptor: descriptor, messages: []),
            TeamTimelineSource(id: unknown, displayName: "Unknown", agentDescriptor: descriptor, messages: []),
        ]
        let statuses: [SessionID: SessionStatus] = [known: .running]

        #expect(
            AgoraThinkingPolicy.thinkingSessionIDs(sources: sources, statusesByID: statuses) == [known]
        )
    }

    @Test func agentMessageはアゴラ専用バブル表示対象() {
        let content = TeamTimelineContent.chatItem(
            .agentMessage(id: "a", text: "hello", timestamp: t0)
        )
        #expect(AgentChatRowPolicy.usesAgentMessageBubble(for: content))
        #expect(AgentChatRowPolicy.showsSpeakerHeader(for: content))
    }

    @Test func userMessageはバブル表示対象外でヘッダも出さない() {
        let content = TeamTimelineContent.chatItem(
            .userMessage(id: "u", text: "hello", timestamp: t0, attachments: [])
        )
        #expect(!AgentChatRowPolicy.usesAgentMessageBubble(for: content))
        #expect(!AgentChatRowPolicy.showsSpeakerHeader(for: content))
    }
}
