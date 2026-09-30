import Foundation
import Testing
import CodexAppServerKit
@testable import SessionFeature

/// Codex 子エージェントの札の名前は、親が spawn 時に付けたタスク名（agent_path の末尾）を最優先にする。
/// 子の最初の usermessage は親の依頼文を引き継ぐことがあり、それが名前になると親の依頼文が札に出てしまう。
@Suite("Codex サブエージェントの札の名前の優先順")
@MainActor
struct CodexSubAgentNamePriorityTests {
    private static let parentRequest = "ログイン画面を直してテストも通してください。詳細は次のとおり"

    private func source(agentPath: String?) -> ThreadSessionSource {
        var spawn: [String: JSONValue] = ["parent_thread_id": .string("parent-1")]
        if let agentPath { spawn["agent_path"] = .string(agentPath) }
        return .subAgent(.object(["thread_spawn": .object(spawn)]))
    }

    private func turns(userText: String?) -> [TurnSummary] {
        let items = userText.map {
            #"[{"id":"u1","type":"userMessage","text":"\#($0)"}]"#
        } ?? "[]"
        let json = #"[{"id":"turn-1","status":"completed","items":\#(items)}]"#
        return try! JSONDecoder().decode([TurnSummary].self, from: Data(json.utf8))
    }

    private func thread(
        agentPath: String?,
        userText: String? = parentRequest,
        name: String? = nil,
        preview: String = ""
    ) -> ThreadSummary {
        ThreadSummary(
            id: "child-1",
            cliVersion: "0",
            createdAt: 0,
            cwd: "/tmp",
            ephemeral: false,
            modelProvider: "test",
            preview: preview,
            sessionId: "child-1",
            source: source(agentPath: agentPath),
            status: .idle,
            turns: turns(userText: userText),
            updatedAt: 0,
            name: name,
            parentThreadId: "parent-1"
        )
    }

    @Test("agent_path があれば、子の最初の usermessage より優先する")
    func agentPathBeatsFirstUserMessage() {
        let t = thread(agentPath: "root/fix_login", name: "別の名前", preview: "プレビュー")
        #expect(CodexSubAgentPresentation.purpose(for: t) == "fix login")
    }

    @Test("agent_path が無い旧 spawn 方式は、従来どおり usermessage → name → preview の順")
    func withoutAgentPathFallsBackToLegacyOrder() {
        #expect(CodexSubAgentPresentation.purpose(for: thread(agentPath: nil)) == Self.parentRequest)
        #expect(
            CodexSubAgentPresentation.purpose(for: thread(agentPath: nil, userText: nil, name: "名前", preview: "プレビュー"))
                == "名前"
        )
        #expect(
            CodexSubAgentPresentation.purpose(for: thread(agentPath: nil, userText: nil, preview: "プレビュー"))
                == "プレビュー"
        )
    }

    @Test("agent_path の末尾が root（タスク名なし）のときは従来の候補へフォールバックする")
    func rootAgentPathFallsBack() {
        #expect(CodexSubAgentPresentation.purpose(for: thread(agentPath: "root")) == Self.parentRequest)
    }

    @Test("turns の無い一覧の応答でも agent_path の名前が札の description まで届く")
    func agentPathReachesStripDescriptionFromListResponse() {
        let listed = ChatSessionViewModel.codexChild(thread(agentPath: "root/fix_login", userText: nil, name: "親の依頼文"))
        #expect(CodexSubAgentPresentation.ref(for: listed).description == "fix login")
    }

    @Test("あとから turns 付きの read で検証されても、名前は usermessage に上書きされない")
    func validatedReadDoesNotOverwriteTaskName() throws {
        var state = CodexSubAgentState(parentThreadId: "parent-1")
        state.apply(.available(children: [
            ChatSessionViewModel.codexChild(thread(agentPath: "root/fix_login", userText: nil))
        ]))
        state.apply(.validated(child: ChatSessionViewModel.codexChild(thread(agentPath: "root/fix_login"))))

        let child = try #require(state.children.first)
        #expect(CodexSubAgentPresentation.ref(for: child).description == "fix login")
    }

    @Test("一度得たタスク名は、agent_path を省略した後続の validated / available でも失わない")
    func taskNameSurvivesLaterResponsesWithoutAgentPath() throws {
        var state = CodexSubAgentState(parentThreadId: "parent-1")
        state.apply(.available(children: [
            ChatSessionViewModel.codexChild(thread(agentPath: "root/fix_login", userText: nil))
        ]))

        state.apply(.validated(child: ChatSessionViewModel.codexChild(thread(agentPath: nil))))
        #expect(try #require(state.children.first).summary == "fix login")

        state.apply(.available(children: [ChatSessionViewModel.codexChild(thread(agentPath: nil))]))
        #expect(try #require(state.children.first).summary == "fix login")
    }

    @Test("agent_path が後続の応答で別の名前に変わったら新しい名前を採る")
    func newerTaskNameReplacesOlderOne() throws {
        var state = CodexSubAgentState(parentThreadId: "parent-1")
        state.apply(.available(children: [ChatSessionViewModel.codexChild(thread(agentPath: "root/old_name"))]))
        state.apply(.validated(child: ChatSessionViewModel.codexChild(thread(agentPath: "root/new_name"))))
        #expect(try #require(state.children.first).summary == "new name")
    }
}
