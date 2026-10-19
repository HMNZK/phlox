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
        #expect(viewModel.presentationState.transcript == .loading)
    }

    @Test("メッセージ取得後は初回ロードを完了してチャットを表示する")
    func messageLoadCompletesInitialLoading() async {
        let viewModel = SessionDetailViewModel(
            session: makeSession(),
            api: MockAPI(messagesOutcome: .success([.agent(id: "m1", text: "完了")]))
        )

        await viewModel.load()

        #expect(!viewModel.isInitialLoading)
        #expect(viewModel.presentationState.transcript == .messages)
        #expect(viewModel.showsChat)
    }

    @Test("構造化チャットのないセッションは既存の空表示へ落ちる")
    func missingMessagesCompleteInitialLoadingWithoutError() async {
        let viewModel = SessionDetailViewModel(
            session: makeSession(),
            api: MockAPI(sessions: [makeSession()], messagesOutcome: .failure(.notFound))
        )

        await viewModel.load()

        #expect(!viewModel.isInitialLoading)
        #expect(viewModel.presentationState.transcript == .empty)
        #expect(!viewModel.showsChat)
        #expect(viewModel.loadError == nil)
    }

    @Test("メッセージ404で一覧にも存在しないセッションは空の会話にしない")
    func deletedSessionIsMissingAndRecoversWhenMessagesReturn() async {
        let api = MockAPI(messagesOutcome: .failure(.notFound))
        let viewModel = SessionDetailViewModel(session: makeSession(), api: api)

        await viewModel.load()

        #expect(viewModel.isSessionMissing)
        #expect(viewModel.loadError == "HTTP 404 · session s1")
        #expect(viewModel.presentationState.transcript == .fetchError)

        await api.setMessagesOutcome(.success([.agent(id: "m1", text: "復帰")]))
        await viewModel.refresh()

        #expect(!viewModel.isSessionMissing)
        #expect(viewModel.loadError == nil)
        #expect(viewModel.chatMessages == [.agent(id: "m1", text: "復帰")])
    }

    @Test("表示済みの会話があっても削除の404を隠さない")
    func deletedSessionAfterLoadIsMissing() async {
        let api = MockAPI(messagesOutcome: .success([.agent(id: "m1", text: "既存")]))
        let viewModel = SessionDetailViewModel(session: makeSession(), api: api)
        await viewModel.load()
        await api.setMessagesOutcome(.failure(.server(status: 404, message: "missing")))

        await viewModel.refresh()

        #expect(viewModel.isSessionMissing)
        #expect(viewModel.chatMessages == [.agent(id: "m1", text: "既存")])
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

    @Test("新規チャットから来た画面では読み込み表示を出さない")
    func newSessionSkipsInitialLoadingIndicator() {
        let viewModel = SessionDetailViewModel(session: makeSession(), api: MockAPI(), isNewSession: true)

        #expect(!viewModel.isInitialLoading)
        #expect(viewModel.presentationState.transcript == .empty)
    }

    @Test("PTY セッションは会話・状態の取得を呼ばない")
    func unsupportedSessionDoesNotFetchConversationOrPoll() async {
        let api = MockAPI()
        let session = Session(
            id: "pty", name: "Terminal", agent: .claudeCode, status: .running,
            backend: "pty", updatedAt: Date(timeIntervalSince1970: 0)
        )
        let viewModel = SessionDetailViewModel(session: session, api: api)

        await viewModel.load()
        await viewModel.refresh()

        #expect(viewModel.presentationState.transcript == .unsupported)
        #expect(viewModel.presentationState.displayState == nil)
        #expect(!viewModel.presentationState.showsInputBar)
        #expect(!viewModel.presentationState.showsUsage)
        #expect(await api.messagesCount == 0)
        #expect(await api.messagesDeltaCount == 0)
        #expect(await api.listSessionsCount == 0)
    }

    @Test("HTTP 失敗は再取得中の詳細として保持する")
    func fetchFailureIncludesHTTPStatus() async {
        let viewModel = SessionDetailViewModel(
            session: makeSession(),
            api: MockAPI(messagesOutcome: .failure(.server(status: 502, message: "gateway")))
        )

        await viewModel.load()

        #expect(viewModel.presentationState.transcript == .fetchError)
        #expect(viewModel.loadError == "メッセージの取得に失敗しました · HTTP 502")
    }

    @Test("通信失敗は説明文でなく技術値を最後に表示する")
    func fetchTransportFailureKeepsTechnicalDetailLast() async {
        let viewModel = SessionDetailViewModel(
            session: makeSession(),
            api: MockAPI(messagesOutcome: .failure(.transport(WrappedError(description: "NSURLError -1005"))))
        )

        await viewModel.load()

        #expect(viewModel.presentationState.transcript == .fetchError)
        #expect(viewModel.loadError == "メッセージの取得に失敗しました · NSURLError -1005")
    }
}
