import Foundation
import Testing
import CodexAppServerKit
@testable import SessionFeature

@Suite("Contract: Codex background terminal state")
@MainActor
struct ContractCodexBackgroundTerminalStateTests {
    @Test("stateは実CodexAppServerClientのterminate後に再取得して停止を確定する")
    func stateUsesRealExperimentalClientSeam() async throws {
        let transport = ContractStateTransport()
        let client = CodexAppServerClient(transport: transport)
        do {
            await client.start()
            let state = CodexBackgroundTerminalState(client: client, threadId: "thread-contract")

            await state.refresh()
            #expect(state.terminal(itemId: "item-1")?.processId == "process-1")
            #expect(await state.terminate(itemId: "item-1"))
            #expect(state.terminal(itemId: "item-1") == nil)

            let requests = await transport.requests.all()
            #expect(requests.map { $0["method"]?.stringValue } == [
                "thread/backgroundTerminals/list",
                "thread/backgroundTerminals/terminate",
                "thread/backgroundTerminals/list",
            ])
            #expect(requests[1]["params"]?["threadId"] == .string("thread-contract"))
            #expect(requests[1]["params"]?["processId"] == .string("process-1"))
        } catch {
            await client.close()
            throw error
        }
        await client.close()
    }
}

private final class ContractStateTransport: AppServerTransport, @unchecked Sendable {
    let requests = ContractStateRequests()
    let receivedLines: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation

    init() {
        var captured: AsyncStream<Data>.Continuation?
        receivedLines = AsyncStream(bufferingPolicy: .unbounded) { captured = $0 }
        continuation = captured!
    }

    func send(_ data: Data) async throws {
        let line = data.firstIndex(of: 0x0A).map { Data(data[..<$0]) } ?? data
        let request = try JSONDecoder().decode(JSONValue.self, from: line)
        await requests.append(request)
        guard let id = request["id"] else { return }

        let method = request["method"]?.stringValue
        let listCount = await requests.listCount()
        let result: JSONValue
        switch method {
        case "thread/backgroundTerminals/list":
            let data: JSONValue = listCount == 1
                ? .array([.object([
                    "itemId": .string("item-1"),
                    "processId": .string("process-1"),
                    "command": .string("echo contract"),
                    "cwd": .string("/contract"),
                ])])
                : .array([])
            result = .object(["data": data, "nextCursor": .null])
        case "thread/backgroundTerminals/terminate":
            result = .object(["terminated": .bool(true)])
        default:
            result = .object([:])
        }

        continuation.yield(try JSONEncoder().encode(JSONValue.object([
            "jsonrpc": .string("2.0"),
            "id": id,
            "result": result,
        ])))
    }

    func close() async {
        continuation.finish()
    }
}

private actor ContractStateRequests {
    private var values: [JSONValue] = []

    func append(_ value: JSONValue) {
        values.append(value)
    }

    func listCount() -> Int {
        values.filter { $0["method"]?.stringValue == "thread/backgroundTerminals/list" }.count
    }

    func all() -> [JSONValue] {
        values
    }
}
