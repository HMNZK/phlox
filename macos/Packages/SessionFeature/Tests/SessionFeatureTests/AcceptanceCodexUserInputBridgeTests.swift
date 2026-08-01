import Foundation
import Testing
import CodexAppServerKit
import StructuredChatKit
@testable import SessionFeature

/// task-2 受け入れテスト（PM が著す不変の契約。実装役は編集不可）。
/// `item/tool/requestUserInput` を承認ではなく質問として橋渡しし、
/// 未実装のサーバ要求は承認バナーを出さずに -32601 相当のエラーを投げることを固定する。
///
/// ハーネス方針: ハンドラの完了は `WireBox` へ書かせてポーリングで待つ。
/// `Task.value` の await はキャンセル不能なので、タイムアウトと組み合わせると
/// テスト自体がハングする（＝未実装時に verify 全体を止める）ため使わない。
@Suite("Acceptance: Codex 質問のブローカー橋渡し（task-2）")
struct AcceptanceCodexUserInputBridgeTests {
    // MARK: - ハーネス

    /// ハンドラの決着（成功 or 例外）を1回だけ記録する箱。
    private actor WireBox {
        enum Outcome: Sendable {
            case value(JSONValue)
            case failure(Bool)  // true = JSONRPCClientError
        }

        private var outcome: Outcome?
        func set(_ value: Outcome) { if outcome == nil { outcome = value } }
        var current: Outcome? { outcome }
    }

    /// ハンドラを別タスクで開始し、決着を書き込む箱を返す。
    private func startHandling(
        _ handler: @escaping JSONRPCClient.ServerRequestHandler,
        _ request: ServerRequest
    ) -> WireBox {
        let box = WireBox()
        Task {
            do {
                await box.set(.value(try await handler(request)))
            } catch is JSONRPCClientError {
                await box.set(.failure(true))
            } catch {
                await box.set(.failure(false))
            }
        }
        return box
    }

    /// 箱が埋まるまでポーリングで待つ（タイムアウト時 nil）。
    private func settled(
        _ box: WireBox,
        timeout: Duration = .seconds(2)
    ) async -> WireBox.Outcome? {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if let outcome = await box.current { return outcome }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return await box.current
    }

    /// 決着した wire の JSON を取り出す（例外・タイムアウトなら nil）。
    private func wireResult(_ box: WireBox, timeout: Duration = .seconds(2)) async -> JSONValue? {
        guard case .value(let value) = await settled(box, timeout: timeout) else { return nil }
        return value
    }

    /// userInputRequests から最初の1件を取り出す（タイムアウト付き）。
    private func firstUserInput(
        _ broker: ChatApprovalBroker,
        timeout: Duration = .seconds(2)
    ) async -> ChatUserInputRequest? {
        let stream = await broker.userInputRequests
        return await withTaskGroup(of: ChatUserInputRequest?.self) { group in
            group.addTask {
                for await request in stream { return request }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    /// 承認ストリームから最初の1件を取り出す（タイムアウト付き）。
    private func firstApproval(
        _ broker: ChatApprovalBroker,
        timeout: Duration = .seconds(2)
    ) async -> ChatApprovalRequest? {
        let stream = await broker.requests
        return await withTaskGroup(of: ChatApprovalRequest?.self) { group in
            group.addTask {
                for await request in stream { return request }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    private func sampleRequest(
        questionIds: [String] = ["q1"],
        withOptions: Bool = true
    ) -> ToolRequestUserInputRequest {
        ToolRequestUserInputRequest(
            threadId: "thread-1",
            turnId: "turn-1",
            itemId: "item-1",
            questions: questionIds.map { id in
                ToolRequestUserInputQuestion(
                    id: id,
                    header: "ヘッダ-\(id)",
                    question: "質問-\(id)",
                    options: withOptions
                        ? [
                            ToolRequestUserInputOption(label: "可読性", description: "読みやすさ"),
                            ToolRequestUserInputOption(label: "性能", description: "速度"),
                        ]
                        : nil
                )
            }
        )
    }

    /// `answers[id].answers` の配列を取り出す。存在しなければ nil。
    private func answerLabels(_ result: JSONValue, id: String) -> [String]? {
        guard let answers = result["answers"],
              let entry = answers[id],
              let list = entry["answers"],
              case .array(let items) = list
        else {
            return nil
        }
        return items.compactMap(\.stringValue)
    }

    /// `answers` が空オブジェクトかどうか。
    private func answersIsEmpty(_ result: JSONValue) -> Bool {
        guard let answers = result["answers"], case .object(let object) = answers else { return false }
        return object.isEmpty
    }

    // MARK: - 質問の橋渡し

    @Test("質問は承認ストリームへ流れず、userInputRequests へ流れる")
    func questionGoesToUserInputStreamNotApprovals() async throws {
        let broker = ChatApprovalBroker()
        let box = startHandling(broker.serverRequestHandler, .userInputRequest(sampleRequest()))
        let received = try #require(await firstUserInput(broker))

        #expect(received.threadId == "thread-1")
        #expect(received.turnId == "turn-1")
        #expect(received.itemId == "item-1")
        #expect(received.questions.count == 1)

        let question = try #require(received.questions.first)
        #expect(question.id == "q1")
        #expect(question.answerKey == "q1")
        #expect(question.header == "ヘッダ-q1")
        #expect(question.question == "質問-q1")
        #expect(question.options.map(\.label) == ["可読性", "性能"])
        #expect(question.multiSelect == false)

        // 承認ストリームには何も流れていない（流れていれば 0.3 秒以内に取れるはず）。
        let approval = await firstApproval(broker, timeout: .milliseconds(300))
        #expect(approval == nil, "質問を承認バナーとして出してはならない")

        await broker.declineUserInput(id: received.id)
        _ = await settled(box)
    }

    @Test("options が nil の質問は選択肢なし（自由入力）として渡る")
    func questionWithoutOptions() async throws {
        let broker = ChatApprovalBroker()
        let box = startHandling(
            broker.serverRequestHandler,
            .userInputRequest(sampleRequest(withOptions: false))
        )

        let received = try #require(await firstUserInput(broker))
        #expect(received.questions.first?.options.isEmpty == true)

        await broker.declineUserInput(id: received.id)
        _ = await settled(box)
    }

    // MARK: - wire 応答の形

    @Test("回答は answers[id].answers の入れ子形で wire へ返る")
    func answerProducesNestedWireShape() async throws {
        let broker = ChatApprovalBroker()
        let box = startHandling(
            broker.serverRequestHandler,
            .userInputRequest(sampleRequest(questionIds: ["q1", "q2"]))
        )

        let received = try #require(await firstUserInput(broker))
        await broker.answerUserInput(
            id: received.id,
            answers: ["q1": ["可読性"], "q2": ["性能", "可読性"]]
        )

        let result = try #require(await wireResult(box))
        #expect(answerLabels(result, id: "q1") == ["可読性"])
        #expect(answerLabels(result, id: "q2") == ["性能", "可読性"])
    }

    @Test("回答が渡されなかった質問はキーごと省く")
    func omitsUnansweredQuestions() async throws {
        let broker = ChatApprovalBroker()
        let box = startHandling(
            broker.serverRequestHandler,
            .userInputRequest(sampleRequest(questionIds: ["q1", "q2"]))
        )

        let received = try #require(await firstUserInput(broker))
        await broker.answerUserInput(id: received.id, answers: ["q1": ["可読性"]])

        let result = try #require(await wireResult(box))
        #expect(answerLabels(result, id: "q1") == ["可読性"])
        #expect(answerLabels(result, id: "q2") == nil)
    }

    @Test("拒否は空の answers で wire を決着させる")
    func declineResolvesWithEmptyAnswers() async throws {
        let broker = ChatApprovalBroker()
        let box = startHandling(broker.serverRequestHandler, .userInputRequest(sampleRequest()))

        let received = try #require(await firstUserInput(broker))
        await broker.declineUserInput(id: received.id)

        let result = try #require(await wireResult(box))
        #expect(answersIsEmpty(result))
    }

    // MARK: - 未実装の要求

    @Test("未実装のサーバ要求は承認を出さず unsupportedServerRequest を投げる")
    func unknownRequestThrowsInsteadOfApproval() async throws {
        let broker = ChatApprovalBroker()
        let box = startHandling(
            broker.serverRequestHandler,
            .unknown(method: "item/tool/call", params: nil)
        )

        let outcome = await settled(box)
        guard case .failure(let isJSONRPCError) = outcome else {
            Issue.record("未実装の要求は例外で決着すること（実際: \(String(describing: outcome))）")
            return
        }
        #expect(isJSONRPCError, "JSONRPCClientError.unsupportedServerRequest を投げること（-32601 になる）")

        let approval = await firstApproval(broker, timeout: .milliseconds(300))
        #expect(approval == nil, "未実装の要求を承認バナーにしてはならない")
    }

    // MARK: - continuation の 1 回 resume（ハザード）

    @Test("cancelAll は保留中の質問を空 answers で決着させ、以後の質問も即時決着する")
    func cancelAllResolvesPendingAndLateQuestions() async throws {
        let broker = ChatApprovalBroker()
        let box = startHandling(broker.serverRequestHandler, .userInputRequest(sampleRequest()))
        _ = try #require(await firstUserInput(broker))

        await broker.cancelAll()
        let result = try #require(await wireResult(box))
        #expect(answersIsEmpty(result))

        // close 後に到達した質問も待たせずに決着する（continuation を漏らさない）。
        let lateBox = startHandling(broker.serverRequestHandler, .userInputRequest(sampleRequest()))
        let late = try #require(await wireResult(lateBox))
        #expect(answersIsEmpty(late))
    }

    @Test("同じ質問へ二重に応答しても継続は1回だけ resume される（クラッシュしない）")
    func doubleResponseIsIdempotent() async throws {
        let broker = ChatApprovalBroker()
        let box = startHandling(broker.serverRequestHandler, .userInputRequest(sampleRequest()))

        let received = try #require(await firstUserInput(broker))
        await broker.answerUserInput(id: received.id, answers: ["q1": ["可読性"]])
        await broker.answerUserInput(id: received.id, answers: ["q1": ["性能"]])
        await broker.declineUserInput(id: received.id)
        await broker.cancelAll()

        let result = try #require(await wireResult(box))
        #expect(answerLabels(result, id: "q1") == ["可読性"])
    }

    // MARK: - 非回帰

    @Test("既知の承認3種は従来どおり承認ストリームへ流れる（非回帰）")
    func approvalsUnchanged() async throws {
        let broker = ChatApprovalBroker()
        let json = """
        {"threadId":"t","turnId":"u","itemId":"i","startedAtMs":1,"command":"pwd","cwd":"/tmp"}
        """
        let request = try JSONDecoder().decode(
            CommandExecutionApprovalRequest.self,
            from: Data(json.utf8)
        )
        let box = startHandling(broker.serverRequestHandler, .commandExecutionApproval(request))

        let received = try #require(await firstApproval(broker))
        #expect(received.kind == .command)
        #expect(received.prompt == "pwd")

        await broker.respond(to: received.id, decision: .accept)
        let result = try #require(await wireResult(box))
        #expect(result["decision"]?.stringValue == "accept")
    }
}
