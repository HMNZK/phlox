import Foundation
import Testing
@testable import CodexAppServerKit

@Suite("親の中断は Codex の配下も停止する")
struct ParentInterruptCascadeTests {
    @Test("実行中の子の turn ID が無い場合は失敗を返し、孫と兄弟を止める")
    func reportsMissingActiveTurn() async throws {
        let transport = CascadeInterruptTransport(missingActiveTurn: "child")
        let adapter = CodexStructuredAgentClient(client: CodexAppServerClient(transport: transport))
        await adapter.start()
        do {
            _ = try await adapter.threadStart(ThreadStartParams())
            do {
                try await adapter.interrupt()
                Issue.record("実行中の子の停止先不明を返していない")
            } catch {
                #expect(String(describing: error).contains("active turn ID unavailable"))
            }
            #expect(transport.interruptedIDs == ["grandchild", "page-child"])
        } catch {
            await adapter.close()
            throw error
        }
        await adapter.close()
    }

    @Test("実行中の親を先に止めてから配下を止める")
    func interruptsParentFirst() async throws {
        let transport = CascadeInterruptTransport()
        let client = CodexAppServerClient(transport: transport)
        let adapter = CodexStructuredAgentClient(client: client)
        await adapter.start()
        do {
            _ = try await adapter.threadStart(ThreadStartParams())
            var events = adapter.threadEvents.makeAsyncIterator()
            transport.receive(#"{"jsonrpc":"2.0","method":"turn/started","params":{"threadId":"parent","turn":{"id":"turn-parent","status":"inProgress"}}}"#)
            _ = try #require(await events.next())
            #expect(await client.activeTurnId(for: "parent") == "turn-parent")
            try await adapter.interrupt()
            #expect(transport.interruptedIDs == ["parent", "child", "grandchild", "page-child"])
        } catch {
            await adapter.close()
            throw error
        }
        await adapter.close()
    }

    @Test("idle の親でも子・孫と一覧の次ページを止め、無関係の thread は止めない")
    func interruptsDescendantsWithoutActiveParent() async throws {
        let transport = CascadeInterruptTransport()
        let adapter = CodexStructuredAgentClient(client: CodexAppServerClient(transport: transport))
        await adapter.start()
        do {
            _ = try await adapter.threadStart(ThreadStartParams())
            try await adapter.interrupt()
            #expect(transport.interruptedIDs == ["child", "grandchild", "page-child"])
            #expect(transport.readIDs.contains("finished"))
            #expect(!transport.readIDs.contains("unrelated"))
        } catch {
            await adapter.close()
            throw error
        }
        await adapter.close()
    }

    @Test("子の停止失敗を返しても、孫と兄弟の停止を続ける")
    func continuesAfterChildFailure() async throws {
        let transport = CascadeInterruptTransport(failingChild: "child")
        let adapter = CodexStructuredAgentClient(client: CodexAppServerClient(transport: transport))
        await adapter.start()
        do {
            _ = try await adapter.threadStart(ThreadStartParams())
            do {
                try await adapter.interrupt()
                Issue.record("子の停止失敗を返していない")
            } catch {
                #expect(String(describing: error).contains("child"))
            }
            #expect(transport.interruptedIDs == ["child", "grandchild", "page-child"])
        } catch {
            await adapter.close()
            throw error
        }
        await adapter.close()
    }

    @Test("read の親子関係が変わった thread は止めず、失敗を報告する")
    func rejectsChangedIdentity() async throws {
        let transport = CascadeInterruptTransport(mismatchedChild: "child")
        let adapter = CodexStructuredAgentClient(client: CodexAppServerClient(transport: transport))
        await adapter.start()
        do {
            _ = try await adapter.threadStart(ThreadStartParams())
            do {
                try await adapter.interrupt()
                Issue.record("親子関係の不一致を返していない")
            } catch {
                #expect(String(describing: error).contains("child"))
            }
            #expect(transport.interruptedIDs == ["page-child"])
        } catch {
            await adapter.close()
            throw error
        }
        await adapter.close()
    }
}

private final class CascadeInterruptTransport: AppServerTransport, @unchecked Sendable {
    let receivedLines: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation
    private let lock = NSLock()
    private var interrupts: [String] = []
    private var reads: [String] = []
    private let failingChild: String?
    private let mismatchedChild: String?
    private let missingActiveTurn: String?

    var interruptedIDs: [String] { lock.withLock { interrupts } }
    var readIDs: [String] { lock.withLock { reads } }

    init(failingChild: String? = nil, mismatchedChild: String? = nil, missingActiveTurn: String? = nil) {
        let stream = AsyncStream<Data>.makeStream()
        receivedLines = stream.stream
        continuation = stream.continuation
        self.failingChild = failingChild
        self.mismatchedChild = mismatchedChild
        self.missingActiveTurn = missingActiveTurn
    }

    func send(_ data: Data) async throws {
        let request = try JSONDecoder().decode(JSONValue.self, from: data)
        guard let id = request["id"] else { return }
        let params = request["params"]
        let threadID = params?["threadId"]?.stringValue ?? ""
        var result: JSONValue = .object([:])
        switch request["method"]?.stringValue {
        case "thread/start":
            result = .object(["thread": thread("parent", parent: nil, running: false)])
        case "thread/list":
            let parent = params?["parentThreadId"]?.stringValue
            let rows: [JSONValue]
            if parent == "parent", params?["cursor"]?.stringValue == nil {
                rows = [thread("child", parent: "parent"), thread("finished", parent: "parent", running: false), thread("unrelated", parent: "other")]
                result = .object(["data": .array(rows), "nextCursor": .string("page-2")])
            } else {
                rows = parent == "child" ? [thread("grandchild", parent: "child")]
                    : parent == "parent" ? [thread("page-child", parent: "parent")] : []
                result = .object(["data": .array(rows)])
            }
        case "thread/read":
            lock.withLock { reads.append(threadID) }
            let parent = threadID == mismatchedChild ? "other" : threadID == "grandchild" ? "child" : "parent"
            result = .object(["thread": thread(threadID, parent: parent, running: threadID != "finished", includeTurns: threadID != missingActiveTurn)])
        case "turn/interrupt":
            lock.withLock { interrupts.append(threadID) }
            #expect(params?["turnId"] == .string("turn-\(threadID)"))
            if threadID == failingChild {
                continuation.yield(try JSONEncoder().encode(JSONValue.object([
                    "jsonrpc": .string("2.0"), "id": id,
                    "error": .object(["code": .number(-32000), "message": .string("stop failed")]),
                ])))
                return
            }
        default: break
        }
        continuation.yield(try JSONEncoder().encode(JSONValue.object([
            "jsonrpc": .string("2.0"), "id": id, "result": result,
        ])))
    }

    func close() async { continuation.finish() }

    func receive(_ line: String) { continuation.yield(Data(line.utf8)) }

    private func thread(_ id: String, parent: String?, running: Bool = true, includeTurns: Bool = false) -> JSONValue {
        var fields: [String: JSONValue] = [
            "id": .string(id), "status": .object(["type": .string(running ? "active" : "idle")]),
            "source": parent == nil ? .string("appServer") : .object(["subAgent": .object(["thread_spawn": .object(["parent_thread_id": .string(parent!)])])]),
            "turns": .array(includeTurns ? [.object(["id": .string("turn-\(id)"), "status": .string(running ? "inProgress" : "completed")])] : []),
        ]
        if let parent { fields["parentThreadId"] = .string(parent) }
        return .object(fields)
    }
}
