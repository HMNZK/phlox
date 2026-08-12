import Foundation
import Observation
import CodexAppServerKit

public protocol CodexSessionHistoryProviding: Sendable {
    func threadList(_ params: ThreadListParams) async throws -> ThreadListResponse
    func threadRead(_ params: ThreadReadParams) async throws -> ThreadReadResponse
    func threadResume(_ params: ThreadResumeParams) async throws -> ThreadResponse

    /// 履歴からの再開を、詳細取得まで完了した場合だけ active thread に反映する。
    /// 通常の client は既存の2呼び出しへフォールバックし、Codex の structured adapter
    /// は active thread の commit を最後へ遅延させる。
    func threadResumeAndRead(_ params: ThreadResumeParams) async throws -> ThreadSummary

    /// raw な resume の直後に read が失敗した場合、adapter が保持する
    /// active thread を resume 前へ戻す。通常の client では何もしない。
    func rollbackThreadResumeIfCurrent(threadID: String) async
}

public extension CodexSessionHistoryProviding {
    func threadResumeAndRead(_ params: ThreadResumeParams) async throws -> ThreadSummary {
        _ = try await threadResume(params)
        return try await threadRead(ThreadReadParams(threadId: params.threadId, includeTurns: true)).thread
    }

    func rollbackThreadResumeIfCurrent(threadID: String) async {}
}

extension CodexAppServerClient: CodexSessionHistoryProviding {}
extension CodexStructuredAgentClient: CodexSessionHistoryProviding {}

public enum CodexSessionHistoryError: Error, Equatable, Sendable, CustomStringConvertible {
    case repeatedCursor(String)
    case unavailable(String)
    case superseded

    public var description: String {
        switch self {
        case .repeatedCursor(let cursor):
            "thread/list pagination stopped: repeated nextCursor \(cursor)"
        case .unavailable(let threadID):
            "thread \(threadID) is unavailable until history refresh succeeds"
        case .superseded:
            "thread operation superseded by a newer history operation"
        }
    }
}

/// Codex app-server の履歴一覧と選択中 thread の詳細を管理する。
@MainActor
@Observable
public final class CodexSessionHistory {
    public private(set) var threads: [ThreadSummary] = []
    public private(set) var selectedThreadID: String?
    public private(set) var selectedThread: ThreadSummary?
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?

    public var entries: [ThreadSummary] { threads }
    public var items: [ThreadSummary] { threads }
    public var history: [ThreadSummary] { threads }
    public var selectedThreadId: String? { selectedThreadID }

    private let client: any CodexSessionHistoryProviding
    private let workingDirectory: String
    private var loadGeneration = 0
    private var selectionGeneration = 0
    private var hasLoadedList = false
    private var listTrustInvalidated = false

    public init(
        client: any CodexSessionHistoryProviding,
        workingDirectory: String
    ) {
        self.client = client
        self.workingDirectory = workingDirectory
    }

    public convenience init(
        client: any CodexSessionHistoryProviding,
        cwd: String
    ) {
        self.init(client: client, workingDirectory: cwd)
    }

    /// 現在の cwd に属する cli / vscode / app-server thread を全ページ取得する。
    public func refresh() async {
        loadGeneration += 1
        selectionGeneration += 1
        let generation = loadGeneration
        isLoading = true
        defer {
            if generation == loadGeneration {
                isLoading = false
            }
        }

        do {
            let fetched = try await fetchAllPages()
            guard generation == loadGeneration else { return }
            threads = Self.deduplicated(fetched)
            hasLoadedList = true
            listTrustInvalidated = false
            if let selectedThreadID,
               let refreshed = threads.first(where: { $0.id == selectedThreadID }) {
                selectedThread = refreshed
            } else if selectedThreadID != nil {
                self.selectedThreadID = nil
                selectedThread = nil
            }
            errorMessage = nil
        } catch {
            guard generation == loadGeneration else { return }
            invalidateList()
            errorMessage = String(describing: error)
        }
    }

    public func load() async {
        await refresh()
    }

    public func list() async {
        await refresh()
    }

    @discardableResult
    public func select(threadID: String) -> Bool {
        guard !listTrustInvalidated,
              let thread = threads.first(where: { $0.id == threadID }) else { return false }
        selectionGeneration += 1
        selectedThreadID = threadID
        selectedThread = thread
        return true
    }

    @discardableResult
    public func select(threadId: String) -> Bool {
        select(threadID: threadId)
    }

    public func thread(id: String) -> ThreadSummary? {
        threads.first { $0.id == id }
    }

    public func readSelected() async throws -> ThreadSummary? {
        guard let selectedThreadID else { return nil }
        return try await read(threadID: selectedThreadID)
    }

    /// UI から呼ぶ読み取り。失敗は `errorMessage` に保持して surface へ表示する。
    public func readIfPossible(threadID: String) async -> ThreadSummary? {
        do {
            return try await read(threadID: threadID)
        } catch {
            return nil
        }
    }

    public func read(threadID: String) async throws -> ThreadSummary {
        guard canUseThread(threadID) else {
            let error = CodexSessionHistoryError.unavailable(threadID)
            errorMessage = String(describing: error)
            throw error
        }
        selectionGeneration += 1
        let selection = selectionGeneration
        let selectedAtStart = selectedThreadID
        do {
            let response = try await client.threadRead(ThreadReadParams(threadId: threadID, includeTurns: true))
            guard response.thread.id == threadID else {
                throw CodexAppServerClientError.threadIDMismatch(
                    requested: threadID,
                    received: response.thread.id
                )
            }
            guard isCurrentOperation(
                selection,
                threadID: threadID,
                selectedAtStart: selectedAtStart
            ) else {
                throw CodexSessionHistoryError.superseded
            }
            update(thread: response.thread)
            errorMessage = nil
            return response.thread
        } catch {
            guard isCurrentOperation(
                selection,
                threadID: threadID,
                selectedAtStart: selectedAtStart
            ) else { throw error }
            await client.rollbackThreadResumeIfCurrent(threadID: threadID)
            errorMessage = String(describing: error)
            throw error
        }
    }

    public func read(threadId: String) async throws -> ThreadSummary {
        try await read(threadID: threadId)
    }

    public func resumeSelected() async throws -> ThreadSummary? {
        guard let selectedThreadID else { return nil }
        return try await resumeAndRead(threadID: selectedThreadID)
    }

    /// UI から呼ぶ再開。失敗は `errorMessage` に保持して surface へ表示する。
    public func resumeIfPossible(threadID: String) async -> ThreadSummary? {
        do {
            return try await resumeAndRead(threadID: threadID)
        } catch {
            return nil
        }
    }

    /// resume と read を一つの操作世代で扱う。read が失敗した場合は履歴 state を更新せず、
    /// structured adapter 側も active thread を commit しない。
    public func resumeAndRead(threadID: String) async throws -> ThreadSummary {
        guard canUseThread(threadID) else {
            let error = CodexSessionHistoryError.unavailable(threadID)
            errorMessage = String(describing: error)
            throw error
        }
        selectionGeneration += 1
        let selection = selectionGeneration
        let selectedAtStart = selectedThreadID
        do {
            let thread = try await client.threadResumeAndRead(
                ThreadResumeParams(threadId: threadID, cwd: workingDirectory)
            )
            guard thread.id == threadID else {
                throw CodexAppServerClientError.threadIDMismatch(
                    requested: threadID,
                    received: thread.id
                )
            }
            guard isCurrentOperation(
                selection,
                threadID: threadID,
                selectedAtStart: selectedAtStart
            ) else {
                throw CodexSessionHistoryError.superseded
            }
            update(thread: thread)
            errorMessage = nil
            return thread
        } catch {
            guard isCurrentOperation(
                selection,
                threadID: threadID,
                selectedAtStart: selectedAtStart
            ) else { throw error }
            await client.rollbackThreadResumeIfCurrent(threadID: threadID)
            errorMessage = String(describing: error)
            throw error
        }
    }

    public func resume(threadID: String) async throws -> ThreadSummary {
        guard canUseThread(threadID) else {
            let error = CodexSessionHistoryError.unavailable(threadID)
            errorMessage = String(describing: error)
            throw error
        }
        selectionGeneration += 1
        let selection = selectionGeneration
        let selectedAtStart = selectedThreadID
        do {
            let response = try await client.threadResume(
                ThreadResumeParams(threadId: threadID, cwd: workingDirectory)
            )
            guard response.thread.id == threadID else {
                throw CodexAppServerClientError.threadIDMismatch(
                    requested: threadID,
                    received: response.thread.id
                )
            }
            guard isCurrentOperation(
                selection,
                threadID: threadID,
                selectedAtStart: selectedAtStart
            ) else {
                throw CodexSessionHistoryError.superseded
            }
            selectedThreadID = threadID
            update(thread: response.thread)
            errorMessage = nil
            return response.thread
        } catch {
            guard isCurrentOperation(
                selection,
                threadID: threadID,
                selectedAtStart: selectedAtStart
            ) else { throw error }
            await client.rollbackThreadResumeIfCurrent(threadID: threadID)
            errorMessage = String(describing: error)
            throw error
        }
    }

    public func resume(threadId: String) async throws -> ThreadSummary {
        try await resume(threadID: threadId)
    }

    private func fetchAllPages() async throws -> [ThreadSummary] {
        var cursor: String?
        var result: [ThreadSummary] = []
        var seenCursors = Set<String>()
        repeat {
            let response = try await client.threadList(ThreadListParams(
                cwd: .multiple([workingDirectory]),
                sourceKinds: [.cli, .vscode, .appServer],
                cursor: cursor
            ))
            result.append(contentsOf: response.data.filter(Self.isMainThread))
            guard let nextCursor = response.nextCursor else { break }
            guard seenCursors.insert(nextCursor).inserted else {
                throw CodexSessionHistoryError.repeatedCursor(nextCursor)
            }
            cursor = nextCursor
        } while cursor != nil
        return result
    }

    private static func isMainThread(_ thread: ThreadSummary) -> Bool {
        guard thread.parentThreadId?.isEmpty != false else { return false }
        switch thread.source {
        case .cli, .vscode, .appServer:
            return true
        case .exec, .unknown, .custom, .subAgent, .unknownRaw:
            return false
        }
    }

    private func update(thread: ThreadSummary) {
        selectedThreadID = thread.id
        selectedThread = thread
        if let index = threads.firstIndex(where: { $0.id == thread.id }) {
            threads[index] = thread
        } else {
            threads.append(thread)
        }
    }

    private func canUseThread(_ threadID: String) -> Bool {
        guard hasLoadedList else { return true }
        return !listTrustInvalidated && threads.contains { $0.id == threadID }
    }

    private func isCurrentOperation(
        _ generation: Int,
        threadID: String,
        selectedAtStart: String?
    ) -> Bool {
        generation == selectionGeneration
            && (selectedThreadID == selectedAtStart || selectedThreadID == threadID)
    }

    private func invalidateList() {
        hasLoadedList = true
        listTrustInvalidated = true
        threads.removeAll()
        selectedThreadID = nil
        selectedThread = nil
    }

    private static func deduplicated(_ threads: [ThreadSummary]) -> [ThreadSummary] {
        var seen = Set<String>()
        return threads.filter { seen.insert($0.id).inserted }
    }
}
