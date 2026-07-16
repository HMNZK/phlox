import Foundation

public enum JSONRPCClientError: Error, Equatable, Sendable {
    case transportClosed
    case malformedMessage(String)
    case invalidResponse(String)
    case serverError(code: Int, message: String)
    case unsupportedServerRequest(String)
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
    case threadTokenUsageUpdated(ThreadTokenUsageUpdatedNotification)
    case threadStatusChanged(ThreadStatusChangedNotification)
    case threadSettingsUpdated(ThreadSettingsUpdatedNotification)
    case error(ErrorNotification)
    case warning(WarningNotification)
    case unknown(method: String, params: JSONValue?)
}

public enum ServerRequest: Equatable, Sendable {
    case commandExecutionApproval(CommandExecutionApprovalRequest)
    case fileChangeApproval(FileChangeApprovalRequest)
    case permissionsApproval(PermissionsApprovalRequest)
    case unknown(method: String, params: JSONValue?)

    public var method: String {
        switch self {
        case .commandExecutionApproval:
            return "item/commandExecution/requestApproval"
        case .fileChangeApproval:
            return "item/fileChange/requestApproval"
        case .permissionsApproval:
            return "item/permissions/requestApproval"
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

    public func start() {
        guard receiveTask == nil else { return }
        let lines = transport.receivedLines
        receiveTask = Task { [weak self] in
            for await line in lines {
                await self?.handle(line: line)
            }
            await self?.failAllPending(JSONRPCClientError.transportClosed)
            await self?.finishStreams()
        }
    }

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

    public func close() async {
        receiveTask?.cancel()
        await transport.close()
        failAllPending(JSONRPCClientError.transportClosed)
        finishStreams()
    }

    private func sendRequest(id: Int, method: String, params: JSONValue) async throws {
        let message = JSONRPCRequestMessage(id: .int(id), method: method, params: params)
        var data = try encoder.encode(message)
        data.append(0x0A)
        try await transport.send(data)
    }

    private func sendResponse(id: RequestID, result: JSONValue) async throws {
        let message = JSONRPCResponseMessage(id: id, result: result, error: nil)
        var data = try encoder.encode(message)
        data.append(0x0A)
        try await transport.send(data)
    }

    private func sendErrorResponse(id: RequestID, error: JSONRPCErrorObject) async throws {
        let message = JSONRPCResponseMessage(id: id, result: nil, error: error)
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
        do {
            let result = try await serverRequestHandler(request)
            try await sendResponse(id: id, result: result)
        } catch JSONRPCClientError.unsupportedServerRequest {
            try? await sendErrorResponse(
                id: id,
                error: JSONRPCErrorObject(code: -32601, message: "Unsupported server request: \(request.method)")
            )
        } catch {
            try? await sendErrorResponse(
                id: id,
                error: JSONRPCErrorObject(code: -32000, message: String(describing: error))
            )
        }
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
            return decode(params, as: TurnInterruptedNotification.self).map(ServerNotification.turnInterrupted)
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
        default:
            return .unknown(method: method, params: params)
        }
    }

    private func decode<T: Decodable & Sendable>(_ params: JSONValue?, as type: T.Type) -> T? {
        guard let params else { return nil }
        return try? decodeFromJSONValue(params, as: T.self)
    }
}

public enum RequestID: Codable, Equatable, Sendable {
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
