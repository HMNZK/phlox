import Foundation
import Observation
import CodexAppServerKit

public protocol CodexSessionHistoryProviding: Sendable {
    func threadList(_ params: ThreadListParams) async throws -> ThreadListResponse
    func threadRead(_ params: ThreadReadParams) async throws -> ThreadReadResponse
    func threadResume(_ params: ThreadResumeParams) async throws -> ThreadResponse
}

extension CodexAppServerClient: CodexSessionHistoryProviding {}
extension CodexStructuredAgentClient: CodexSessionHistoryProviding {}

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
        guard let thread = threads.first(where: { $0.id == threadID }) else { return false }
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
        selectionGeneration += 1
        let selection = selectionGeneration
        do {
            let response = try await client.threadRead(ThreadReadParams(threadId: threadID, includeTurns: true))
            guard response.thread.id == threadID else {
                throw CodexAppServerClientError.threadIDMismatch(
                    requested: threadID,
                    received: response.thread.id
                )
            }
            guard selection == selectionGeneration,
                  selectedThreadID == nil || selectedThreadID == threadID else {
                return response.thread
            }
            update(thread: response.thread)
            errorMessage = nil
            return response.thread
        } catch {
            errorMessage = String(describing: error)
            throw error
        }
    }

    public func read(threadId: String) async throws -> ThreadSummary {
        try await read(threadID: threadId)
    }

    public func resumeSelected() async throws -> ThreadSummary? {
        guard let selectedThreadID else { return nil }
        return try await resume(threadID: selectedThreadID)
    }

    /// UI から呼ぶ再開。失敗は `errorMessage` に保持して surface へ表示する。
    public func resumeIfPossible(threadID: String) async -> ThreadSummary? {
        do {
            return try await resume(threadID: threadID)
        } catch {
            return nil
        }
    }

    public func resume(threadID: String) async throws -> ThreadSummary {
        selectionGeneration += 1
        let selection = selectionGeneration
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
            guard selection == selectionGeneration,
                  selectedThreadID == nil || selectedThreadID == threadID else {
                return response.thread
            }
            selectedThreadID = threadID
            update(thread: response.thread)
            errorMessage = nil
            return response.thread
        } catch {
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
        repeat {
            let response = try await client.threadList(ThreadListParams(
                cwd: .multiple([workingDirectory]),
                sourceKinds: [.cli, .vscode, .appServer],
                cursor: cursor
            ))
            result.append(contentsOf: response.data)
            cursor = response.nextCursor
        } while cursor != nil
        return result
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

    private static func deduplicated(_ threads: [ThreadSummary]) -> [ThreadSummary] {
        var seen = Set<String>()
        return threads.filter { seen.insert($0.id).inserted }
    }
}
