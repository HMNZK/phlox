import Foundation
import Testing
import CodexAppServerKit
@testable import SessionFeature

/// task-2 の履歴 seam 契約。
///
/// SessionFeature の履歴状態と実 DTO・client・event seam が
/// list/read/resume の transport identity を保つ境界を検査する。
@Suite("Contract: Codex 履歴 seam")
@MainActor
struct ContractCodexHistorySeamTests {
    private let cwd = "/workspace/project"

    @Test("list request は cwd と sourceKinds を固定する")
    func listRequestHasExactFilters() async throws {
        let transport = CodexHistoryTransport()
        let client = CodexAppServerClient(transport: transport)
        do {
            await client.start()
            let history = CodexSessionHistory(client: client, cwd: cwd)
            await history.refresh()

            let response = try await client.threadList(ThreadListParams(
                cwd: .multiple([cwd]),
                sourceKinds: [.cli, .vscode, .appServer],
                parentThreadId: nil,
                ancestorThreadId: nil
            ))
            let request = try #require(await transport.firstRequest(method: "thread/list"))

            #expect(request["params"] == JSONValue.object([
                "cwd": .array([.string(cwd)]),
                "sourceKinds": .array([.string("cli"), .string("vscode"), .string("appServer")]),
            ]))
            #expect(response.data.map(\.id) == ["cli-1", "app-1"])
            #expect(response.nextCursor == "page-2")
            #expect(history.threads.map(\.id) == ["cli-1", "app-1", "app-2"])
        } catch {
            await client.close()
            throw error
        }
        await client.close()
    }

    @Test("read は includeTurns=true を必ず指定する")
    func readRequestIncludesTurns() async throws {
        let transport = CodexHistoryTransport()
        let client = CodexAppServerClient(transport: transport)
        do {
            await client.start()
            let history = CodexSessionHistory(client: client, cwd: cwd)

            let response = try await client.threadRead(ThreadReadParams(threadId: "thread-1"))
            let read = try await history.read(threadID: "thread-1")
            let request = try #require(await transport.firstRequest(method: "thread/read"))

            #expect(request["params"] == JSONValue.object([
                "threadId": .string("thread-1"),
                "includeTurns": .bool(true),
            ]))
            #expect(response.thread.id == "thread-1")
            #expect(response.thread.parentThreadId == "parent-thread")
            #expect(response.thread.canAcceptDirectInput == false)
            #expect(read.id == "thread-1")
            #expect(history.selectedThreadID == "thread-1")
        } catch {
            await client.close()
            throw error
        }
        await client.close()
    }

    @Test("別 thread の read 応答は選択 ID の成功扱いにならない")
    func staleReadResponseCannotReplaceSelection() async throws {
        let transport = CodexHistoryTransport(readResponseID: "thread-1")
        let client = CodexAppServerClient(transport: transport)
        do {
            await client.start()
            let history = CodexSessionHistory(client: client, cwd: cwd)

            do {
                _ = try await history.read(threadID: "thread-2")
                Issue.record("thread/read の ID mismatch が成功扱いになっている")
            } catch let error as CodexAppServerClientError {
                #expect(error == .threadIDMismatch(requested: "thread-2", received: "thread-1"))
            }
            #expect(history.selectedThreadID == nil)
            #expect(history.threads.isEmpty)
        } catch {
            await client.close()
            throw error
        }
        await client.close()
    }

    @Test("resume 成功後だけ選択 thread の ID を一致させる")
    func resumeStateChangesOnlyAfterMatchingResponse() async throws {
        let transport = CodexHistoryTransport()
        let client = CodexAppServerClient(transport: transport)
        do {
            await client.start()
            let history = CodexSessionHistory(client: client, cwd: cwd)

            let response = try await history.resume(threadID: "thread-1")
            let request = try #require(await transport.firstRequest(method: "thread/resume"))

            #expect(response.id == "thread-1")
            #expect(history.selectedThreadID == "thread-1")
            #expect(history.selectedThread?.id == "thread-1")
            #expect(request["params"]?["threadId"] == JSONValue.string("thread-1"))
            #expect(request["params"]?["cwd"] == JSONValue.string(cwd))
        } catch {
            await client.close()
            throw error
        }
        await client.close()
    }

    @Test("別 thread の resume 応答は選択状態を更新しない")
    func staleResumeResponseCannotReplaceSelection() async throws {
        let transport = CodexHistoryTransport(resumeResponseID: "thread-1")
        let client = CodexAppServerClient(transport: transport)
        do {
            await client.start()
            let history = CodexSessionHistory(client: client, cwd: cwd)

            do {
                _ = try await history.resume(threadID: "thread-2")
                Issue.record("thread/resume の ID mismatch が成功扱いになっている")
            } catch let error as CodexAppServerClientError {
                #expect(error == .threadIDMismatch(requested: "thread-2", received: "thread-1"))
            }
            #expect(history.selectedThreadID == nil)
            #expect(history.selectedThread == nil)
            #expect(history.threads.isEmpty)
        } catch {
            await client.close()
            throw error
        }
        await client.close()
    }

    @Test("turn/completed event は threadId と turn identity を保持する")
    func completedEventPreservesThreadAndTurnIdentity() async throws {
        let transport = CodexHistoryTransport()
        let client = CodexAppServerClient(transport: transport)
        await client.start()
        var events = client.events.makeAsyncIterator()

        transport.receive(#"{"jsonrpc":"2.0","method":"turn/completed","params":{"threadId":"thread-1","turn":{"id":"turn-1","status":"interrupted","items":[]}}}"#)

        if case .turnCompleted(let threadId, let turn) = await events.next() {
            #expect(threadId == "thread-1")
            #expect(turn.id == "turn-1")
            #expect(turn.status == "interrupted")
        } else {
            Issue.record("turn/completed が typed event へ到達していない")
        }
        await client.close()
    }
}

final class CodexHistoryTransport: AppServerTransport, @unchecked Sendable {
    private actor Recorder {
        private var messages: [JSONValue] = []

        func append(_ message: JSONValue) {
            messages.append(message)
        }

        func first(method: String) -> JSONValue? {
            messages.first { $0["method"]?.stringValue == method }
        }
    }

    let receivedLines: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation
    private let recorder = Recorder()
    private let readResponseID: String?
    private let resumeResponseID: String?

    init(readResponseID: String? = nil, resumeResponseID: String? = nil) {
        self.readResponseID = readResponseID
        self.resumeResponseID = resumeResponseID
        var captured: AsyncStream<Data>.Continuation?
        receivedLines = AsyncStream { captured = $0 }
        continuation = captured!
    }

    func send(_ data: Data) async throws {
        let line = data.firstIndex(of: 0x0A).map { Data(data[..<$0]) } ?? data
        let request = try JSONDecoder().decode(JSONValue.self, from: line)
        await recorder.append(request)
        guard let id = request["id"]?.intValue,
              let method = request["method"]?.stringValue
        else { return }

        let result: JSONValue
        switch method {
        case "thread/list":
            if request["params"]?["cursor"]?.stringValue != nil {
                result = .object([
                    "data": .array([
                        threadJSON(id: "app-1", source: "appServer"),
                        threadJSON(id: "app-2", source: "appServer"),
                    ]),
                    "nextCursor": .null,
                ])
            } else {
                result = .object([
                    "data": .array([
                        threadJSON(id: "cli-1", source: "cli"),
                        threadJSON(id: "app-1", source: "appServer"),
                    ]),
                    "nextCursor": .string("page-2"),
                ])
            }
        case "thread/read":
            let requested = request["params"]?["threadId"]?.stringValue ?? "thread-1"
            result = .object(["thread": threadJSON(id: readResponseID ?? requested, parent: "parent-thread")])
        case "thread/resume":
            let requested = request["params"]?["threadId"]?.stringValue ?? "thread-1"
            result = .object(["thread": threadJSON(id: resumeResponseID ?? requested)])
        default:
            result = .object([:])
        }

        let response = JSONValue.object([
            "jsonrpc": .string("2.0"),
            "id": .number(Double(id)),
            "result": result,
        ])
        continuation.yield(try JSONEncoder().encode(response))
    }

    func close() async {
        continuation.finish()
    }

    func receive(_ json: String) {
        continuation.yield(Data(json.utf8))
    }

    func firstRequest(method: String) async -> JSONValue? {
        await recorder.first(method: method)
    }

    private func threadJSON(id: String, source: String = "appServer", parent: String? = nil) -> JSONValue {
        var object: [String: JSONValue] = [
            "id": .string(id),
            "cliVersion": .string("0.147.0"),
            "createdAt": .number(1),
            "cwd": .string("/workspace/project"),
            "ephemeral": .bool(false),
            "modelProvider": .string("openai"),
            "preview": .string("shared title"),
            "sessionId": .string("session-\(id)"),
            "source": .string(source),
            "status": .object(["type": .string("idle")]),
            "turns": .array([]),
            "updatedAt": .number(2),
        ]
        if let parent {
            object["parentThreadId"] = .string(parent)
            object["canAcceptDirectInput"] = .bool(false)
        }
        return .object(object)
    }
}
