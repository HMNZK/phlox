import XCTest
import PhloxCore
@testable import Features

/// task-3 受け入れテスト（PM 著・**実装役は編集禁止**）。
///
/// 凍結する契約:
///  1. `.error(...)` でも入力欄が有効（＝入力欄が View 階層から消えない）。
///  2. `.completed(...)` でも入力欄が有効。
///  3. `.starting` は従来どおり無効（初回 spawn 待ちの例外経路は別）。
///  4. 対話中ステータス（`.idle` / `.running` / `.awaitingApproval` / `.awaitingUserQuestion`）は従来どおり有効。
///  5. 送信中（`isSending`）は入力を無効化する既存の性質を壊さない。
///
/// 背景: macOS の `ChatSessionViewModel.isReadyForInput` は `.starting` のみ false で
/// `.completed` / `.error` は true。iOS だけがこの非対称で復帰手段を失っていた。
/// 復帰は「送信」で足りる（`ClaudeChatClient.turnStart` が transport 死亡時に自動 respawn する）。
@MainActor
final class AcceptanceErrorInputBarTests: XCTestCase {

    private func session(_ status: SessionStatus) -> Session {
        Session(
            id: "s1",
            name: "Rose",
            agent: .claudeCode,
            status: status,
            subtitle: "",
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    /// 契約1: エラー停止でも入力欄が残る。
    func testInputBarStaysEnabledOnError() {
        let vm = SessionDetailViewModel(session: session(.error(message: "boom")), api: MockAPI())
        XCTAssertTrue(
            vm.inputEnabled,
            "エラー停止（.error）でも入力欄を残す。送信すると macOS 側が会話を保って respawn する"
        )
        XCTAssertTrue(
            vm.isInputBarEnabled,
            "isInputBarEnabled も true（SessionDetailView は これで入力欄セクションを描画する）"
        )
    }

    /// 契約2: 正常終了でも入力欄が残る。
    func testInputBarStaysEnabledOnCompleted() {
        let vm = SessionDetailViewModel(session: session(.completed(exitCode: 0)), api: MockAPI())
        XCTAssertTrue(vm.inputEnabled, "正常終了（.completed）でも入力欄を残す")
        XCTAssertTrue(vm.isInputBarEnabled)

        let failed = SessionDetailViewModel(session: session(.completed(exitCode: 1)), api: MockAPI())
        XCTAssertTrue(failed.inputEnabled, "非ゼロ終了でも入力欄を残す")
    }

    /// 契約3: 起動中は従来どおり無効。
    func testStartingRemainsDisabled() {
        let vm = SessionDetailViewModel(session: session(.starting), api: MockAPI())
        XCTAssertFalse(
            vm.inputEnabled,
            ".starting は従来どおり無効（CLI 起動前で送信が実行されないため）"
        )
    }

    /// 契約4: 対話中ステータスは従来どおり有効。
    func testInteractiveStatusesRemainEnabled() {
        XCTAssertTrue(SessionDetailViewModel(session: session(.idle), api: MockAPI()).inputEnabled)
        XCTAssertTrue(SessionDetailViewModel(session: session(.running), api: MockAPI()).inputEnabled)
        XCTAssertTrue(
            SessionDetailViewModel(session: session(.awaitingApproval(prompt: "p")), api: MockAPI()).inputEnabled
        )
        XCTAssertTrue(
            SessionDetailViewModel(session: session(.awaitingUserQuestion), api: MockAPI()).inputEnabled
        )
    }

    /// 契約5: エラー停止時も「送信中は無効」の既存性質を保つ。
    func testSendingDisablesInputBarEvenOnError() async {
        let vm = SessionDetailViewModel(session: session(.error(message: "boom")), api: MockAPI())
        XCTAssertTrue(vm.isInputBarEnabled, "前提: 送信前は有効")
        XCTAssertEqual(
            vm.inputEnabled && !vm.isSending,
            vm.isInputBarEnabled,
            "isInputBarEnabled は inputEnabled && !isSending の関係を保つ"
        )
    }
}
