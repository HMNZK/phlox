import Foundation
import Testing
import PhloxCore
import Features

/// task-1 受け入れテスト（PM 著・実装役は編集禁止）。
/// レビュー #1: 初回ロード失敗で loadError がセットされた後、ポーリング（refresh）が
/// 回復したらエラーバナーを消す（loadError = nil）。
/// acceptance_tests のアサーションは変更禁止。ただしテストハーネスの欠陥を発見した場合は、
/// PM に報告し承認を得たうえでハーネス部分に限り修理してよい。
@MainActor
struct SessionDetailErrorRecoveryAcceptanceTests {
    private func makeSession() -> Session {
        Session(
            id: "s1", name: "Rose", agent: .claudeCode, status: .running,
            subtitle: "proj", updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    @Test("初回 output 失敗後、ポーリングの output 成功でエラーバナーが消える")
    func terminalRecoveryClearsLoadError() async {
        let api = MockAPI(
            outputOutcome: .failure(.unreachable),
            messagesOutcome: .success([])
        )
        let vm = SessionDetailViewModel(session: makeSession(), api: api)

        await vm.load()
        #expect(vm.loadError != nil, "初回失敗でエラーバナーが出る前提")

        await api.setOutputOutcome(.success("recovered output"))
        await vm.refresh()

        #expect(vm.loadError == nil, "output 取得が回復したらエラーバナーを消すべき")
        #expect(vm.outputText == "recovered output")
    }

    @Test("初回 output 失敗後、ポーリングの messages 成功（チャット化）でもエラーバナーが消える")
    func chatRecoveryClearsLoadError() async {
        let api = MockAPI(
            outputOutcome: .failure(.unreachable),
            messagesOutcome: .success([])
        )
        let vm = SessionDetailViewModel(session: makeSession(), api: api)

        await vm.load()
        #expect(vm.loadError != nil)

        await api.setMessagesOutcome(.success([.agent(id: "m1", text: "こんにちは")]))
        await vm.refresh()

        #expect(vm.loadError == nil, "messages が取れたらエラーバナーを消すべき")
        #expect(vm.chatMessages == [.agent(id: "m1", text: "こんにちは")])
    }
}
