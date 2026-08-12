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

    /// `CodexSettingsProviding` を使う既存 Session からの注入用。
    public init(
        client: any CodexSettingsProviding,
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
        self.threadId = threadId
        terminals = []
        selectedItemId = nil
        confirmedTerminationItemIds = []
        errorMessage = nil
    }

    public func updateThreadID(_ threadId: String?) {
        updateThreadId(threadId)
    }

    /// app-server の一覧を取得する。ページングが返った場合は全ページを結合する。
    public func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        guard let threadId, !threadId.isEmpty else {
            errorMessage = CodexBackgroundTerminalError.threadNotStarted.localizedDescription
            return
        }

        do {
            let fetched = try await listRequest(threadId)
            terminals = fetched
            if let selectedItemId,
               !terminals.contains(where: { $0.itemId == selectedItemId }) {
                self.selectedItemId = nil
            }
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
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
    public func jumpTarget(for itemId: String) -> String? {
        terminal(itemId: itemId) == nil ? nil : itemId
    }

    public func jumpTarget(
        for itemId: String,
        transcriptItemIds: Set<String>
    ) -> String? {
        guard transcriptItemIds.contains(itemId) else { return nil }
        return jumpTarget(for: itemId)
    }

    public func canJump(to itemId: String) -> Bool {
        jumpTarget(for: itemId) != nil
    }

    /// itemId から対応する processId を解決して停止する。
    /// terminate=true の戻り値だけでは削除せず、再取得で itemId が消えた場合だけ true。
    @discardableResult
    public func terminate(itemId: String) async -> Bool {
        guard !terminatingItemIds.contains(itemId),
              let terminal = terminal(itemId: itemId),
              let threadId,
              !threadId.isEmpty
        else { return false }

        terminatingItemIds.insert(itemId)
        isTerminating = true
        defer {
            terminatingItemIds.remove(itemId)
            isTerminating = !terminatingItemIds.isEmpty
        }

        do {
            let response = try await terminateRequest(threadId, terminal.processId)
            guard response.terminated else { return false }

            let previousError = errorMessage
            await refresh()
            guard errorMessage == nil else {
                // 再取得不能時は、terminate の戻り値だけで停止済みと断定しない。
                errorMessage = previousError ?? errorMessage
                return false
            }
            let confirmed = self.terminal(itemId: itemId) == nil
            if confirmed {
                confirmedTerminationItemIds.insert(itemId)
                if selectedItemId == itemId {
                    selectedItemId = nil
                }
            }
            return confirmed
        } catch {
            errorMessage = String(describing: error)
            return false
        }
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

    private static func requests<Client: CodexBackgroundTerminalProviding>(
        for client: Client,
        pageSize: UInt32
    ) -> (list: ListRequest, terminate: TerminateRequest) {
        let list: ListRequest = { threadId in
            var cursor: String?
            var result: [ThreadBackgroundTerminal] = []
            repeat {
                let response = try await client.threadBackgroundTerminalsList(
                    ThreadBackgroundTerminalsListParams(
                        threadId: threadId,
                        cursor: cursor,
                        limit: pageSize
                    )
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
