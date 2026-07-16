import Testing
import Foundation
import PhloxCore
@testable import Features

// task-2 受け入れテスト（PM 著・凍結）。契約: tasks/task-2.md
// 空メッセージの表示除外（visibleMessages）・ライブ status 追従（currentStatus/isAgentWorking）・
// thinkingPreview を検証する。ネットワークは自己完結スタブで即時応答（実 I/O なし）。

private struct StubUnusedError: Error {}

/// 受け入れテスト専用の自己完結スタブ（MockAPI には依存しない＝凍結テストが白箱テストの都合で壊れない）。
private final class AcceptanceStubAPI: PhloxAPI, @unchecked Sendable {
    var sessionsResult: Result<[Session], PhloxError> = .success([])
    var messagesResult: Result<[ChatMessage], PhloxError> = .success([])
    var outputResult: Result<String, PhloxError> = .success("")

    func listSessions() async throws -> [Session] { try sessionsResult.get() }
    func messages(sessionID: String) async throws -> [ChatMessage] { try messagesResult.get() }
    func output(sessionID: String) async throws -> String { try outputResult.get() }

    func spawn(_ request: SpawnRequest) async throws -> Session { throw StubUnusedError() }
    func waitUntilReady(sessionID: String) async throws -> Bool { throw StubUnusedError() }
    func send(_ request: SendRequest) async throws -> SendResult { throw StubUnusedError() }
    func remove(sessionID: String) async throws { throw StubUnusedError() }
    func approvals() async throws -> [Approval] { throw StubUnusedError() }
    func respond(approvalID: String, decision: ApprovalDecision) async throws { throw StubUnusedError() }
}

private func makeSession(_ status: SessionStatus, id: String = "s1") -> Session {
    Session(id: id, name: "Rose", agent: .claudeCode, status: status, subtitle: "", updatedAt: Date(timeIntervalSince1970: 0))
}

@Suite("チャット表示の受け入れ（空メッセージ除外・ライブ status・thinkingPreview）")
@MainActor
struct ChatVisibilityAcceptanceTests {

    // MARK: - visibleMessages（空メッセージ除外）

    @Test("空 text の user/agent/reasoning/subAgent・空 message の error・空の command/fileChange は表示されない")
    func emptyMessagesAreHidden() async {
        let api = AcceptanceStubAPI()
        api.messagesResult = .success([
            .agent(id: "m1", text: ""),
            .reasoning(id: "m2", text: "   \n"),
            .user(id: "m3", text: ""),
            .agent(id: "m4", text: "こんにちは"),
            .command(id: "m5", command: nil, output: ""),
            .command(id: "m6", command: "ls", output: ""),
            .command(id: "m7", command: nil, output: "生出力あり"),
            .fileChange(id: "m8", changes: []),
            .error(id: "m9", message: " "),
            .subAgent(id: "m10", text: ""),
            .subAgent(id: "m11", text: "Sub-agent explore running: 調査"),
        ])
        let vm = SessionDetailViewModel(session: makeSession(.running), api: api)
        await vm.load()

        #expect(vm.visibleMessages == [
            .agent(id: "m4", text: "こんにちは"),
            .command(id: "m6", command: "ls", output: ""),
            .command(id: "m7", command: nil, output: "生出力あり"),
            .subAgent(id: "m11", text: "Sub-agent explore running: 調査"),
        ])
        // 生データは温存（ポーリング差分比較・showsChat 判定を汚染しない）
        #expect(vm.chatMessages.count == 11)
        #expect(vm.showsChat)
    }

    // MARK: - currentStatus / isAgentWorking（ライブ status 追従）

    @Test("初期 currentStatus は snapshot の status と一致する")
    func initialStatusMatchesSnapshot() {
        let vm = SessionDetailViewModel(session: makeSession(.idle), api: AcceptanceStubAPI())
        #expect(vm.currentStatus == .idle)
        #expect(!vm.isAgentWorking)
    }

    @Test("refresh() が listSessions の status を currentStatus に反映し、running でインジケータ条件が立つ")
    func refreshTracksLiveStatus() async {
        let api = AcceptanceStubAPI()
        api.messagesResult = .success([.agent(id: "m1", text: "hi")])
        api.sessionsResult = .success([makeSession(.running)])
        let vm = SessionDetailViewModel(session: makeSession(.idle), api: api)
        await vm.load()
        await vm.refresh()
        #expect(vm.currentStatus == .running)
        #expect(vm.isAgentWorking)

        api.sessionsResult = .success([makeSession(.idle)])
        await vm.refresh()
        #expect(vm.currentStatus == .idle)
        #expect(!vm.isAgentWorking)
    }

    @Test("listSessions 失敗・該当 id 不在では currentStatus を変えない（無音維持）")
    func statusKeptOnFailureOrMissing() async {
        let api = AcceptanceStubAPI()
        api.messagesResult = .success([.agent(id: "m1", text: "hi")])
        api.sessionsResult = .success([makeSession(.running)])
        let vm = SessionDetailViewModel(session: makeSession(.idle), api: api)
        await vm.load()
        await vm.refresh()
        #expect(vm.currentStatus == .running)

        api.sessionsResult = .failure(.unreachable)
        await vm.refresh()
        #expect(vm.currentStatus == .running)

        api.sessionsResult = .success([makeSession(.idle, id: "別セッション")])
        await vm.refresh()
        #expect(vm.currentStatus == .running)
    }

    @Test("ターミナル表示（チャットなし）では running でもインジケータ条件が立たない")
    func noIndicatorInTerminalMode() async {
        let api = AcceptanceStubAPI()
        api.messagesResult = .success([])
        api.outputResult = .success("terminal text")
        api.sessionsResult = .success([makeSession(.running)])
        let vm = SessionDetailViewModel(session: makeSession(.running), api: api)
        await vm.load()
        await vm.refresh()
        #expect(!vm.showsChat)
        #expect(vm.currentStatus == .running)
        #expect(!vm.isAgentWorking)
    }

    // MARK: - thinkingPreview

    @Test("表示末尾が reasoning ならその text が thinkingPreview になる（末尾の空メッセージは無視）")
    func thinkingPreviewFromTrailingReasoning() async {
        let api = AcceptanceStubAPI()
        api.messagesResult = .success([
            .agent(id: "m1", text: "作業します"),
            .reasoning(id: "m2", text: "次の手を検討"),
            .agent(id: "m3", text: ""),
        ])
        let vm = SessionDetailViewModel(session: makeSession(.running), api: api)
        await vm.load()
        #expect(vm.thinkingPreview == "次の手を検討")
    }

    @Test("表示末尾が reasoning 以外なら thinkingPreview は nil")
    func thinkingPreviewNilWhenTrailingIsNotReasoning() async {
        let api = AcceptanceStubAPI()
        api.messagesResult = .success([
            .reasoning(id: "m1", text: "検討"),
            .agent(id: "m2", text: "結論です"),
        ])
        let vm = SessionDetailViewModel(session: makeSession(.running), api: api)
        await vm.load()
        #expect(vm.thinkingPreview == nil)
    }
}
