import Foundation
import Testing
import PhloxCore
import Features

/// 凍結受け入れテスト（PM 著・実装役はアサーション/本体の編集禁止）。
/// バグ: プロジェクト一覧「+ セッションを追加」→ 下書き画面（placeholder が status:.running）で、
/// まだ spawn していない（isAwaitingInitialSpawn）のに入力バーが送信でなく停止ボタン（赤■）を出し、
/// 最初の1通を送れず操作不能になっていた。
/// 観測可能な振る舞いを公開プロパティ `showsStopButton` で凍結する（View レンダリングには依存しない）:
///  - 下書き未 spawn 中は placeholder が .running でも停止ボタンを出さない（＝送信ボタン）。
///  - 実 running セッション（非ドラフト）では従来どおり停止ボタンを出す。
///  - idle・interrupt 非対応（canInterrupt=false）では停止ボタンを出さない。
@MainActor
struct DraftComposeSendButtonAcceptanceTests {
    private let draft = SessionComposeDraft(project: "phlox")

    /// 下書き画面の placeholder を production（DraftSessionComposeDestination）と同型で作る。
    private func makeDraftPlaceholderSession() -> Session {
        Session(
            id: "draft-compose",
            name: "phlox",
            agent: .claudeCode,
            status: .running,
            subtitle: "phlox",
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func makeSession(status: SessionStatus) -> Session {
        Session(
            id: "s1", name: "Rose", agent: .claudeCode, status: status,
            subtitle: "proj", updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    @Test("下書き未 spawn（placeholder が .running）では停止ボタンを出さない＝送信ボタンを出す")
    func draftAwaitingInitialSpawnShowsSendNotStop() async {
        let api = MockAPI()
        let vm = SessionDetailViewModel(session: makeDraftPlaceholderSession(), api: api)

        await vm.prepareDraft(draft)

        #expect(vm.isAwaitingInitialSpawn, "下書き未 spawn 状態であること（前提）")
        #expect(vm.showsStopButton == false, "下書き中は placeholder が .running でも送信ボタンを出す")
    }

    @Test("実 running セッション（非ドラフト）では停止ボタンを出す")
    func realRunningSessionShowsStop() {
        let api = MockAPI()
        let vm = SessionDetailViewModel(session: makeSession(status: .running), api: api)

        #expect(vm.isAwaitingInitialSpawn == false)
        #expect(vm.showsStopButton == true, "非ドラフトの running では従来どおり停止ボタン")
    }

    @Test("idle セッションでは停止ボタンを出さない")
    func idleSessionDoesNotShowStop() {
        let api = MockAPI()
        let vm = SessionDetailViewModel(session: makeSession(status: .idle), api: api)

        #expect(vm.showsStopButton == false)
    }

    @Test("interrupt 非対応（409 で canInterrupt=false）では running でも停止ボタンを出さない")
    func runningButNotInterruptibleDoesNotShowStop() async {
        let api = MockAPI()
        await api.setInterruptOutcome(.failure(.server(status: 409, message: "interrupt 非対応")))
        let vm = SessionDetailViewModel(session: makeSession(status: .running), api: api)

        await vm.stop() // 409 → canInterrupt = false

        #expect(vm.canInterrupt == false, "前提: 409 で停止 UI が無効化される")
        #expect(vm.showsStopButton == false, "停止できない running では停止ボタンを出さない")
    }
}
