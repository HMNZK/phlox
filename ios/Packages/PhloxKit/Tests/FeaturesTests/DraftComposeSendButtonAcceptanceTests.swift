import Foundation
import Testing
import PhloxCore
import Features

/// 実セッションの停止ボタン条件を `showsStopButton` で固定する。
@MainActor
struct SessionDetailStopButtonAcceptanceTests {
    private func makeSession(status: SessionStatus) -> Session {
        Session(
            id: "s1", name: "Rose", agent: .claudeCode, status: status,
            subtitle: "proj", updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    @Test("実 running セッション（非ドラフト）では停止ボタンを出す")
    func realRunningSessionShowsStop() {
        let api = MockAPI()
        let vm = SessionDetailViewModel(session: makeSession(status: .running), api: api)

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
