import XCTest
import PhloxCore
@testable import Features

// Repository 購読、プロジェクト順、プル更新の補助取得を検証する。
@MainActor
final class SessionListViewModelTests: XCTestCase {

    private func session(_ id: String, attention: Bool) -> Session {
        Session(id: id, name: id, agent: .claudeCode,
                status: attention ? .awaitingApproval(prompt: "p") : .running,
                subtitle: "", updatedAt: Date(timeIntervalSince1970: 0))
    }

    func testLoadedStateReflectsSessions() async {
        let sessions = [session("s1", attention: false), session("s2", attention: true)]
        let vm = SessionListViewModel(repository: StubSessionRepository(states: [.loaded(sessions)]))
        await vm.observe(interval: .milliseconds(1))
        XCTAssertEqual(vm.allSessions.map(\.id), ["s1", "s2"])
    }

    func testProjectionSeparatesAttentionFromProjectRows() async {
        let sessions = [session("s1", attention: false), session("s2", attention: true), session("s3", attention: true)]
        let vm = SessionListViewModel(repository: StubSessionRepository(states: [.loaded(sessions)]))
        await vm.observe(interval: .milliseconds(1))
        XCTAssertEqual(vm.projection.attentionSessions.map(\.id), ["s2", "s3"])
        XCTAssertEqual(vm.projection.otherGroup?.roots.map(\.id), ["s1"])
    }

    func testOfflineState() async {
        let vm = SessionListViewModel(repository: StubSessionRepository(states: [.offline]))
        await vm.observe(interval: .milliseconds(1))
        XCTAssertEqual(vm.state, .offline)
    }

    func testLastFetchedAtPreservedAfterOffline() async {
        let sessions = [
            Session(id: "1", name: "R", agent: .claudeCode, status: .running, subtitle: "", updatedAt: Date()),
        ]
        let vm = SessionListViewModel(repository: StubSessionRepository(states: [.loaded(sessions), .offline]))
        await vm.observe(interval: .milliseconds(1))
        XCTAssertEqual(vm.state, .offline)
        XCTAssertNotNil(vm.lastFetchedAt)
        XCTAssertTrue(vm.allSessions.isEmpty)
        XCTAssertTrue(vm.projection.attentionSessions.isEmpty)
    }

    func testEmptyState() async {
        let vm = SessionListViewModel(repository: StubSessionRepository(states: [.empty]))
        await vm.observe(interval: .milliseconds(1))
        XCTAssertEqual(vm.state, .empty)
    }

    // バックグラウンド復帰時の再購読で state が一時的に .offline/.loading になっても、
    // 詳細画面が「セッションが見つかりません」へ転落しないよう、直近取得分から id 解決できること。
    func testSessionLookupSurvivesTransientNonLoadedState() async {
        let sessions = [session("s1", attention: false)]
        let vm = SessionListViewModel(repository: StubSessionRepository(states: [.loaded(sessions), .offline]))
        await vm.observe(interval: .milliseconds(1))
        XCTAssertEqual(vm.state, .offline)
        XCTAssertTrue(vm.allSessions.isEmpty)
        XCTAssertEqual(vm.session(id: "s1")?.id, "s1", "直近取得分から解決できる")
        XCTAssertNil(vm.session(id: "missing"))
    }

    func testErrorState() async {
        let vm = SessionListViewModel(repository: StubSessionRepository(states: [.error(.unauthorized)]))
        await vm.observe(interval: .milliseconds(1))
        XCTAssertEqual(vm.state, .error(.unauthorized))
    }

    func testTransitionsThroughMultipleStates() async {
        let sessions = [session("s1", attention: false)]
        let vm = SessionListViewModel(repository: StubSessionRepository(states: [.loading, .loaded(sessions)]))
        await vm.observe(interval: .milliseconds(1))
        XCTAssertEqual(vm.state, .loaded(sessions))
    }

    func testConnectionEndpointUsesStoredHostAndPort() {
        let config = InMemoryConnectionConfigStore(ConnectionConfig(host: "100.64.0.1", port: 8765))
        let vm = SessionListViewModel(
            repository: StubSessionRepository(states: [.loading]),
            configStore: config
        )
        XCTAssertEqual(vm.connectionEndpoint, "100.64.0.1:8765")
    }

    func testConnectionEndpointUsesFallbackWhenConfigIsMissing() {
        let vm = SessionListViewModel(
            repository: StubSessionRepository(states: [.loading]),
            configStore: InMemoryConnectionConfigStore()
        )
        XCTAssertEqual(vm.connectionEndpoint, "\(SessionListViewModel.uiTestFallbackHost):8765")
    }

    func testProjectsResponseOrdersTheViewModelProjection() async {
        let sessions = [
            Session(id: "a", name: "A", agent: .claudeCode, status: .running, projectId: "a", projectName: "A", updatedAt: Date(timeIntervalSince1970: 0)),
            Session(id: "b", name: "B", agent: .claudeCode, status: .running, projectId: "b", projectName: "B", updatedAt: Date(timeIntervalSince1970: 0)),
        ]
        let api = MockAPI()
        await api.setProjectsOutcome(.success([
            ProjectSummary(id: "b", name: "B"),
            ProjectSummary(id: "a", name: "A"),
        ]))
        let vm = SessionListViewModel(repository: StubSessionRepository(states: [.loaded(sessions)]), api: api)
        await vm.observe(interval: .milliseconds(1))
        XCTAssertEqual(vm.projection.projectGroups.map(\.id), ["id:b", "id:a"])
    }

    func testPullRefreshAlsoReloadsProjectsAndUsage() async {
        let api = MockAPI()
        await api.setProjectsOutcome(.success([ProjectSummary(id: "p", name: "P")]))
        let vm = SessionListViewModel(repository: StubSessionRepository(states: [.loaded([session("s1", attention: false)])]), api: api)

        await vm.refresh()

        let projectsCount = await api.projectsCount
        let usageCount = await api.cliUsageCount
        XCTAssertEqual(projectsCount, 1)
        XCTAssertEqual(usageCount, 1)
        XCTAssertEqual(vm.cliUsage, [])
    }
}
