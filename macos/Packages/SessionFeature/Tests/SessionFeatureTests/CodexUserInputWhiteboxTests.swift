import Foundation
import Testing
import CodexAppServerKit
import StructuredChatKit
@testable import SessionFeature

private actor WireResultBox {
    private var result: JSONValue?

    func set(_ result: JSONValue) {
        if self.result == nil {
            self.result = result
        }
    }

    var current: JSONValue? { result }
}

private func startUserInputHandling(
    _ handler: @escaping JSONRPCClient.ServerRequestHandler,
    request: ToolRequestUserInputRequest
) -> WireResultBox {
    let box = WireResultBox()
    Task {
        if let result = try? await handler(.userInputRequest(request)) {
            await box.set(result)
        }
    }
    return box
}

private func waitForWireResult(
    _ box: WireResultBox,
    timeout: Duration = .seconds(2)
) async -> JSONValue? {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        if let result = await box.current {
            return result
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return await box.current
}

private func firstUserInputRequest(
    from broker: ChatApprovalBroker,
    timeout: Duration = .seconds(2)
) async -> ChatUserInputRequest? {
    let stream = await broker.userInputRequests
    return await withTaskGroup(of: ChatUserInputRequest?.self) { group in
        group.addTask {
            for await request in stream {
                return request
            }
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

private func sampleUserInputRequest() -> ToolRequestUserInputRequest {
    ToolRequestUserInputRequest(
        threadId: "thread-1",
        turnId: "turn-1",
        itemId: "item-1",
        questions: [
            ToolRequestUserInputQuestion(
                id: "q1",
                header: "ヘッダ",
                question: "質問",
                options: [ToolRequestUserInputOption(label: "可読性", description: "読みやすさ")]
            )
        ]
    )
}

private func isEmptyUserInputResponse(_ result: JSONValue) -> Bool {
    guard let answers = result["answers"], case .object(let entries) = answers else {
        return false
    }
    return entries.isEmpty
}

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

@Suite("Whitebox: Codex 質問ブローカーの決着")
struct CodexUserInputWhiteboxTests {
    @Test("回答と cancelAll の競合でも wire は1回だけ決着する")
    func answerAndCancelRaceResolvesOnce() async throws {
        let broker = ChatApprovalBroker()
        let box = startUserInputHandling(
            broker.serverRequestHandler,
            request: sampleUserInputRequest()
        )
        let received = try #require(await firstUserInputRequest(from: broker))

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await broker.answerUserInput(id: received.id, answers: ["q1": ["可読性"]])
            }
            group.addTask {
                await broker.cancelAll()
            }
            await group.waitForAll()
        }

        let result = try #require(await waitForWireResult(box))
        let hasAnswer = answerLabels(result, id: "q1") == ["可読性"]
        #expect(hasAnswer || isEmptyUserInputResponse(result))

        await broker.answerUserInput(id: received.id, answers: ["q1": ["性能"]])
        await broker.declineUserInput(id: received.id)
        await broker.cancelAll()
        #expect(await waitForWireResult(box, timeout: .milliseconds(50)) == result)
    }

    @Test("同じ質問への拒否を2回呼んでも wire は1回だけ決着する")
    func doubleDeclineIsIdempotent() async throws {
        let broker = ChatApprovalBroker()
        let box = startUserInputHandling(
            broker.serverRequestHandler,
            request: sampleUserInputRequest()
        )
        let received = try #require(await firstUserInputRequest(from: broker))

        await broker.declineUserInput(id: received.id)
        await broker.declineUserInput(id: received.id)

        let result = try #require(await waitForWireResult(box))
        #expect(isEmptyUserInputResponse(result))
    }

    @Test("承認応答は質問用の保留を決着させない")
    func approvalResponseDoesNotResolveUserInput() async throws {
        let broker = ChatApprovalBroker()
        let box = startUserInputHandling(
            broker.serverRequestHandler,
            request: sampleUserInputRequest()
        )
        let received = try #require(await firstUserInputRequest(from: broker))

        await broker.respond(to: received.id, decision: .accept)
        #expect(await waitForWireResult(box, timeout: .milliseconds(100)) == nil)

        await broker.declineUserInput(id: received.id)
        #expect(await waitForWireResult(box) != nil)
    }
}
