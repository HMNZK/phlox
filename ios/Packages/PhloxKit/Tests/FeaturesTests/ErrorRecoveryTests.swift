import XCTest
import PhloxCore
@testable import Features

// E5-2 検証。主要失敗シナリオ 7 種で「回復導線つきエラー表示」が設計どおり出ることを横断検証する。
@MainActor
final class ErrorRecoveryTests: XCTestCase {

    // 1. オフライン → 一覧が .offline、到達不可画面に「再接続」導線
    func testOfflineShowsReconnectAffordance() async {
        let list = SessionListViewModel(repository: StubSessionRepository(states: [.offline]))
        await list.observe(interval: .milliseconds(1))
        XCTAssertEqual(list.state, .offline)

        let vm = UnreachableViewModel(reachability: .offlineNetwork, onRetry: {})
        XCTAssertTrue(vm.cardMessage.contains("圏外"))
    }

    // 2. Mac スリープ（unreachableHost）→ ping/応答なし旨
    func testUnreachableHostShowsPingHint() {
        let vm = UnreachableViewModel(reachability: .unreachableHost, host: "100.64.0.1", onRetry: {})
        XCTAssertEqual(vm.technicalDetail, "ping 100.64.0.1 → timeout")
    }

    // 3. 401 → 再認証導線（接続設定へ）
    func testUnauthorizedOffersReauthRoute() {
        XCTAssertEqual(PhloxError.unauthorized.presentation.recoveryAction, "接続設定を開く")
    }

    // 4. 429 → spawn カウントダウン: wave-4 で spawn 画面（SpawnViewModel）を廃止したため supersede。
    //    レート制限のカウントダウンは task-4 の compose 導線で再導入時にテストを再確立する
    //    （decision-log.md「task-1 波及テスト処理」）。

    // 5. 500 → サーバエラー + 再試行
    func testServerErrorHasRetry() async {
        let list = SessionListViewModel(repository: StubSessionRepository(states: [.error(.server(status: 500, message: nil))]))
        await list.observe(interval: .milliseconds(1))
        guard case .error(let error) = list.state else { return XCTFail("expected error") }
        XCTAssertEqual(error.presentation.recoveryAction, "再試行")
    }

    // 6. 削除 403 → 「許可が必要です」相当メッセージ
    func testDeleteForbiddenShowsPermissionMessage() async {
        let vm = DeleteConfirmationViewModel(sessionID: "s1", cascadeCount: 0,
                                             api: MockAPI(removeError: .server(status: 403, message: "許可が必要です")),
                                             onDeleted: {})
        await vm.confirmDelete()
        if case .failed(let message) = vm.state {
            XCTAssertTrue(message.contains("許可が必要です"))
        } else {
            XCTFail("expected .failed")
        }
    }

    // 7. send 失敗 → 楽観更新ロールバック（入力復元）
    func testSendFailureRollsBackInput() async {
        let session = Session(id: "s1", name: "R", agent: .claudeCode, status: .running, subtitle: "", updatedAt: Date(timeIntervalSince1970: 0))
        let vm = SessionDetailViewModel(session: session, api: MockAPI(sendOutcome: .failure(.unreachable)))
        vm.inputText = "重要な指示"
        await vm.sendMessage()
        XCTAssertEqual(vm.inputText, "重要な指示")
    }
}
