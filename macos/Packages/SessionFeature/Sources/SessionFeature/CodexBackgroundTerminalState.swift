import Foundation
import Observation
import CodexAppServerKit

/// Codex の実験的な背景ターミナル API を SessionFeature から利用するための seam。
///
/// app-server の DTO は `itemId`（表示・選択）と `processId`（停止）を別々に
/// 持つため、状態管理側でもこの 2 つを混ぜない。
public protocol CodexBackgroundTerminalProviding: Sendable {
    func threadBackgroundTerminalsList(
        _ params: ThreadBackgroundTerminalsListParams
    ) async throws -> ThreadBackgroundTerminalsListResponse

    func threadBackgroundTerminalsTerminate(
        _ params: ThreadBackgroundTerminalsTerminateParams
    ) async throws -> ThreadBackgroundTerminalsTerminateResponse
}

public enum CodexBackgroundTerminalError: Error, Equatable, Sendable {
    case unsupported
    case threadNotStarted
}

public extension CodexBackgroundTerminalProviding {
    func threadBackgroundTerminalsList(
        _ params: ThreadBackgroundTerminalsListParams
    ) async throws -> ThreadBackgroundTerminalsListResponse {
        throw CodexBackgroundTerminalError.unsupported
    }

    func threadBackgroundTerminalsTerminate(
        _ params: ThreadBackgroundTerminalsTerminateParams
    ) async throws -> ThreadBackgroundTerminalsTerminateResponse {
        throw CodexBackgroundTerminalError.unsupported
    }
}

extension CodexAppServerClient: CodexBackgroundTerminalProviding {}
extension CodexStructuredAgentClient: CodexBackgroundTerminalProviding {}

private actor CodexBackgroundTerminalOperationGate {
    private var occupied = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func enter() async {
        guard occupied else {
            occupied = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func leave() {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume()
        } else {
            occupied = false
        }
    }
}

/// Codex 背景ターミナルの一覧・詳細・停止を保持する状態。
///
/// 停止の成功は terminate の戻り値だけでは確定しない。terminate が true を返した
/// 後に list を再取得し、対象 `itemId` が消えたときだけ状態からも停止済みとする。
@MainActor
@Observable
public final class CodexBackgroundTerminalState {
    public typealias Terminal = ThreadBackgroundTerminal

    public private(set) var terminals: [ThreadBackgroundTerminal] = []
    public private(set) var selectedItemId: String?
    public private(set) var isRefreshing = false
    public private(set) var isTerminating = false
    public private(set) var terminatingItemIds: Set<String> = []
    public private(set) var confirmedTerminationItemIds: Set<String> = []
    public private(set) var errorMessage: String?
    public private(set) var threadId: String?

    private var threadGeneration = 0
    private var listGeneration = 0
    private let operationGate = CodexBackgroundTerminalOperationGate()

    /// UI が「一覧」と呼ぶ場合の読み取り用別名。
    public var items: [ThreadBackgroundTerminal] { terminals }

    /// 選択中の詳細。選択項目が一覧から消えた場合は nil になる。
    public var selectedTerminal: ThreadBackgroundTerminal? {
        guard let selectedItemId else { return nil }
        return terminal(itemId: selectedItemId)
    }

    public var detail: ThreadBackgroundTerminal? { selectedTerminal }

    public init(
        client: any CodexBackgroundTerminalProviding,
        threadId: String? = nil,
        pageSize: UInt32 = 20
    ) {
        self.threadId = threadId
        let requests = Self.requests(for: client, pageSize: pageSize)
        self.listRequest = requests.list
        self.terminateRequest = requests.terminate
    }

    /// Session の thread が reset / restore で変わったときに呼ぶ。
    /// thread を跨いだ一覧を一時的に表示しないよう、ID 変更時は選択と一覧を捨てる。
    public func updateThreadId(_ threadId: String?) {
        guard self.threadId != threadId else { return }
        threadGeneration += 1
        listGeneration += 1
        self.threadId = threadId
        invalidateList()
        errorMessage = nil
    }

    public func updateThreadID(_ threadId: String?) {
        updateThreadId(threadId)
    }

    /// app-server の一覧を取得する。ページングが返った場合は全ページを結合する。
    public func refresh() async {
        await operationGate.enter()
        defer { Task { await operationGate.leave() } }
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        guard let threadId, !threadId.isEmpty else {
            invalidateList()
            errorMessage = CodexBackgroundTerminalError.threadNotStarted.localizedDescription
            return
        }
        let generation = threadGeneration
        listGeneration += 1
        let requestGeneration = listGeneration

        do {
            let fetched = try await listRequest(threadId)
            guard isCurrentList(
                threadGeneration: generation,
                listGeneration: requestGeneration,
                threadId: threadId
            ) else { return }
            terminals = fetched
            if let selectedItemId,
               !terminals.contains(where: { $0.itemId == selectedItemId }) {
                self.selectedItemId = nil
            }
            errorMessage = nil
        } catch {
            guard isCurrentList(
                threadGeneration: generation,
                listGeneration: requestGeneration,
                threadId: threadId
            ) else { return }
            let message = String(describing: error)
            invalidateList()
            errorMessage = message
        }
    }

    public func load() async {
        await refresh()
    }

    public func list() async {
        await refresh()
    }

    /// itemId だけを選択キーに使う。存在しない項目は選択も jump も行わない。
    @discardableResult
    public func select(itemId: String) -> Bool {
        guard terminals.contains(where: { $0.itemId == itemId }) else { return false }
        selectedItemId = itemId
        return true
    }

    @discardableResult
    public func selectItem(_ itemId: String) -> Bool {
        select(itemId: itemId)
    }

    public func terminal(itemId: String) -> ThreadBackgroundTerminal? {
        terminals.first { $0.itemId == itemId }
    }

    public func detail(for itemId: String) -> ThreadBackgroundTerminal? {
        terminal(itemId: itemId)
    }

    /// 一覧に存在する item だけを transcript jump の対象にする。
    public func jumpTarget(
        for itemId: String,
        transcriptItemIds: Set<String>
    ) -> String? {
        guard transcriptItemIds.contains(itemId), terminal(itemId: itemId) != nil else { return nil }
        return itemId
    }

    /// itemId から対応する processId を解決して停止する。
    /// terminate=true の戻り値だけでは削除せず、再取得で itemId が消えた場合だけ true。
    @discardableResult
    public func terminate(itemId: String) async -> Bool {
        await operationGate.enter()
        defer { Task { await operationGate.leave() } }
        guard !terminatingItemIds.contains(itemId),
              let terminal = terminal(itemId: itemId),
              let threadId,
              !threadId.isEmpty
        else {
            errorMessage = "背景ターミナルを停止できませんでした"
            return false
        }
        let generation = threadGeneration
        listGeneration += 1
        let requestGeneration = listGeneration

        terminatingItemIds.insert(itemId)
        isTerminating = true
        defer {
            terminatingItemIds.remove(itemId)
            isTerminating = !terminatingItemIds.isEmpty
        }

        let response: ThreadBackgroundTerminalsTerminateResponse
        do {
            response = try await terminateRequest(threadId, terminal.processId)
        } catch {
            // terminate RPC の失敗は一覧の信頼性を壊さないため、対象を保持する。
            guard isCurrentList(
                threadGeneration: generation,
                listGeneration: requestGeneration,
                threadId: threadId
            ) else { return false }
            errorMessage = String(describing: error)
            return false
        }
        guard isCurrentList(
            threadGeneration: generation,
            listGeneration: requestGeneration,
            threadId: threadId
        ) else { return false }
        guard response.terminated else {
            errorMessage = "背景ターミナルを停止できませんでした"
            return false
        }

        // terminate=true でも必ず同じ thread の一覧を再取得して確認する。
        let fetched: [ThreadBackgroundTerminal]
        do {
            fetched = try await listRequest(threadId)
        } catch {
            guard isCurrentList(
                threadGeneration: generation,
                listGeneration: requestGeneration,
                threadId: threadId
            ) else { return false }
            invalidateList()
            errorMessage = String(describing: error)
            return false
        }
        guard isCurrentList(
            threadGeneration: generation,
            listGeneration: requestGeneration,
            threadId: threadId
        ) else { return false }
        terminals = fetched
        if let selectedItemId,
           !terminals.contains(where: { $0.itemId == selectedItemId }) {
            self.selectedItemId = nil
        }
        errorMessage = nil
        // item が消えても processId が別 item に再利用されていれば未確認とする。
        let confirmed = self.terminal(itemId: itemId) == nil
            && !terminals.contains(where: { $0.processId == terminal.processId })
        if confirmed {
            confirmedTerminationItemIds.insert(itemId)
            if selectedItemId == itemId {
                selectedItemId = nil
            }
        } else {
            errorMessage = "背景ターミナルの停止を確認できませんでした"
        }
        return confirmed
    }

    @discardableResult
    public func terminate(_ itemId: String) async -> Bool {
        await terminate(itemId: itemId)
    }

    @discardableResult
    public func stop(itemId: String) async -> Bool {
        await terminate(itemId: itemId)
    }

    private typealias ListRequest = @Sendable (String) async throws -> [ThreadBackgroundTerminal]
    private typealias TerminateRequest = @Sendable (String, String) async throws -> ThreadBackgroundTerminalsTerminateResponse

    private let listRequest: ListRequest
    private let terminateRequest: TerminateRequest

    private func invalidateList() {
        terminals.removeAll()
        selectedItemId = nil
        confirmedTerminationItemIds.removeAll()
    }

    private func isCurrentList(
        threadGeneration: Int,
        listGeneration: Int,
        threadId: String
    ) -> Bool {
        threadGeneration == self.threadGeneration
            && listGeneration == self.listGeneration
            && self.threadId == threadId
    }

    private static func requests<Client: CodexBackgroundTerminalProviding>(
        for client: Client,
        pageSize: UInt32
    ) -> (list: ListRequest, terminate: TerminateRequest) {
        let list: ListRequest = { threadId in
            var cursor: String?
            var seenCursors = Set<String>()
            var result: [ThreadBackgroundTerminal] = []
            repeat {
                if let cursor, !seenCursors.insert(cursor).inserted {
                    break
                }
                let response = try await client.threadBackgroundTerminalsList(
                    ThreadBackgroundTerminalsListParams(threadId: threadId, cursor: cursor, limit: pageSize)
                )
                result.append(contentsOf: response.data)
                cursor = response.nextCursor
            } while cursor != nil
            return result
        }
        let terminate: TerminateRequest = { threadId, processId in
            try await client.threadBackgroundTerminalsTerminate(
                ThreadBackgroundTerminalsTerminateParams(
                    threadId: threadId,
                    processId: processId
                )
            )
        }
        return (list, terminate)
    }
}
