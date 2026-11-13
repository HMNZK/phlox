import Foundation
import StructuredChatKit

public enum JSONRPCClientError: LocalizedError, Equatable, Sendable {
    case transportClosed
    case malformedMessage(String)
    case invalidResponse(String)
    case serverError(code: Int, message: String)
    case unsupportedServerRequest(String)
    /// サーバ要求への応答を書き込めなかった、または書き込めたか確認できない。同じIDへは再送しない（二重応答になる）。
    case responseNotDelivered(String)

    public var errorDescription: String? {
        switch self {
        case .transportClosed: "The connection to Codex has closed."
        case .malformedMessage(let reason): "Invalid Codex message: \(reason)"
        case .invalidResponse(let reason): "Invalid Codex response: \(reason)"
        case .serverError(_, let message): message
        case .unsupportedServerRequest(let method): "Codex requested an unsupported operation: \(method)"
        case .responseNotDelivered(let detail): "A response to Codex could not be delivered: \(detail)"
        }
    }
}

public struct JSONRPCErrorObject: Codable, Equatable, Sendable {
    public var code: Int
    public var message: String
    public var data: JSONValue?

    public init(code: Int, message: String, data: JSONValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }
}

/// 計画的なホスト更新で運ぶ、`JSONRPCClient`の状態（ADR 0233）。
public struct JSONRPCHandoverState: Codable, Equatable, Sendable {
    public var nextRequestID: Int
    /// 確定点の時点で未応答のサーバ要求（承認・質問）の原文。受信順。
    public var pendingServerRequests: [Data]

    public init(nextRequestID: Int, pendingServerRequests: [Data]) {
        self.nextRequestID = nextRequestID
        self.pendingServerRequests = pendingServerRequests
    }
}

public enum ServerNotification: Equatable, Sendable {
    case agentMessageDelta(AgentMessageDeltaNotification)
    case reasoningSummaryTextDelta(ReasoningSummaryTextDeltaNotification)
    case commandExecutionOutputDelta(CommandExecutionOutputDeltaNotification)
    case fileChangePatchUpdated(FileChangePatchUpdatedNotification)
    case itemStarted(ItemStartedNotification)
    case itemCompleted(ItemCompletedNotification)
    case turnStarted(TurnLifecycleNotification)
    case turnCompleted(TurnLifecycleNotification)
    case turnInterrupted(TurnInterruptedNotification)
    case turnPlanUpdated(TurnPlanUpdatedNotification)
    case skillsChanged(SkillsChangedNotification)
    case threadTokenUsageUpdated(ThreadTokenUsageUpdatedNotification)
    case threadStatusChanged(ThreadStatusChangedNotification)
    case threadSettingsUpdated(ThreadSettingsUpdatedNotification)
    case error(ErrorNotification)
    case warning(WarningNotification)
    /// 計画的なホスト更新（ADR 0233）のフェンス。通知の流れの順序を保って、各層が「ここまで処理した」時点を知る。
    case handoverFence(UUID)
    case unknown(method: String, params: JSONValue?)
}

public enum ServerRequest: Equatable, Sendable {
    public static let userInputRequestMethod = "item/tool/requestUserInput"

    case commandExecutionApproval(CommandExecutionApprovalRequest)
    case fileChangeApproval(FileChangeApprovalRequest)
    case permissionsApproval(PermissionsApprovalRequest)
    /// モデルからユーザーへの質問（承認ではない）。task-0 で公開面を凍結し task-1 がデコードを実装する。
    case userInputRequest(ToolRequestUserInputRequest)
    case unknown(method: String, params: JSONValue?)

    public var method: String {
        switch self {
        case .commandExecutionApproval:
            return "item/commandExecution/requestApproval"
        case .fileChangeApproval:
            return "item/fileChange/requestApproval"
        case .permissionsApproval:
            return "item/permissions/requestApproval"
        case .userInputRequest:
            return Self.userInputRequestMethod
        case .unknown(let method, _):
            return method
        }
    }
}

public actor JSONRPCClient {
    public typealias ServerRequestHandler = @Sendable (ServerRequest) async throws -> JSONValue

    private struct PendingRequest: Sendable {
        let continuation: CheckedContinuation<JSONValue, Error>
    }

    private let transport: any AppServerTransport
    private let encoder = JSONEncoder.appServer
    private let decoder = JSONDecoder.appServer
    private var nextRequestID = 1
    private var pending: [Int: PendingRequest] = [:]
    private var receiveTask: Task<Void, Never>?
    private var serverRequestHandler: ServerRequestHandler
    /// 未応答のサーバ要求の原文（ADR 0233）。受信ループで同期的に記録し、応答の書き込みが終わったら消す。
    private enum ServerRequestState: Sendable { case pending, responding }
    private struct ServerRequestRecord: Sendable {
        let line: Data
        let order: Int
        var state: ServerRequestState
        /// 確実に未送信のまま失敗した応答（確定点の準備で送信が止まっていた等）。中止されたら送り直す。
        var undelivered: JSONRPCResponseMessage?
    }
    private var serverRequests: [RequestID: ServerRequestRecord] = [:]
    private var nextServerRequestOrder = 0
    /// 計画的更新で手放した。以後の入力の途切れを終了として扱わず、ストリームも閉じない。
    private var detached = false

    private let notificationContinuation: AsyncStream<ServerNotification>.Continuation
    public let notifications: AsyncStream<ServerNotification>
    private let errorContinuation: AsyncStream<JSONRPCClientError>.Continuation
    public let errors: AsyncStream<JSONRPCClientError>

    public init(
        transport: any AppServerTransport,
        serverRequestHandler: ServerRequestHandler? = nil
    ) {
        self.transport = transport
        self.serverRequestHandler = serverRequestHandler ?? { request in
            throw JSONRPCClientError.unsupportedServerRequest(request.method)
        }

        var notificationContinuation: AsyncStream<ServerNotification>.Continuation?
        self.notifications = AsyncStream { notificationContinuation = $0 }
        self.notificationContinuation = notificationContinuation!

        var errorContinuation: AsyncStream<JSONRPCClientError>.Continuation?
        self.errors = AsyncStream { errorContinuation = $0 }
        self.errorContinuation = errorContinuation!
    }

    deinit {
        receiveTask?.cancel()
        notificationContinuation.finish()
        errorContinuation.finish()
    }

    /// holder経由の子なら、そのトランスポート（計画的更新の対象かの判定と、配送の停止・確認に使う）。
    public nonisolated var holderTransport: HolderTransport? { transport as? HolderTransport }

    public func start() {
        guard receiveTask == nil else { return }
        let lines = transport.receivedLines
        receiveTask = Task { [weak self] in
            for await line in lines {
                await self?.handle(line: line)
            }
            guard await self?.isDetached() == false else { return }
            await self?.failAllPending(JSONRPCClientError.transportClosed)
            await self?.finishStreams()
        }
    }

    private func isDetached() -> Bool { detached }

    public func setServerRequestHandler(_ handler: @escaping ServerRequestHandler) {
        self.serverRequestHandler = handler
    }

    public func request<Params: Encodable & Sendable, Response: Decodable & Sendable>(
        method: String,
        params: Params,
        responseType: Response.Type = Response.self
    ) async throws -> Response {
        let result = try await requestJSON(method: method, params: encodeToJSONValue(params))
        return try decodeFromJSONValue(result, as: Response.self)
    }

    public func requestJSON(method: String, params: JSONValue) async throws -> JSONValue {
        let id = nextRequestID
        nextRequestID += 1

        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = PendingRequest(continuation: continuation)
            Task {
                do {
                    try await sendRequest(id: id, method: method, params: params)
                } catch {
                    resumePending(id: id, result: .failure(error))
                }
            }
        }
    }

    public func transportTerminationStatus() async -> Int32? {
        await transport.terminationStatus()
    }

    public func transportStderrTail() async -> String? {
        await transport.stderrTail()
    }

    public func close() async {
        receiveTask?.cancel()
        await transport.close()
        failAllPending(JSONRPCClientError.transportClosed)
        finishStreams()
    }

    // MARK: - 計画的なホスト更新（ADR 0233）

    /// 更新できない理由。nilなら可。クライアントからの未応答リクエストと、応答の書き込み中のサーバ要求は運べない。
    public func handoverGateReason() -> String? {
        if !pending.isEmpty { return "Codexへの応答待ちのリクエストがあります" }
        if serverRequests.values.contains(where: { $0.state == .responding }) { return "承認・質問への応答を送信中です" }
        return nil
    }

    public func captureHandoverState() -> JSONRPCHandoverState {
        let lines = serverRequests.values.filter { $0.state == .pending }.sorted { $0.order < $1.order }.map(\.line)
        return JSONRPCHandoverState(nextRequestID: nextRequestID, pendingServerRequests: lines)
    }

    /// 引き継ぎ側: 要求IDを続きの番号から始める。受信を始める前に呼ぶ。
    public func applyHandoverState(_ state: JSONRPCHandoverState) {
        nextRequestID = max(nextRequestID, state.nextRequestID)
    }

    /// 引き継ぎ側: 未応答だった要求の原文を、通常の受信経路へ再投入する（応答は新ホストが同じIDで一度だけ返す）。
    public func reinjectServerRequests(_ lines: [Data]) {
        for line in lines { handle(line: line) }
    }

    public func emitHandoverFence(_ id: UUID) {
        notificationContinuation.yield(.handoverFence(id))
    }

    /// 受信を止める。`transport.close()`は呼ばない（子は新ホストが引き継ぐ）。ストリームも閉じない。
    public func detachForHandover() {
        detached = true
        receiveTask?.cancel()
        receiveTask = nil
    }

    private func sendRequest(id: Int, method: String, params: JSONValue) async throws {
        let message = JSONRPCRequestMessage(id: .int(id), method: method, params: params)
        var data = try encoder.encode(message)
        data.append(0x0A)
        try await transport.send(data)
    }

    private func handle(line: Data) {
        do {
            let raw = try decoder.decode(RawJSONRPCMessage.self, from: line)
            if raw.method != nil, raw.id != nil {
                // server→client リクエスト（承認）はハンドラが長くブロックしうる。受信ループ内で
                // await すると後続の response/notification が全て停止する（I10 deadlock）。
                // Task 化してループを解放する。response はここでは処理せず順序を保つ。
                let request = raw
                if let id = raw.id {
                    serverRequests[id] = ServerRequestRecord(line: line, order: nextServerRequestOrder, state: .pending)
                    nextServerRequestOrder += 1
                }
                Task { [weak self] in
                    await self?.handleServerRequest(request)
                }
            } else if raw.method != nil {
                handleNotification(raw)
            } else if raw.id != nil {
                handleResponse(raw)
            } else {
                report(.invalidResponse("JSON-RPC message has neither id nor method"))
            }
        } catch {
            report(.malformedMessage(String(data: line, encoding: .utf8) ?? "<non-utf8>"))
        }
    }

    private func handleResponse(_ raw: RawJSONRPCMessage) {
        guard let id = raw.id?.intValue else {
            report(.invalidResponse("Response id is not an integer"))
            return
        }
        guard let pending = pending.removeValue(forKey: id) else { return }

        if let error = raw.error {
            pending.continuation.resume(
                throwing: JSONRPCClientError.serverError(code: error.code, message: error.message)
            )
            return
        }
        pending.continuation.resume(returning: raw.result ?? .null)
    }

    private func handleNotification(_ raw: RawJSONRPCMessage) {
        guard let method = raw.method else { return }
        notificationContinuation.yield(decodeNotification(method: method, params: raw.params))
    }

    private func handleServerRequest(_ raw: RawJSONRPCMessage) async {
        guard let id = raw.id, let method = raw.method else { return }
        let request = decodeServerRequest(method: method, params: raw.params)
        // 応答はハンドラの結果で1つだけ決め、送るのは1回だけ。送信に失敗した・結果不明のときに
        // 同じIDへ別の応答（エラー応答）を送り直すと、二重応答になる（ADR 0233）。
        let response: JSONRPCResponseMessage
        do {
            response = JSONRPCResponseMessage(id: id, result: try await serverRequestHandler(request), error: nil)
        } catch JSONRPCClientError.unsupportedServerRequest {
            response = JSONRPCResponseMessage(
                id: id, result: nil,
                error: JSONRPCErrorObject(code: -32601, message: "Unsupported server request: \(request.method)"))
        } catch {
            response = JSONRPCResponseMessage(
                id: id, result: nil, error: JSONRPCErrorObject(code: -32000, message: String(describing: error)))
        }
        serverRequests[id]?.state = .responding
        await deliver(response, id: id, method: method)
    }

    /// 応答を1回だけ送る。確実に未送信の失敗（送信が止まっている）なら、記録を`.pending`へ戻して応答を保持する
    /// （確定点に載せて新ホストで再提示するか、中止後に送り直す）。結果不明・書き込み失敗は、二重応答を避けるため再送も再提示もしない。
    private func deliver(_ response: JSONRPCResponseMessage, id: RequestID, method: String) async {
        do {
            try await send(response)
            serverRequests.removeValue(forKey: id)
        } catch {
            if Self.isCertainlyUnsent(error), serverRequests[id] != nil {
                serverRequests[id]?.state = .pending
                serverRequests[id]?.undelivered = response
            } else {
                serverRequests.removeValue(forKey: id)
            }
            report(.responseNotDelivered("\(method): \(error)"))
        }
    }

    private static func isCertainlyUnsent(_ error: Error) -> Bool {
        guard let holder = error as? HolderError else { return false }
        return holder == .handoverInProgress || holder == .notWriter
    }

    /// 更新が中止された。確実に未送信だった応答を、同じIDで送り直す（利用者の答えを失わない）。
    public func resendUndeliveredResponses() async {
        let targets = serverRequests.filter { $0.value.state == .pending && $0.value.undelivered != nil }
            .sorted { $0.value.order < $1.value.order }
        for (id, record) in targets {
            guard let response = record.undelivered else { continue }
            serverRequests[id]?.state = .responding
            serverRequests[id]?.undelivered = nil
            await deliver(response, id: id, method: "resend")
        }
    }

    private func send(_ message: JSONRPCResponseMessage) async throws {
        var data = try encoder.encode(message)
        data.append(0x0A)
        try await transport.send(data)
    }

    private func resumePending(id: Int, result: Result<JSONValue, Error>) {
        guard let pending = pending.removeValue(forKey: id) else { return }
        switch result {
        case .success(let value):
            pending.continuation.resume(returning: value)
        case .failure(let error):
            pending.continuation.resume(throwing: error)
        }
    }

    private func failAllPending(_ error: Error) {
        let requests = pending
        pending.removeAll()
        for request in requests.values {
            request.continuation.resume(throwing: error)
        }
    }

    private func finishStreams() {
        notificationContinuation.finish()
        errorContinuation.finish()
    }

    private func report(_ error: JSONRPCClientError) {
        errorContinuation.yield(error)
    }

    private func decodeNotification(method: String, params: JSONValue?) -> ServerNotification {
        switch method {
        case "item/agentMessage/delta":
            return decode(params, as: AgentMessageDeltaNotification.self).map(ServerNotification.agentMessageDelta)
                ?? .unknown(method: method, params: params)
        case "item/reasoning/summaryTextDelta":
            return decode(params, as: ReasoningSummaryTextDeltaNotification.self).map(ServerNotification.reasoningSummaryTextDelta)
                ?? .unknown(method: method, params: params)
        case "item/commandExecution/outputDelta":
            return decode(params, as: CommandExecutionOutputDeltaNotification.self).map(ServerNotification.commandExecutionOutputDelta)
                ?? .unknown(method: method, params: params)
        case "item/fileChange/patchUpdated":
            return decode(params, as: FileChangePatchUpdatedNotification.self).map(ServerNotification.fileChangePatchUpdated)
                ?? .unknown(method: method, params: params)
        case "item/started":
            return decode(params, as: ItemStartedNotification.self).map(ServerNotification.itemStarted)
                ?? .unknown(method: method, params: params)
        case "item/completed":
            return decode(params, as: ItemCompletedNotification.self).map(ServerNotification.itemCompleted)
                ?? .unknown(method: method, params: params)
        case "turn/started":
            return decode(params, as: TurnLifecycleNotification.self).map(ServerNotification.turnStarted)
                ?? .unknown(method: method, params: params)
        case "turn/completed":
            return decode(params, as: TurnLifecycleNotification.self).map(ServerNotification.turnCompleted)
                ?? .unknown(method: method, params: params)
        case "turn/interrupted":
            // `turn/interrupted` was removed from the current app-server schema.
            // Keep the raw notification available for diagnostics, but never turn it
            // into a completion event.  The authoritative stop signal is
            // `turn/completed` with an interrupted turn status.
            return .unknown(method: method, params: params)
        case "turn/plan/updated":
            return decode(params, as: TurnPlanUpdatedNotification.self).map(ServerNotification.turnPlanUpdated)
                ?? .unknown(method: method, params: params)
        case "skills/changed":
            return decode(params, as: SkillsChangedNotification.self).map(ServerNotification.skillsChanged)
                ?? .unknown(method: method, params: params)
        case "thread/tokenUsage/updated":
            return decode(params, as: ThreadTokenUsageUpdatedNotification.self).map(ServerNotification.threadTokenUsageUpdated)
                ?? .unknown(method: method, params: params)
        case "thread/status/changed":
            return decode(params, as: ThreadStatusChangedNotification.self).map(ServerNotification.threadStatusChanged)
                ?? .unknown(method: method, params: params)
        case "thread/settings/updated":
            return decode(params, as: ThreadSettingsUpdatedNotification.self).map(ServerNotification.threadSettingsUpdated)
                ?? .unknown(method: method, params: params)
        case "error":
            return decode(params, as: ErrorNotification.self).map(ServerNotification.error)
                ?? .unknown(method: method, params: params)
        case "warning":
            return decode(params, as: WarningNotification.self).map(ServerNotification.warning)
                ?? .unknown(method: method, params: params)
        default:
            return .unknown(method: method, params: params)
        }
    }

    private func decodeServerRequest(method: String, params: JSONValue?) -> ServerRequest {
        switch method {
        case "item/commandExecution/requestApproval":
            return decode(params, as: CommandExecutionApprovalRequest.self).map(ServerRequest.commandExecutionApproval)
                ?? .unknown(method: method, params: params)
        case "item/fileChange/requestApproval":
            return decode(params, as: FileChangeApprovalRequest.self).map(ServerRequest.fileChangeApproval)
                ?? .unknown(method: method, params: params)
        case "item/permissions/requestApproval":
            return decode(params, as: PermissionsApprovalRequest.self).map(ServerRequest.permissionsApproval)
                ?? .unknown(method: method, params: params)
        case ServerRequest.userInputRequestMethod:
            return decode(params, as: ToolRequestUserInputRequest.self).map(ServerRequest.userInputRequest)
                ?? .unknown(method: method, params: params)
        default:
            return .unknown(method: method, params: params)
        }
    }

    private func decode<T: Decodable & Sendable>(_ params: JSONValue?, as type: T.Type) -> T? {
        guard let params else { return nil }
        return try? decodeFromJSONValue(params, as: T.self)
    }
}

public enum RequestID: Codable, Hashable, Sendable {
    case int(Int)
    case string(String)

    public var intValue: Int? {
        guard case .int(let value) = self else { return nil }
        return value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        }
    }
}

private struct RawJSONRPCMessage: Codable, Sendable {
    var id: RequestID?
    var method: String?
    var params: JSONValue?
    var result: JSONValue?
    var error: JSONRPCErrorObject?
}

private struct JSONRPCRequestMessage: Codable, Sendable {
    var jsonrpc = "2.0"
    var id: RequestID
    var method: String
    var params: JSONValue
}

private struct JSONRPCResponseMessage: Codable, Sendable {
    var jsonrpc = "2.0"
    var id: RequestID
    var result: JSONValue?
    var error: JSONRPCErrorObject?
}
