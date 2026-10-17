import Foundation
import PhloxCore
import Testing
@testable import Features

@Suite("SessionDetail の初回ロード表示")
@MainActor
struct SessionDetailLoadingWhiteboxTests {
    private func makeSession() -> Session {
        Session(
            id: "s1",
            name: "Rose",
            agent: .claudeCode,
            status: .running,
            subtitle: "",
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    @Test("生成直後は初回ロード中")
    func startsInInitialLoadingState() {
        let viewModel = SessionDetailViewModel(session: makeSession(), api: MockAPI())

        #expect(viewModel.isInitialLoading)
        #expect(viewModel.showsInitialLoadingIndicator)
    }

    @Test("メッセージ取得後は初回ロードを完了してチャットを表示する")
    func messageLoadCompletesInitialLoading() async {
        let viewModel = SessionDetailViewModel(
            session: makeSession(),
            api: MockAPI(messagesOutcome: .success([.agent(id: "m1", text: "完了")]))
        )

        await viewModel.load()

        #expect(!viewModel.isInitialLoading)
        #expect(!viewModel.showsInitialLoadingIndicator)
        #expect(viewModel.showsChat)
    }

    @Test("構造化チャットのないセッションは既存の空表示へ落ちる")
    func missingMessagesCompleteInitialLoadingWithoutError() async {
        let viewModel = SessionDetailViewModel(
            session: makeSession(),
            api: MockAPI(messagesOutcome: .failure(.notFound))
        )

        await viewModel.load()

        #expect(!viewModel.isInitialLoading)
        #expect(!viewModel.showsInitialLoadingIndicator)
        #expect(!viewModel.showsChat)
        #expect(viewModel.loadError == nil)
    }

    @Test("メッセージ取得失敗後も初回ロードを完了する")
    func failureCompletesInitialLoading() async {
        let viewModel = SessionDetailViewModel(
            session: makeSession(),
            api: MockAPI(messagesOutcome: .failure(.unreachable))
        )

        await viewModel.load()

        #expect(!viewModel.isInitialLoading)
        #expect(viewModel.loadError != nil)
    }

    @Test("ポーリング更新では初回ロード中へ戻らない")
    func refreshDoesNotRestoreInitialLoading() async {
        let viewModel = SessionDetailViewModel(
            session: makeSession(),
            api: MockAPI(messagesOutcome: .success([.agent(id: "m1", text: "loaded")]))
        )
        await viewModel.load()

        await viewModel.refresh()

        #expect(!viewModel.isInitialLoading)
    }
}
