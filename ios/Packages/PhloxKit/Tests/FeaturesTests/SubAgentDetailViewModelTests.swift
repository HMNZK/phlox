import XCTest
import PhloxCore
@testable import Features

@MainActor
final class SubAgentDetailViewModelTests: XCTestCase {

    private func session() -> Session {
        Session(
            id: "s1", name: "Rose", agent: .claudeCode, status: .running,
            subtitle: "", updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    func testLoadReflectsSubAgentMessages() async {
        let api = MockAPI()
        let messages: [ChatMessage] = [.agent(id: "sm1", text: "サブ回答")]
        await api.setSubAgentMessagesOutcome(.success(messages))
        let vm = SubAgentDetailViewModel(session: session(), subAgentID: "sa1", api: api)

        await vm.load()

        XCTAssertEqual(vm.chatMessages, messages)
        XCTAssertNil(vm.loadError)
    }

    func testPollingStopsWhenTaskCancelled() async throws {
        let api = MockAPI()
        await api.setSubAgentMessagesOutcome(.success([.agent(id: "m1", text: "hi")]))
        let vm = SubAgentDetailViewModel(session: session(), subAgentID: "sa1", api: api)

        let task = Task { await vm.startPolling(interval: .milliseconds(50)) }

        // ポーリングが実際に取得したことを、固定 sleep でなく取得回数の到達で決定的に待つ
        // （wall-clock 依存の境界レースを避ける）。load + poll 少なくとも計2回。
        try await pollUntil(timeout: .seconds(2)) { await api.subAgentMessagesLog.count >= 2 }
        let countBeforeCancel = await api.subAgentMessagesLog.count
        XCTAssertGreaterThanOrEqual(countBeforeCancel, 2)

        // キャンセルし、ポーリングループが完全に停止する（startPolling が return する）まで待つ。
        // 停止後は追加取得が起こり得ないため、以降の回数が不変であることを決定的に検証できる。
        task.cancel()
        await task.value
        let countAfterStop = await api.subAgentMessagesLog.count

        // 停止後に十分待っても取得が増えない（画面離脱相当のキャンセル後は追加取得しない）。
        try await Task.sleep(for: .milliseconds(200))
        let countAfterWait = await api.subAgentMessagesLog.count
        XCTAssertEqual(countAfterWait, countAfterStop, "画面離脱相当のキャンセル後は追加取得しない")
    }

    /// 条件が真になるまで短間隔で待つ決定的ヘルパー（wall-clock 固定 sleep の境界レースを避ける）。
    private func pollUntil(
        timeout: Duration,
        interval: Duration = .milliseconds(10),
        _ condition: () async -> Bool
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: interval)
        }
        if await condition() { return }
        XCTFail("条件が \(timeout) 以内に成立しませんでした")
    }

    func testRefreshKeepsMessagesOnTransientFailure() async {
        let api = MockAPI()
        await api.setSubAgentMessagesOutcome(.success([.agent(id: "m1", text: "hi")]))
        let vm = SubAgentDetailViewModel(session: session(), subAgentID: "sa1", api: api)
        await vm.load()

        await api.setSubAgentMessagesOutcome(.failure(.unreachable))
        await vm.refresh()

        XCTAssertEqual(vm.chatMessages.map(\.id), ["m1"])
    }
}
