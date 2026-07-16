import XCTest
import PhloxCore
@testable import Features

// E4-3 検証。Repository 購読による状態反映と「あなたの番」フィルタを検証する。
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

    func testAttentionSessionsAreFiltered() async {
        let sessions = [session("s1", attention: false), session("s2", attention: true), session("s3", attention: true)]
        let vm = SessionListViewModel(repository: StubSessionRepository(states: [.loaded(sessions)]))
        await vm.observe(interval: .milliseconds(1))
        XCTAssertEqual(vm.attentionSessions.map(\.id), ["s2", "s3"])
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
        XCTAssertTrue(vm.attentionSessions.isEmpty)
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

    // MARK: - DP-4-2 カンプ②メタ表示

    func testListSubtitleFormatsSessionCountAndHost() async {
        let sessions = [session("s1", attention: false), session("s2", attention: true)]
        let config = InMemoryConnectionConfigStore(ConnectionConfig(host: "100.64.0.1", port: 8765))
        let vm = SessionListViewModel(
            repository: StubSessionRepository(states: [.loaded(sessions)]),
            configStore: config
        )
        await vm.observe(interval: .milliseconds(1))
        XCTAssertEqual(vm.listSubtitle, "2 件 · 100.64.0.1")
    }

    func testListSubtitleUsesFallbackHostWhenConfigMissing() async {
        let sessions = [session("s1", attention: false)]
        let vm = SessionListViewModel(
            repository: StubSessionRepository(states: [.loaded(sessions)]),
            configStore: InMemoryConnectionConfigStore()
        )
        await vm.observe(interval: .milliseconds(1))
        XCTAssertEqual(vm.listSubtitle, "1 件 · \(SessionListViewModel.uiTestFallbackHost)")
    }

    func testAttentionSectionTitleIncludesCount() async {
        let sessions = [
            session("s1", attention: true),
            session("s2", attention: true),
            session("s3", attention: false),
        ]
        let vm = SessionListViewModel(repository: StubSessionRepository(states: [.loaded(sessions)]))
        await vm.observe(interval: .milliseconds(1))
        XCTAssertEqual(vm.attentionSectionTitle, "あなたの番 · 2")
    }

    func testOtherSectionTitleIsCampLabel() {
        XCTAssertEqual(SessionListViewModel.otherSectionTitle, "実行中・その他")
    }

    func testSessionCountIsZeroWhenNotLoaded() async {
        let vm = SessionListViewModel(repository: StubSessionRepository(states: [.loading]))
        await vm.observe(interval: .milliseconds(1))
        XCTAssertEqual(vm.sessionCount, 0)
        XCTAssertEqual(vm.listSubtitle, "0 件 · \(SessionListViewModel.uiTestFallbackHost)")
    }
}
