// task-4 の不変受け入れテスト（PM 著・実装役は編集禁止）。
// 契約の正本: tasks/task-4.md — アゴラ討論タイムラインの表示内容・Thinking 表示ポリシー。
// acceptance_tests のアサーションは変更禁止。ただしテストハーネスの欠陥を発見した場合は、
// PM に報告し承認を得たうえでハーネス部分に限り修理してよい。

import Foundation
import Testing
import AgentDomain
import SessionFeature
@testable import DashboardFeature

private let t0 = Date(timeIntervalSince1970: 2_000_000)

@Suite("Acceptance: アゴラタイムラインの表示ポリシー（task-4）")
struct AcceptanceAgoraTimelineDisplayTests {
    // MARK: - 表示内容: 発言（結果）だけを見せる

    @Test func エージェント発言は表示する() {
        #expect(AgoraTimelineContentPolicy.includes(.agentMessage(id: "a", text: "発言", timestamp: t0)))
    }

    @Test func ユーザー発言は表示する() {
        #expect(AgoraTimelineContentPolicy.includes(.userMessage(id: "u", text: "議題", timestamp: t0, attachments: [])))
    }

    @Test func エラーは表示する() {
        #expect(AgoraTimelineContentPolicy.includes(.error(id: "e", message: "spawn 失敗", timestamp: t0)))
    }

    @Test func Reasoningは表示しない() {
        #expect(!AgoraTimelineContentPolicy.includes(.reasoning(id: "r", text: "思考", timestamp: t0)))
    }

    @Test func コマンド実行は表示しない() {
        #expect(!AgoraTimelineContentPolicy.includes(.commandExecution(id: "c", command: "ls", output: "…", timestamp: t0)))
    }

    @Test func ファイル変更は表示しない() {
        #expect(!AgoraTimelineContentPolicy.includes(.fileChange(id: "f", changes: [], timestamp: t0)))
    }

    @Test func サブエージェントマーカーは表示しない() {
        #expect(!AgoraTimelineContentPolicy.includes(.subAgentMarker(id: "s", subagentType: "Explore", description: "調査", status: .running)))
    }

    @Test func ターンコストは表示しない() {
        #expect(!AgoraTimelineContentPolicy.includes(.turnCost(id: "t", costUSD: 0.1, timestamp: t0)))
    }

    // MARK: - Thinking インジケータ: 生成中のみ

    @Test func 生成中はThinkingを表示する() {
        #expect(AgoraThinkingPolicy.showsThinking(status: .running))
    }

    @Test func 待機中はThinkingを表示しない() {
        #expect(!AgoraThinkingPolicy.showsThinking(status: .idle))
    }

    @Test func 起動中はThinkingを表示しない() {
        #expect(!AgoraThinkingPolicy.showsThinking(status: .starting))
    }

    @Test func 承認待ちはThinkingを表示しない() {
        #expect(!AgoraThinkingPolicy.showsThinking(status: .awaitingApproval(prompt: "y/n")))
    }

    @Test func 終了済みはThinkingを表示しない() {
        #expect(!AgoraThinkingPolicy.showsThinking(status: .completed(exitCode: 0)))
        #expect(!AgoraThinkingPolicy.showsThinking(status: .error(message: "died")))
    }
}
