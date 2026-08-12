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
        try await withTaskCleanup(first) {
            try await client.waitForStart("A")
            let second = Task { await history.readIfPossible(threadID: "B") }
            try await withTaskCleanup(second) {
                try await client.waitForStart("B")

                _ = await second.value
                await client.fail("A")
                _ = await first.value

                #expect(history.selectedThreadID == "B")
                #expect(history.errorMessage == nil)
            }
        }
    }

    @Test("古い read の失敗は後続 B の失敗内容も上書きしない")
    func staleReadFailureDoesNotOverwriteLaterFailure() async throws {
        let client = StaleHistoryClient(failB: true)
        let history = CodexSessionHistory(client: client, workingDirectory: "/workspace")

        let first = Task { await history.readIfPossible(threadID: "A") }
        try await withTaskCleanup(first) {
            try await client.waitForStart("A")
            let second = Task { await history.readIfPossible(threadID: "B") }
            try await withTaskCleanup(second) {
                try await client.waitForStart("B")

                _ = await second.value
                #expect(history.errorMessage?.contains("B") == true)
                await client.fail("A")
                _ = await first.value

                #expect(history.errorMessage?.contains("B") == true)
            }
        }
    }

    @Test("古い resume の失敗は後続 B の成功を errorMessage で上書きしない")
    func staleResumeFailureDoesNotOverwriteLaterSuccess() async throws {
        let client = StaleHistoryClient()
        let history = CodexSessionHistory(client: client, workingDirectory: "/workspace")

        let first = Task { await history.resumeIfPossible(threadID: "A") }
        try await withTaskCleanup(first) {
            try await client.waitForStart("resume:A")
            let second = Task { await history.resumeIfPossible(threadID: "B") }
            try await withTaskCleanup(second) {
                try await client.waitForStart("resume:B")

                _ = await second.value
                await client.fail("resume:A")
                _ = await first.value

                #expect(history.selectedThreadID == "B")
                #expect(history.errorMessage == nil)
            }
        }
    }

    @Test("古い resume の失敗は後続 B の失敗内容も上書きしない")
    func staleResumeFailureDoesNotOverwriteLaterFailure() async throws {
        let client = StaleHistoryClient(failB: true)
        let history = CodexSessionHistory(client: client, workingDirectory: "/workspace")

        let first = Task { await history.resumeIfPossible(threadID: "A") }
        try await withTaskCleanup(first) {
            try await client.waitForStart("resume:A")
            let second = Task { await history.resumeIfPossible(threadID: "B") }
            try await withTaskCleanup(second) {
                try await client.waitForStart("resume:B")

                _ = await second.value
                #expect(history.errorMessage?.contains("B") == true)
                await client.fail("resume:A")
                _ = await first.value

                #expect(history.errorMessage?.contains("B") == true)
            }
        }
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

private enum StaleHistoryWaitError: Error, CustomStringConvertible, Sendable {
    case timedOut(String)

    var description: String {
        switch self {
        case .timedOut(let operation): "Timed out waiting for \(operation)"
        }
    }
}

private final class StaleHistoryClient: CodexSessionHistoryProviding, @unchecked Sendable {
    private actor Gate {
        var started: Set<String> = []
        var startWaiters: [String: CheckedContinuation<Void, Error>] = [:]
        var responses: [String: CheckedContinuation<ThreadReadResponse, Error>] = [:]
        var resumeResponses: [String: CheckedContinuation<ThreadSummary, Error>] = [:]

        func noteStart(_ id: String) {
            started.insert(id)
            startWaiters.removeValue(forKey: id)?.resume()
        }

        func waitForStart(_ id: String, timeout: Duration = .seconds(2)) async throws {
            guard !started.contains(id) else { return }

            try await withTaskCancellationHandler(operation: {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask { try await self.waitForStartContinuation(id) }
                    group.addTask {
                        try await Task.sleep(for: timeout)
                        throw StaleHistoryWaitError.timedOut("start \(id)")
                    }
                    defer { group.cancelAll() }
                    try await group.next()
                }
            }, onCancel: {
                Task { await self.cancelStartWaiter(id) }
            })
        }

        private func waitForStartContinuation(_ id: String) async throws {
            try await withTaskCancellationHandler(operation: {
                try await withCheckedThrowingContinuation(isolation: self) {
                    (continuation: CheckedContinuation<Void, Error>) in
                    if started.contains(id) {
                        continuation.resume()
                    } else {
                        startWaiters[id] = continuation
                    }
                }
            }, onCancel: {
                Task { await self.cancelStartWaiter(id) }
            })
        }

        private func cancelStartWaiter(_ id: String) {
            startWaiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
        }

        func waitForResponse(_ id: String, timeout: Duration = .seconds(2)) async throws -> ThreadReadResponse {
            try await withTaskCancellationHandler(operation: {
                try await withThrowingTaskGroup(of: ThreadReadResponse.self) { group in
                    group.addTask { try await self.waitForResponseContinuation(id) }
                    group.addTask {
                        try await Task.sleep(for: timeout)
                        throw StaleHistoryWaitError.timedOut("response \(id)")
                    }
                    defer { group.cancelAll() }
                    return try await group.next()!
                }
            }, onCancel: {
                Task { await self.cancelResponseWaiter(id) }
            })
        }

        private func waitForResponseContinuation(_ id: String) async throws -> ThreadReadResponse {
            try await withTaskCancellationHandler(operation: {
                try await withCheckedThrowingContinuation(isolation: self) {
                    (continuation: CheckedContinuation<ThreadReadResponse, Error>) in
                    responses[id] = continuation
                }
            }, onCancel: {
                Task { await self.cancelResponseWaiter(id) }
            })
        }

        private func cancelResponseWaiter(_ id: String) {
            responses.removeValue(forKey: id)?.resume(throwing: CancellationError())
        }

        func waitForResumeResponse(
            _ id: String,
            timeout: Duration = .seconds(2)
        ) async throws -> ThreadSummary {
            try await withTaskCancellationHandler(operation: {
                try await withThrowingTaskGroup(of: ThreadSummary.self) { group in
                    group.addTask { try await self.waitForResumeResponseContinuation(id) }
                    group.addTask {
                        try await Task.sleep(for: timeout)
                        throw StaleHistoryWaitError.timedOut("resume response \(id)")
                    }
                    defer { group.cancelAll() }
                    return try await group.next()!
                }
            }, onCancel: {
                Task { await self.cancelResumeResponseWaiter(id) }
            })
        }

        private func waitForResumeResponseContinuation(_ id: String) async throws -> ThreadSummary {
            try await withTaskCancellationHandler(operation: {
                try await withCheckedThrowingContinuation(isolation: self) {
                    (continuation: CheckedContinuation<ThreadSummary, Error>) in
                    resumeResponses[id] = continuation
                }
            }, onCancel: {
                Task { await self.cancelResumeResponseWaiter(id) }
            })
        }

        private func cancelResumeResponseWaiter(_ id: String) {
            resumeResponses.removeValue(forKey: id)?.resume(throwing: CancellationError())
        }

        func fail(_ id: String) {
            responses.removeValue(forKey: id)?.resume(throwing: StaleHistoryError.failed(id))
            resumeResponses.removeValue(forKey: id)?.resume(throwing: StaleHistoryError.failed(id))
        }

    }

    private let gate = Gate()
    private let failB: Bool

    init(failB: Bool = false) {
        self.failB = failB
    }

    func waitForStart(_ id: String) async throws {
        try await gate.waitForStart(id)
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

@MainActor
private func withTaskCleanup<Value, Result>(
    _ task: Task<Value, Never>,
    operation: () async throws -> Result
) async throws -> Result {
    do {
        return try await operation()
    } catch {
        task.cancel()
        _ = await task.value
        throw error
    }
}
