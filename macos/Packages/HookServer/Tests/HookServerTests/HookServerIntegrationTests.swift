import AgentDomain
import Foundation
import Testing
@testable import HookServer

@Suite struct HookServerIntegrationTests {
    private let sessionID = SessionID()

    @Test func sessionStartEvent() async throws {
        try await assertHook(
            json: """
            {"sessionId":"\(sessionID.rawValue.uuidString)","kind":"sessionStart"}
            """,
            expected: .sessionStart
        )
    }

    @Test func notificationEvent() async throws {
        try await assertHook(
            json: """
            {"sessionId":"\(sessionID.rawValue.uuidString)","kind":"notification","message":"hello"}
            """,
            expected: .notification(message: "hello")
        )
    }

    @Test func stopEvent() async throws {
        try await assertHook(
            json: """
            {"sessionId":"\(sessionID.rawValue.uuidString)","kind":"stop","exitCode":0}
            """,
            expected: .stop(turnId: nil)
        )
    }

    @Test func preToolUseEvent() async throws {
        try await assertHook(
            json: """
            {"sessionId":"\(sessionID.rawValue.uuidString)","kind":"preToolUse","toolName":"Shell"}
            """,
            expected: .preToolUse(toolName: "Shell")
        )
    }

    @Test func postToolUseEvent() async throws {
        try await assertHook(
            json: """
            {"sessionId":"\(sessionID.rawValue.uuidString)","kind":"postToolUse","toolName":"Read"}
            """,
            expected: .postToolUse(toolName: "Read")
        )
    }

    @Test func userPromptSubmitEvent() async throws {
        try await assertHook(
            json: """
            {"sessionId":"\(sessionID.rawValue.uuidString)","kind":"userPromptSubmit"}
            """,
            expected: .userPromptSubmit(turnId: nil)
        )
    }

    @Test func nativeSessionIdIsDeliveredWithEvent() async throws {
        let server = HookServer()
        let port = try await server.start()
        let nativeID = "019e9177-d565-78e2-95b9-174015ba898e"

        let deliveryTask = Task { () -> HookDelivery? in
            var iterator = server.deliveries.makeAsyncIterator()
            return await iterator.next()
        }

        let statusCode = try await postHook(
            port: port,
            body: """
            {"sessionId":"\(sessionID.rawValue.uuidString)","kind":"userPromptSubmit","turnId":"turn-1","nativeSessionId":"\(nativeID)"}
            """,
            expectedStatus: 200
        )
        #expect(statusCode == 200)

        let delivery = await deliveryTask.value
        #expect(delivery?.sessionID == sessionID)
        #expect(delivery?.event == .userPromptSubmit(turnId: "turn-1"))
        #expect(delivery?.nativeSessionId == nativeID)
    }

    @Test func invalidJSONReturns400() async throws {
        let server = HookServer()
        let port = try await server.start()
        let statusCode = try await postHook(port: port, body: "{not json", expectedStatus: 400)
        #expect(statusCode == 400)
    }

    // MARK: - 境界系（追加）

    @Test func invalidUUIDReturns400() async throws {
        let server = HookServer()
        let port = try await server.start()
        let body = """
        {"sessionId":"not-a-uuid","kind":"notification","message":"hi"}
        """
        let statusCode = try await postHook(port: port, body: body, expectedStatus: 400)
        #expect(statusCode == 400)
    }

    @Test func unknownPathReturns404() async throws {
        let server = HookServer()
        let port = try await server.start()
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/unknown")!)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        let (_, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        #expect(statusCode == 404)
    }

    @Test func getMethodOnHookPathReturns404() async throws {
        let server = HookServer()
        let port = try await server.start()
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/hook")!)
        request.httpMethod = "GET"
        let (_, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        #expect(statusCode == 404)
    }

    @Test func concurrentPostsAllReceived() async throws {
        let server = HookServer()
        let port = try await server.start()

        let count = 10
        let baseIDs = (0..<count).map { _ in SessionID() }

        // 受信側を先に走らせる
        let receiveTask = Task { () -> [SessionID] in
            var collected: [SessionID] = []
            var iterator = server.events.makeAsyncIterator()
            while collected.count < count, let item = await iterator.next() {
                collected.append(item.0)
            }
            return collected
        }

        // 10 件を並列に POST
        try await withThrowingTaskGroup(of: Void.self) { group in
            for id in baseIDs {
                group.addTask {
                    let body = """
                    {"sessionId":"\(id.rawValue.uuidString)","kind":"userPromptSubmit"}
                    """
                    _ = try await Self.postHookStatic(port: port, body: body)
                }
            }
            try await group.waitForAll()
        }

        let received = await receiveTask.value
        #expect(received.count == count)
        // 順序は保証しないが、欠落しないことを集合一致で確認
        #expect(Set(received) == Set(baseIDs))
    }

    // MARK: - Helpers

    private func assertHook(json: String, expected: HookEvent) async throws {
        let server = HookServer()
        let port = try await server.start()

        let eventTask = Task { () -> (SessionID, HookEvent)? in
            var iterator = server.events.makeAsyncIterator()
            return await iterator.next()
        }

        let statusCode = try await postHook(port: port, body: json, expectedStatus: 200)
        #expect(statusCode == 200)

        let received = await eventTask.value
        #expect(received?.0 == sessionID)
        #expect(received?.1 == expected)
    }

    private func postHook(port: Int, body: String, expectedStatus: Int) async throws -> Int {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/hook")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(body.utf8)
        let (_, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        return statusCode
    }

    static func postHookStatic(port: Int, body: String) async throws -> Int {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/hook")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(body.utf8)
        let (_, response) = try await URLSession.shared.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode ?? -1
    }
}
