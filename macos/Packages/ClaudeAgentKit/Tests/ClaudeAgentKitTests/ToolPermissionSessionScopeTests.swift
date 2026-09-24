import Foundation
import Testing
import StructuredChatKit
@testable import ClaudeAgentKit

// 「このセッション中は許可」（05 R6）: CLI の permission_suggestions のうち、許可ルールの追加だけを
// destination: session にして返す。形式は Claude Code 2.1.280 の can_use_tool / updatedPermissions の検証に合わせる。

@Test func sessionPermissionUpdates_keepsAllowRulesAndDirectoriesAsSessionOnly() throws {
    let suggestions: [[String: Any]] = [
        ["type": "addRules", "rules": [["toolName": "Bash", "ruleContent": "git push:*"]], "behavior": "allow", "destination": "localSettings"],
        ["type": "setMode", "mode": "acceptEdits", "destination": "session"],
        ["type": "addRules", "rules": [["toolName": "Bash"]], "behavior": "deny", "destination": "session"],
        ["type": "addDirectories", "directories": ["/tmp"], "destination": "localSettings"],
    ]

    let updates = ClaudeChatClient.sessionPermissionUpdates(from: suggestions)

    #expect(updates.count == 2)
    let rule = try #require(updates.first)
    #expect(rule["type"] as? String == "addRules")
    #expect(rule["behavior"] as? String == "allow")
    #expect(rule["destination"] as? String == "session")
    #expect((rule["rules"] as? [[String: Any]])?.first?["ruleContent"] as? String == "git push:*")
    let directories = try #require(updates.last)
    #expect(directories["type"] as? String == "addDirectories")
    #expect(directories["directories"] as? [String] == ["/tmp"])
    #expect(directories["destination"] as? String == "session")
}

@Test func sessionPermissionUpdates_emptyWithoutSuggestions() {
    #expect(ClaudeChatClient.sessionPermissionUpdates(from: nil).isEmpty)
    #expect(ClaudeChatClient.sessionPermissionUpdates(from: "x").isEmpty)
    #expect(ClaudeChatClient.sessionPermissionUpdates(from: [["type": "addRules", "rules": [], "behavior": "allow"]]).isEmpty)
}

@Test func toolPermissionQuestion_carriesSessionScopeOnlyWhenAvailable() {
    let with = ClaudeChatClient.makeToolPermissionQuestion(toolName: "Bash", input: ["command": "ls"], allowsSessionScope: true)
    let without = ClaudeChatClient.makeToolPermissionQuestion(toolName: "Bash", input: ["command": "ls"])
    #expect(with.permission?.allowsSessionScope == true)
    #expect(without.permission?.allowsSessionScope == nil)
    // 選択肢は凍結どおり Allow / Deny のまま（セッション許可は回答ラベルだけで表す）。
    #expect(with.options.map(\.label) == ["Allow", "Deny"])
}

private final class SessionScopeMockTransport: LineDelimitedTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<Data>.Continuation?
    private var sent: [Data] = []
    let receivedLines: AsyncStream<Data>

    init() {
        var captured: AsyncStream<Data>.Continuation?
        receivedLines = AsyncStream { captured = $0 }
        continuation = captured
    }

    func start() throws {}
    func send(_ data: Data) async throws { lock.withLock { sent.append(data) } }
    func interrupt() async {}
    func close() async { continuation?.finish() }
    func stderrTail() async -> String? { nil }
    func receive(_ line: String) { continuation?.yield(Data(line.utf8)) }

    func controlResponses() -> [[String: Any]] {
        lock.withLock { sent }.compactMap { data in
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["type"] as? String == "control_response" else { return nil }
            return object
        }
    }
}

// 形は Claude Code 2.1.280 が実際に送ってきた can_use_tool（/tmp で touch を頼んだとき）。
private let suggestedBashRequestLine = """
{"type":"control_request","request_id":"permission-s","request":{"subtype":"can_use_tool","tool_name":"Bash","input":{"command":"touch /tmp/x.txt"},"permission_suggestions":[{"type":"addRules","rules":[{"toolName":"Bash","ruleContent":"touch /tmp/x.txt"}],"behavior":"allow","destination":"localSettings"},{"type":"addDirectories","directories":["/tmp"],"destination":"session"},{"type":"setMode","mode":"acceptEdits","destination":"session"}]}}
"""

@Test func allowForSession_sendsSessionRuleInUpdatedPermissions() async throws {
    let transport = SessionScopeMockTransport()
    let client = ClaudeChatClient(environment: [:], transportFactory: { _, _, _, _ in transport })
    await client.start()
    let events = client.events
    let questionTask = Task { () -> ChatUserQuestion? in
        for await event in events {
            if case .userQuestionRequested(_, let questions) = event { return questions.first }
        }
        return nil
    }
    transport.receive(suggestedBashRequestLine)
    let question = try #require(await questionTask.value)
    #expect(question.permission?.allowsSessionScope == true)

    await client.respondToUserQuestion(
        requestId: "permission-s",
        answers: [question.answerKey: [ClaudeChatClient.allowForSessionLabel]]
    )

    let envelope = try #require(transport.controlResponses().first?["response"] as? [String: Any])
    let response = try #require(envelope["response"] as? [String: Any])
    #expect(response["behavior"] as? String == "allow")
    let updates = try #require(response["updatedPermissions"] as? [[String: Any]])
    // ルールと作業ディレクトリの追加の 2 件。モードの切り替えは送らない。
    #expect(updates.map { $0["type"] as? String } == ["addRules", "addDirectories"])
    #expect(updates.allSatisfy { $0["destination"] as? String == "session" })
    #expect((updates.first?["rules"] as? [[String: Any]])?.first?["ruleContent"] as? String == "touch /tmp/x.txt")
    await client.close()
}
