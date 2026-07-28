import Foundation
import Testing
import AgentDomain
@testable import DashboardFeature
@testable import SessionFeature

/// 凍結受け入れテスト（PM 著・実装役は編集禁止。ハーネス欠陥を見つけた場合のみ PM 承認の上で修理可）。
///
/// 契約（ADR 0137 の runningBreakdown への波及・task-2）: 実行中セッションの計数
/// `DashboardViewModel.runningBreakdown` は、生 `status` ではなく表示用の実効状態
/// `displayStatus` を数える。すなわち「メインターン完了で status は idle でも、背景
/// タスク/サブエージェントが動いている（displayStatus == .running）セッション」は
/// 実行中として数える。純粋な idle（displayStatus == .idle）は数えない。
@Suite("runningBreakdown counts displayStatus (frozen)")
struct RunningBreakdownDisplayStatusAcceptanceTests {
    private func projectID() -> ProjectID {
        ProjectID(rawValue: UUID(uuid: (
            9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 9
        )))
    }

    private func sessionID(_ value: UInt8) -> SessionID {
        SessionID(rawValue: UUID(uuid: (
            value, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        )))
    }

    private func input(
        _ value: UInt8,
        status: SessionStatus,
        displayStatus: SessionStatus?
    ) -> SessionTreeInput {
        SessionTreeInput(
            id: sessionID(value),
            parentSessionID: nil,
            projectID: projectID(),
            launchContext: .interactive,
            status: status,
            name: "session-\(value)",
            agentRef: .builtin(.claudeCode),
            displayStatus: displayStatus
        )
    }

    @Test("idle でも displayStatus == .running なら実行中として数える（desync の核）")
    func idleButProcessingIsCounted() {
        let node = input(1, status: .idle, displayStatus: .running)
        let breakdown = DashboardViewModel.runningBreakdown(in: projectID(), from: [node])
        #expect(breakdown.visible == 1)
        #expect(breakdown.total == 1)
    }

    @Test("純粋な idle（displayStatus == .idle）は数えない")
    func pureIdleIsNotCounted() {
        let node = input(2, status: .idle, displayStatus: .idle)
        let breakdown = DashboardViewModel.runningBreakdown(in: projectID(), from: [node])
        #expect(breakdown.total == 0)
    }

    @Test("生 status == .running は従来どおり数える（回帰ガード）")
    func rawRunningStillCounted() {
        let node = input(3, status: .running, displayStatus: nil)
        let breakdown = DashboardViewModel.runningBreakdown(in: projectID(), from: [node])
        #expect(breakdown.visible == 1)
        #expect(breakdown.total == 1)
    }
}
