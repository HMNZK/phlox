import Foundation
import Testing
import CodexAppServerKit
@testable import SessionFeature

@Suite("Acceptance: Codex 背景端末")
struct AcceptanceCodexBackgroundTerminalTests {
    private func terminal(
        itemID: String,
        processID: String,
        command: String = "swift test",
        cwd: String = "/workspace"
    ) -> ThreadBackgroundTerminal {
        ThreadBackgroundTerminal(
            itemId: itemID,
            processId: processID,
            command: command,
            cwd: cwd,
            osPid: 4242,
            cpuPercent: 1.25,
            rssKb: 2048
        )
    }

    @Test("一覧DTOはitemId/processId/command/cwdを同じ行へ保持する")
    func listPreservesAllIdentifiers() throws {
        let response = ThreadBackgroundTerminalsListResponse(data: [terminal(itemID: "item-1", processID: "process-1")])
        let raw = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(response))
        let item = try #require(raw["data"]?.arrayValue?.first)

        #expect(item["itemId"] == .string("item-1"))
        #expect(item["processId"] == .string("process-1"))
        #expect(item["command"] == .string("swift test"))
        #expect(item["cwd"] == .string("/workspace"))
    }

    @Test("複数行のidentityを混同せず更新後も対応IDを保持する")
    func rowsRemainSeparatedAcrossRefresh() throws {
        let response = ThreadBackgroundTerminalsListResponse(data: [
            terminal(itemID: "item-1", processID: "process-1", command: "one"),
            terminal(itemID: "item-2", processID: "process-2", command: "two"),
        ])
        let decoded = try JSONDecoder().decode(
            ThreadBackgroundTerminalsListResponse.self,
            from: JSONEncoder().encode(response)
        )
        #expect(decoded.data.map(\.itemId) == ["item-1", "item-2"])
        #expect(decoded.data.map(\.processId) == ["process-1", "process-2"])
        #expect(decoded.data.map(\.command) == ["one", "two"])
    }

    @Test("terminate requestはthreadIdとprocessIdを両方指定する")
    func terminateUsesThreadAndProcessIdentity() throws {
        let request = ThreadBackgroundTerminalsTerminateParams(threadId: "thread-parent", processId: "process-1")
        let raw = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(request))
        #expect(raw == .object(["threadId": .string("thread-parent"), "processId": .string("process-1")]))
    }

    @Test("実clientはbackground terminalのlist/terminateを実DTOへ橋渡しする")
    func clientBridgesBackgroundTerminalMethods() async throws {
        let transport = BackgroundTerminalTransport()
        let client = CodexAppServerClient(transport: transport)
        do {
            await client.start()

            let response = try await client.threadBackgroundTerminalsList(
                ThreadBackgroundTerminalsListParams(threadId: "thread-parent", cursor: nil, limit: 20)
            )
            #expect(response.data.map { $0.itemId } == ["item-1"])
            #expect(response.data.first?.processId == "process-1")

            let terminated = try await client.threadBackgroundTerminalsTerminate(
                ThreadBackgroundTerminalsTerminateParams(threadId: "thread-parent", processId: "process-1")
            )
            #expect(terminated.terminated)

            let requests = await transport.requests.all()
            #expect(requests.map { $0["method"]?.stringValue } == [
                "thread/backgroundTerminals/list",
                "thread/backgroundTerminals/terminate",
            ])
            #expect(requests[0]["params"]?["threadId"] == .string("thread-parent"))
            #expect(requests[1]["params"]?["processId"] == .string("process-1"))
        } catch {
            await client.close()
            throw error
        }
        await client.close()
    }

}

private extension JSONValue {
    var arrayValue: [JSONValue]? {
        guard case .array(let values) = self else { return nil }
        return values
    }
}

private final class BackgroundTerminalTransport: AppServerTransport, @unchecked Sendable {
    let requests = BackgroundTerminalRequests()
    let receivedLines: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation

    init() {
        var captured: AsyncStream<Data>.Continuation?
        receivedLines = AsyncStream { captured = $0 }
        continuation = captured!
    }

    func send(_ data: Data) async throws {
        let value = try JSONDecoder().decode(JSONValue.self, from: data.dropLastIfNewline())
        await requests.append(value)
        guard let id = value["id"] else { return }

        let result: JSONValue
        switch value["method"]?.stringValue {
        case "thread/backgroundTerminals/list":
            result = .object([
                "data": .array([.object([
                    "itemId": .string("item-1"),
                    "processId": .string("process-1"),
                    "command": .string("swift test"),
                    "cwd": .string("/workspace"),
                ])]),
                "nextCursor": .null,
            ])
        case "thread/backgroundTerminals/terminate":
            result = .object(["terminated": .bool(true)])
        default:
            result = .object([:])
        }

        let response = JSONValue.object([
            "jsonrpc": .string("2.0"),
            "id": id,
            "result": result,
        ])
        continuation.yield(try JSONEncoder().encode(response))
    }

    func close() async {
        continuation.finish()
    }
}

private actor BackgroundTerminalRequests {
    private var values: [JSONValue] = []

    func append(_ value: JSONValue) {
        values.append(value)
    }

    func all() -> [JSONValue] {
        values
    }
}

private extension Data {
    func dropLastIfNewline() -> Data {
        last == 0x0A ? dropLast() : self
    }
}
