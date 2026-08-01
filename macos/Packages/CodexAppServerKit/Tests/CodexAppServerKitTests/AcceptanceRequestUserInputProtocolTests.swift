import Foundation
import Testing
@testable import CodexAppServerKit

/// task-1 受け入れテスト（PM が著す不変の契約。実装役は編集不可）。
/// `item/tool/requestUserInput` を `ServerRequest.userInputRequest` としてデコードできること、
/// デコード不能なら `.unknown` にフォールバックすること、既知3種が不変であることを固定する。
@Suite("Acceptance: item/tool/requestUserInput のデコード（task-1）")
struct AcceptanceRequestUserInputProtocolTests {
    /// ハンドラが受け取った ServerRequest を1件だけ捕まえる箱。
    private actor Captured {
        var request: ServerRequest?
        func set(_ value: ServerRequest) { request = value }
    }

    private func run(rawMessage: String) async -> ServerRequest? {
        let transport = MockTransport()
        let captured = Captured()
        let rpc = JSONRPCClient(transport: transport) { request in
            await captured.set(request)
            return .object([:])
        }
        await rpc.start()
        transport.receive(rawMessage)
        _ = await waitUntil { await captured.request != nil }
        await rpc.close()
        return await captured.request
    }

    @Test("完全な params は userInputRequest としてデコードされ、全フィールドが復元される")
    func decodesFullParams() async throws {
        let request = await run(rawMessage: """
        {"jsonrpc":"2.0","id":11,"method":"item/tool/requestUserInput","params":{\
        "threadId":"thread-1","turnId":"turn-1","itemId":"item-1","autoResolutionMs":30000,\
        "questions":[{"id":"q1","header":"リファクタの目的","question":"何を優先しますか？",\
        "options":[{"label":"可読性","description":"読みやすさを優先"},{"label":"性能","description":"速度を優先"}],\
        "isOther":true,"isSecret":false}]}}
        """)

        guard case .userInputRequest(let value) = request else {
            Issue.record("Expected .userInputRequest, got \(String(describing: request))")
            return
        }
        #expect(value.threadId == "thread-1")
        #expect(value.turnId == "turn-1")
        #expect(value.itemId == "item-1")
        #expect(value.autoResolutionMs == 30000)
        #expect(value.questions.count == 1)

        let question = try #require(value.questions.first)
        #expect(question.id == "q1")
        #expect(question.header == "リファクタの目的")
        #expect(question.question == "何を優先しますか？")
        #expect(question.isOther == true)
        #expect(question.isSecret == false)
        #expect(question.options?.count == 2)
        #expect(question.options?.first?.label == "可読性")
        #expect(question.options?.first?.description == "読みやすさを優先")
    }

    @Test("任意フィールドの省略・null は nil になり、デコードは失敗しない")
    func optionalFieldsTolerateOmissionAndNull() async throws {
        let request = await run(rawMessage: """
        {"jsonrpc":"2.0","id":12,"method":"item/tool/requestUserInput","params":{\
        "threadId":"t","turnId":"u","itemId":"i",\
        "questions":[{"id":"q1","header":"h","question":"自由に答えてください","options":null}]}}
        """)

        guard case .userInputRequest(let value) = request else {
            Issue.record("Expected .userInputRequest, got \(String(describing: request))")
            return
        }
        #expect(value.autoResolutionMs == nil)
        let question = try #require(value.questions.first)
        #expect(question.options == nil)
        // isOther / isSecret は省略時 false 相当（nil でも false でもよいが true にはならない）。
        #expect(question.isOther != true)
        #expect(question.isSecret != true)
    }

    @Test("未知フィールドが増えてもデコードは壊れない（codex 側 EXPERIMENTAL への耐性）")
    func toleratesUnknownFields() async throws {
        let request = await run(rawMessage: """
        {"jsonrpc":"2.0","id":13,"method":"item/tool/requestUserInput","params":{\
        "threadId":"t","turnId":"u","itemId":"i","futureField":"whatever",\
        "questions":[{"id":"q1","header":"h","question":"q","brandNew":123}]}}
        """)

        guard case .userInputRequest = request else {
            Issue.record("Expected .userInputRequest, got \(String(describing: request))")
            return
        }
    }

    @Test("必須フィールドが欠けた params は .unknown へフォールバックする")
    func fallsBackToUnknownWhenRequiredFieldMissing() async throws {
        // questions が無い＝必須欠落。
        let request = await run(rawMessage: """
        {"jsonrpc":"2.0","id":14,"method":"item/tool/requestUserInput","params":{"itemId":"item-1"}}
        """)

        guard case .unknown(let method, _) = request else {
            Issue.record("Expected .unknown, got \(String(describing: request))")
            return
        }
        #expect(method == "item/tool/requestUserInput")
    }

    @Test("ServerRequest.method は userInputRequest に対し正しいメソッド名を返す")
    func methodStringIsStable() {
        let value = ToolRequestUserInputRequest(
            threadId: "t",
            turnId: "u",
            itemId: "i",
            questions: []
        )
        #expect(ServerRequest.userInputRequest(value).method == "item/tool/requestUserInput")
    }

    @Test("既知3種の承認は従来どおりデコードされる（非回帰）")
    func knownApprovalsUnchanged() async throws {
        let request = await run(rawMessage: """
        {"jsonrpc":"2.0","id":15,"method":"item/commandExecution/requestApproval","params":{\
        "threadId":"thread-1","turnId":"turn-1","itemId":"item-1","startedAtMs":1,"command":"pwd","cwd":"/tmp"}}
        """)

        guard case .commandExecutionApproval(let value) = request else {
            Issue.record("Expected .commandExecutionApproval, got \(String(describing: request))")
            return
        }
        #expect(value.command == "pwd")
    }

    @Test("他の未実装メソッドは引き続き .unknown（スコープを広げていない）")
    func otherUnimplementedMethodsStayUnknown() async throws {
        let request = await run(rawMessage: """
        {"jsonrpc":"2.0","id":16,"method":"item/tool/call","params":{"threadId":"t"}}
        """)

        guard case .unknown(let method, _) = request else {
            Issue.record("Expected .unknown, got \(String(describing: request))")
            return
        }
        #expect(method == "item/tool/call")
    }
}
