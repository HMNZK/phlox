import Foundation
import XCTest
import PhloxCore
@testable import Features

/// task-4 受け入れテスト（PM 著・**実装役は編集禁止**）。
///
/// 凍結する契約:
///  1. 取得件数が何件でも、一度に描画対象となるメッセージ数は上限（親画面と同じ 50 件）を超えない。
///  2. 描画対象は**末尾**（最新側）から取る。
///  3. 隠れている件数が観測できる（「以前のメッセージを読む」導線を出せる）。
///  4. 明示操作で窓を広げられる。
///  5. 初回ロードが終わるまでロード中であることが観測できる（白画面を出さないため）。
///  6. 一時的な取得失敗で表示済みメッセージを消さない（既存契約の維持）。
///
/// 実装役が満たすべき公開面（この契約に合わせて実装すること）:
/// ```swift
/// extension SubAgentDetailViewModel {
///     static var visibleMessageLimit: Int { get }      // 50（TranscriptWindow.defaultLimit と同値）
///     var visibleMessages: [ChatMessage] { get }       // 末尾から visibleMessageLimit 件まで
///     var hiddenMessageCount: Int { get }              // 窓の外にある件数
///     var isInitialLoading: Bool { get }               // 初回 load 完了前は true
///     func expandVisibleWindow()                       // 窓を広げる（TranscriptWindow.expandStep 相当）
/// }
/// ```
@MainActor
final class AcceptanceSubAgentTranscriptWindowTests: XCTestCase {

    private func makeSession() -> Session {
        Session(
            id: "s1",
            name: "Rose",
            agent: .claudeCode,
            status: .running,
            subtitle: "proj",
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    /// 稼働中サブエージェント相当の大量メッセージ（1 件あたり 20KB × 300 件）。
    private func heavyMessages(count: Int) -> [ChatMessage] {
        let body = String(repeating: "x", count: 20_000)
        return (0..<count).map { index in
            ChatMessage.command(id: "m\(index)", command: "echo \(index)", output: body)
        }
    }

    /// 契約1・2・3: 300 件返っても描画対象は上限で頭打ちになり、末尾から取る。
    func testVisibleMessagesAreCappedAndTakenFromTail() async {
        let messages = heavyMessages(count: 300)
        let vm = SubAgentDetailViewModel(
            session: makeSession(),
            subAgentID: "sa1",
            api: StubSubAgentAPI(messages: messages)
        )
        await vm.load()

        let limit = SubAgentDetailViewModel.visibleMessageLimit
        XCTAssertEqual(
            vm.visibleMessages.count,
            limit,
            "300 件返っても一度に描画するのは上限 \(limit) 件まで（一括レイアウトでメインスレッドを詰まらせない）"
        )
        XCTAssertEqual(
            vm.visibleMessages.last?.id,
            "m299",
            "描画対象は末尾（最新側）から取る"
        )
        XCTAssertEqual(
            vm.hiddenMessageCount,
            300 - limit,
            "窓の外の件数が観測できる（以前のメッセージを読む導線のため）"
        )
    }

    /// 契約1: 上限は親画面（TranscriptWindow）と同じ 50 件。
    func testVisibleMessageLimitMatchesParentScreen() {
        XCTAssertEqual(
            SubAgentDetailViewModel.visibleMessageLimit,
            50,
            "親画面 TranscriptWindow.defaultLimit と同じ 50 件に揃える"
        )
    }

    /// 契約4: 明示操作で窓を広げられる。
    func testExpandVisibleWindowRevealsMore() async {
        let messages = heavyMessages(count: 300)
        let vm = SubAgentDetailViewModel(
            session: makeSession(),
            subAgentID: "sa1",
            api: StubSubAgentAPI(messages: messages)
        )
        await vm.load()
        let before = vm.visibleMessages.count

        vm.expandVisibleWindow()

        XCTAssertGreaterThan(vm.visibleMessages.count, before, "明示操作で窓が広がる")
        XCTAssertLessThan(vm.hiddenMessageCount, 300 - before, "隠れ件数が減る")
    }

    /// 契約1: 上限未満なら全件を描画する（窓の導入で表示が欠けない）。
    func testFewMessagesAreAllVisible() async {
        let messages = heavyMessages(count: 3)
        let vm = SubAgentDetailViewModel(
            session: makeSession(),
            subAgentID: "sa1",
            api: StubSubAgentAPI(messages: messages)
        )
        await vm.load()

        XCTAssertEqual(vm.visibleMessages.count, 3)
        XCTAssertEqual(vm.hiddenMessageCount, 0)
    }

    /// 契約5: 初回ロード完了前はロード中（白画面ではなくインジケータを出すため）。
    func testInitialLoadingIsTrueBeforeFirstLoad() {
        let vm = SubAgentDetailViewModel(
            session: makeSession(),
            subAgentID: "sa1",
            api: StubSubAgentAPI(messages: [])
        )
        XCTAssertTrue(
            vm.isInitialLoading,
            "初回ロード前はロード中。空の ScrollView（白画面）を出さない"
        )
    }

    /// 契約5: 初回ロード完了後はロード中ではない（空応答でも永久ロードにしない）。
    func testInitialLoadingIsFalseAfterLoadEvenWhenEmpty() async {
        let vm = SubAgentDetailViewModel(
            session: makeSession(),
            subAgentID: "sa1",
            api: StubSubAgentAPI(messages: [])
        )
        await vm.load()
        XCTAssertFalse(
            vm.isInitialLoading,
            "空応答でもロード中のままにしない（永久スピナー禁止）"
        )
    }

    /// 契約6: 一時的な取得失敗で表示済みメッセージを消さない。
    func testTransientFailureKeepsExistingMessages() async {
        let messages = heavyMessages(count: 3)
        let api = StubSubAgentAPI(messages: messages)
        let vm = SubAgentDetailViewModel(session: makeSession(), subAgentID: "sa1", api: api)
        await vm.load()
        XCTAssertEqual(vm.visibleMessages.count, 3, "前提: 取得できている")

        await api.setFailure(.unreachable)
        await vm.refresh()

        XCTAssertEqual(
            vm.visibleMessages.count,
            3,
            "一時的な取得失敗では表示済みメッセージを消さない（既存契約）"
        )
    }

    /// 契約5・4 の View 配線: ViewModel だけ直して View が繋がっていなければ症状は消えない。
    /// ソースを直接読んで配線を凍結する（同パッケージの
    /// `Wave3SessionDetailChromeWhiteboxTests.swift` に前例のある方式）。
    func testSubAgentDetailViewWiresIndicatorAndExpansion() throws {
        let source = try sourceText("Sources/Features/SessionDetail/SubAgentDetailView.swift")
        let compact = source.filter { !$0.isWhitespace }

        XCTAssertTrue(
            compact.contains("isInitialLoading"),
            "ロード中は白画面ではなくインジケータを出すこと。View が isInitialLoading を見ていなければ白画面のまま"
        )
        XCTAssertTrue(
            source.contains("DSConnectingIndicator"),
            "ロード中表示は親画面と同じ DSConnectingIndicator を使うこと"
        )
        XCTAssertTrue(
            compact.contains("hiddenMessageCount"),
            "窓の外の件数を View が使うこと（隠れたメッセージがあることをユーザーに見せる）"
        )
        XCTAssertTrue(
            compact.contains("expandVisibleWindow()"),
            "明示操作で窓を広げる導線を View に出すこと（窓だけ入れて広げられないと以前のメッセージが読めない）"
        )
    }

    // MARK: - helpers

    private func sourceText(_ relativePath: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: packageRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}

// MARK: - stub（受け入れテスト専用。実装役は編集しない）

private actor StubSubAgentAPI: PhloxAPI {
    private var messages: [ChatMessage]
    private var failure: PhloxError?

    init(messages: [ChatMessage]) {
        self.messages = messages
    }

    func setFailure(_ error: PhloxError?) {
        failure = error
    }

    func subAgentMessages(sessionID: String, subAgentID: String) async throws -> [ChatMessage] {
        if let failure { throw failure }
        return messages
    }

    func listSessions() async throws -> [Session] { [] }
    func spawn(_ request: SpawnRequest) async throws -> Session { throw PhloxError.notFound }
    func waitUntilReady(sessionID: String) async throws -> Bool { true }
    func send(_ request: SendRequest) async throws -> SendResult { SendResult(accepted: true) }
    func output(sessionID: String) async throws -> String { "" }
    func messages(sessionID: String) async throws -> [ChatMessage] { [] }
    func remove(sessionID: String) async throws {}
    func approvals() async throws -> [Approval] { [] }
    func respond(approvalID: String, decision: ApprovalDecision) async throws {}
}
