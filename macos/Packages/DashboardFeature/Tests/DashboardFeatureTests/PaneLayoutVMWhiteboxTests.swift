// task-3 白箱テスト（実装役著）。自分が書いたコード経路の細部を検証する。
// 受け入れテスト・契約テストとは別に、handlePaneLayoutAction の未知セッションガードなど
// 実装内部の分岐を直接カバーする。

import Foundation
import Testing
import AgentDomain
@testable import DashboardFeature
@testable import SessionFeature

@Suite("PaneLayout VM whitebox (task-3)")
struct PaneLayoutVMWhiteboxTests {

    private func sid(_ n: Int) -> SessionID {
        SessionID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", n))")!)
    }

    @MainActor
    private func makeDashboardWithSessions(
        _ workspaceURL: URL,
        count: Int
    ) async throws -> (DashboardViewModel, [SessionID]) {
        let projectURL = workspaceURL.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let dashboard = DashboardViewModel(
            environment: makeTestEnvironment(
                pty: MockPTYManager(),
                hookStream: hookStream,
                workspaceDirectory: workspaceURL
            )
        )
        await dashboard.start()
        let projectID = try #require(dashboard.addProject(name: "Project", directoryPath: projectURL.path))
        var ids: [SessionID] = []
        for _ in 0..<count {
            ids.append(try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectID))
        }
        return (dashboard, ids)
    }

    // insertBySplitting: session が実在しなければ target が実在していても何も変えない
    // （`PaneTree.inserting` 自体は target さえ見つかれば未知の session でも葉を作れてしまうため、
    // VM 側で sessionNodeIndex を見て弾いている。この分岐は受け入れテストの
    // handlePaneLayoutAction_unknownTargetIsNoOp でも間接的に踏むが、ここでは単独で確認する）。
    @Test @MainActor func insertBySplitting_withUnknownSession_isNoOp() async throws {
        let ws = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(ws) }
        let (dashboard, ids) = try await makeDashboardWithSessions(ws, count: 2)

        let before = dashboard.paneLayout
        dashboard.handlePaneLayoutAction(
            .insertBySplitting(session: sid(999), target: ids[0], edge: .trailing)
        )

        #expect(dashboard.paneLayout == before, "未知のセッションを差し込まない")
        #expect(!dashboard.paneLayout.sessions.contains(sid(999)))
    }

    // 同一操作を2回連続で発行しても、2回目は状態が同じなら再永続化しない
    // （`updated != paneLayout` ガードの確認。副作用の直接観測は難しいので、
    // 少なくとも状態が余計に変化しないことだけを確認する）。
    @Test @MainActor func handlePaneLayoutAction_appliedTwice_isIdempotentAfterFirstChange() async throws {
        let ws = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(ws) }
        let (dashboard, _) = try await makeDashboardWithSessions(ws, count: 2)

        dashboard.handlePaneLayoutAction(.applyPreset(.columns2))
        let afterFirst = dashboard.paneLayout
        dashboard.handlePaneLayoutAction(.applyPreset(.columns2))
        #expect(dashboard.paneLayout == afterFirst)
    }
}
