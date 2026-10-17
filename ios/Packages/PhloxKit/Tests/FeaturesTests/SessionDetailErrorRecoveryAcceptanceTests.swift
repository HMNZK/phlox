import Foundation
import Testing
import PhloxCore
import Features

/// task-1 受け入れテスト（PM 著・実装役は編集禁止）。
/// 初回の会話取得失敗後、ポーリングで回復したらエラーバナーを消す。
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

    @Test("初回メッセージ取得失敗後、ポーリングの messages 成功（チャット化）でエラーバナーが消える")
    func chatRecoveryClearsLoadError() async {
        let api = MockAPI(messagesOutcome: .failure(.unreachable))
        let vm = SessionDetailViewModel(session: makeSession(), api: api)

        await vm.load()
        #expect(vm.loadError != nil)

        await api.setMessagesOutcome(.success([.agent(id: "m1", text: "こんにちは")]))
        await vm.refresh()

        #expect(vm.loadError == nil, "messages が取れたらエラーバナーを消すべき")
        #expect(vm.chatMessages == [.agent(id: "m1", text: "こんにちは")])
    }
}
