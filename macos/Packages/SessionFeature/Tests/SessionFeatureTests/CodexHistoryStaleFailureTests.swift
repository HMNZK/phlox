import Foundation
import Testing
import CodexAppServerKit
@testable import SessionFeature

@Suite("Regression: Codex history stale failure")
@MainActor
struct CodexHistoryStaleFailureTests {
    @Test("古い read の失敗は後続 B の成功を errorMessage で上書きしない")
    func staleReadFailureDoesNotOverwriteLaterSuccess() async throws {
        let client = StaleHistoryClient()
        let history = CodexSessionHistory(client: client, workingDirectory: "/workspace")

        let first = Task { await history.readIfPossible(threadID: "A") }
        await client.waitForStart("A")
        let second = Task { await history.readIfPossible(threadID: "B") }
        await client.waitForStart("B")

        _ = await second.value
        await client.fail("A")
        _ = await first.value

        #expect(history.selectedThreadID == "B")
        #expect(history.errorMessage == nil)
    }

    @Test("古い read の失敗は後続 B の失敗内容も上書きしない")
    func staleReadFailureDoesNotOverwriteLaterFailure() async throws {
        let client = StaleHistoryClient(failB: true)
        let history = CodexSessionHistory(client: client, workingDirectory: "/workspace")

        let first = Task { await history.readIfPossible(threadID: "A") }
        await client.waitForStart("A")
        let second = Task { await history.readIfPossible(threadID: "B") }
        await client.waitForStart("B")

        _ = await second.value
        #expect(history.errorMessage?.contains("B") == true)
        await client.fail("A")
        _ = await first.value

        #expect(history.errorMessage?.contains("B") == true)
    }

    @Test("古い resume の失敗は後続 B の成功を errorMessage で上書きしない")
    func staleResumeFailureDoesNotOverwriteLaterSuccess() async throws {
        let client = StaleHistoryClient()
        let history = CodexSessionHistory(client: client, workingDirectory: "/workspace")

        let first = Task { await history.resumeIfPossible(threadID: "A") }
        await client.waitForStart("resume:A")
        let second = Task { await history.resumeIfPossible(threadID: "B") }
        await client.waitForStart("resume:B")

        _ = await second.value
        await client.fail("resume:A")
        _ = await first.value

        #expect(history.selectedThreadID == "B")
        #expect(history.errorMessage == nil)
    }

    @Test("古い resume の失敗は後続 B の失敗内容も上書きしない")
    func staleResumeFailureDoesNotOverwriteLaterFailure() async throws {
        let client = StaleHistoryClient(failB: true)
        let history = CodexSessionHistory(client: client, workingDirectory: "/workspace")

        let first = Task { await history.resumeIfPossible(threadID: "A") }
        await client.waitForStart("resume:A")
        let second = Task { await history.resumeIfPossible(threadID: "B") }
        await client.waitForStart("resume:B")

        _ = await second.value
        #expect(history.errorMessage?.contains("B") == true)
        await client.fail("resume:A")
        _ = await first.value

        #expect(history.errorMessage?.contains("B") == true)
    }
}

private enum StaleHistoryError: Error, CustomStringConvertible, Sendable {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let id): "history-\(id)-failed"
        }
    }
}

private final class StaleHistoryClient: CodexSessionHistoryProviding, @unchecked Sendable {
    private actor Gate {
        var started: Set<String> = []
        var startWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]
        var responses: [String: CheckedContinuation<ThreadReadResponse, Error>] = [:]
        var resumeResponses: [String: CheckedContinuation<ThreadSummary, Error>] = [:]

        func noteStart(_ id: String) {
            started.insert(id)
            for waiter in startWaiters.removeValue(forKey: id) ?? [] {
                waiter.resume()
            }
        }

        func waitForStart(_ id: String) async {
            guard !started.contains(id) else { return }
            await withCheckedContinuation { continuation in
                startWaiters[id, default: []].append(continuation)
            }
        }

        func waitForResponse(_ id: String) async throws -> ThreadReadResponse {
            try await withCheckedThrowingContinuation { continuation in
                responses[id] = continuation
            }
        }

        func fail(_ id: String) {
            responses.removeValue(forKey: id)?.resume(throwing: StaleHistoryError.failed(id))
            resumeResponses.removeValue(forKey: id)?.resume(throwing: StaleHistoryError.failed(id))
        }

        func waitForResumeResponse(_ id: String) async throws -> ThreadSummary {
            try await withCheckedThrowingContinuation { continuation in
                resumeResponses[id] = continuation
            }
        }
    }

    private let gate = Gate()
    private let failB: Bool

    init(failB: Bool = false) {
        self.failB = failB
    }

    func waitForStart(_ id: String) async {
        await gate.waitForStart(id)
    }

    func fail(_ id: String) async {
        await gate.fail(id)
    }

    func threadList(_ params: ThreadListParams) async throws -> ThreadListResponse {
        ThreadListResponse(data: [])
    }

    func threadRead(_ params: ThreadReadParams) async throws -> ThreadReadResponse {
        await gate.noteStart(params.threadId)
        guard params.threadId == "A" else {
            if failB { throw StaleHistoryError.failed(params.threadId) }
            return readResponse(summary(id: params.threadId))
        }
        return try await gate.waitForResponse(params.threadId)
    }

    func threadResume(_ params: ThreadResumeParams) async throws -> ThreadResponse {
        resumeResponse(summary(id: params.threadId))
    }

    func threadResumeAndRead(_ params: ThreadResumeParams) async throws -> ThreadSummary {
        let id = "resume:\(params.threadId)"
        await gate.noteStart(id)
        guard params.threadId == "A" else {
            if failB { throw StaleHistoryError.failed(params.threadId) }
            return summary(id: params.threadId)
        }
        return try await gate.waitForResumeResponse(id)
    }

    func rollbackThreadResumeIfCurrent(threadID: String) async {}

    private func summary(id: String) -> ThreadSummary {
        ThreadSummary(
            id: id,
            cliVersion: "0.147.0",
            createdAt: 1,
            cwd: "/workspace",
            ephemeral: false,
            modelProvider: "openai",
            preview: id,
            sessionId: "session-\(id)",
            source: .appServer,
            status: .idle,
            turns: [],
            updatedAt: 2
        )
    }

    private func readResponse(_ thread: ThreadSummary) -> ThreadReadResponse {
        let rawThread = try! JSONDecoder().decode(
            JSONValue.self,
            from: JSONEncoder().encode(thread)
        )
        return try! JSONDecoder().decode(
            ThreadReadResponse.self,
            from: JSONEncoder().encode(JSONValue.object(["thread": rawThread]))
        )
    }

    private func resumeResponse(_ thread: ThreadSummary) -> ThreadResponse {
        let rawThread = try! JSONDecoder().decode(
            JSONValue.self,
            from: JSONEncoder().encode(thread)
        )
        return try! JSONDecoder().decode(
            ThreadResponse.self,
            from: JSONEncoder().encode(JSONValue.object(["thread": rawThread]))
        )
    }
}
