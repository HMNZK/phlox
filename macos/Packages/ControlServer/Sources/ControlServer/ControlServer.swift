import AgentDomain
import Foundation
import LocalHTTPServer
import Network

public enum ControlServerError: Error, Sendable {
    case listenerFailed(Error)
    case portUnavailable
    case alreadyStarted
}

public actor ControlServer {
    /// テスト用シーム: NWListener の生成を差し替えられるようにする(既定は実生成)。
    internal typealias MakeListener = LocalHTTPListener.MakeListener

    private let tokenStore: SessionTokenStore
    private let agentCatalog: AgentCatalog
    private let handler: @Sendable (ControlRequest) async -> ControlResponse
    private let makeListener: MakeListener

    private var listener: NWListener?
    private let connectionQueue = DispatchQueue(label: "ControlServer.connections")
    private var pendingSpawnRole: String?
    private var pendingSpawnModel: String?

    public init(
        tokenStore: SessionTokenStore,
        agentCatalog: AgentCatalog = .builtins,
        handler: @escaping @Sendable (ControlRequest) async -> ControlResponse
    ) {
        self.tokenStore = tokenStore
        self.agentCatalog = agentCatalog
        self.handler = handler
        self.makeListener = { try NWListener(using: $0) }
    }

    internal init(
        tokenStore: SessionTokenStore,
        agentCatalog: AgentCatalog = .builtins,
        handler: @escaping @Sendable (ControlRequest) async -> ControlResponse,
        makeListener: @escaping MakeListener
    ) {
        self.tokenStore = tokenStore
        self.agentCatalog = agentCatalog
        self.handler = handler
        self.makeListener = makeListener
    }

    public func start() async throws -> Int {
        try await start(preferredPort: 0)
    }

    /// 指定ポートでの起動を試みる。0 のときはランダムポートを使う（既存の start() と同等）。
    /// 指定ポートが使用中の場合はランダムポートにフォールバックする。
    public func start(preferredPort: UInt16) async throws -> Int {
        if listener != nil {
            throw ControlServerError.alreadyStarted
        }

        guard preferredPort != 0 else {
            return try await startListener(port: 0)
        }

        do {
            return try await startListener(port: preferredPort)
        } catch {
            return try await startListener(port: 0)
        }
    }

    private func startListener(port: UInt16) async throws -> Int {
        let listener: NWListener
        do {
            listener = try LocalHTTPListener.makeListener(port: port, make: makeListener)
        } catch {
            throw ControlServerError.listenerFailed(error)
        }

        self.listener = listener

        do {
            return try await LocalHTTPListener.startAndWaitUntilReady(
                listener,
                queue: connectionQueue
            ) { [weak self] connection in
                guard let self else {
                    connection.cancel()
                    return
                }
                connection.start(queue: self.connectionQueue)
                Task {
                    await self.handle(connection: connection)
                }
            }
        } catch {
            // 起動失敗時に listener を残すと以後の start が恒久的に alreadyStarted になる
            listener.cancel()
            self.listener = nil
            throw Self.startupError(from: error)
        }
    }

    /// 共通基盤のエラーを公開エラー型 ControlServerError へ写像する。
    private static func startupError(from error: Error) -> ControlServerError {
        switch error {
        case LocalHTTPListenerError.portUnavailable:
            return .portUnavailable
        case LocalHTTPListenerError.listenerFailed(let underlying):
            return .listenerFailed(underlying)
        default:
            return .listenerFailed(error)
        }
    }

    /// Control API の transport body 上限。契約5（/send images）の合計 8MiB（base64 で約 11MB）を
    /// 受信できるよう、既定の HTTPMessageParser.maxBodyLength（256KiB）よりこのサーバーだけ広げる。
    /// HookServer 等の他サーバーは既定値のまま（DoS 面を広げない）。
    public static let maxRequestBodyLength = 16 * 1024 * 1024

    private func handle(connection: NWConnection) async {
        do {
            try await LocalHTTPConnection.waitUntilReady(connection)
        } catch {
            connection.cancel()
            return
        }

        let request: HTTPRequest
        do {
            request = try await LocalHTTPConnection.receiveRequest(
                from: connection,
                maxBodyLength: Self.maxRequestBodyLength
            )
        } catch HTTPMessageParserError.payloadTooLarge {
            await send(connection: connection, response: .status(413))
            return
        } catch {
            await send(connection: connection, response: .status(400))
            return
        }

        guard let requester = await authenticate(headers: request.headers) else {
            await send(connection: connection, response: .status(401))
            return
        }

        let action: ControlRequest.Action
        switch route(request: request) {
        case .success(let routed):
            action = routed
        case .failure(let response):
            await send(connection: connection, response: response)
            return
        }

        let controlRequest = ControlRequest(requester: requester, action: action)
        let spawnRole = pendingSpawnRole
        pendingSpawnRole = nil
        let spawnModel = pendingSpawnModel
        pendingSpawnModel = nil
        let controlResponse: ControlResponse
        if case .spawn = action {
            controlResponse = await ControlSpawnContext.$role.withValue(spawnRole) {
                await ControlSpawnContext.$model.withValue(spawnModel) {
                    await handler(controlRequest)
                }
            }
        } else {
            controlResponse = await handler(controlRequest)
        }
        await send(connection: connection, response: controlResponse)
    }

    private func authenticate(headers: [String: String]) async -> SessionID? {
        guard let authorization = headers["authorization"] else {
            return nil
        }
        let prefix = "Bearer "
        guard authorization.hasPrefix(prefix) else {
            return nil
        }
        let token = String(authorization.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespaces)
        guard !token.isEmpty else {
            return nil
        }
        return await tokenStore.session(forToken: token)
    }

    private enum RouteResult {
        case success(ControlRequest.Action)
        case failure(ControlResponse)
    }

    private func route(request: HTTPRequest) -> RouteResult {
        switch (request.method, request.path) {
        case ("GET", "/sessions"):
            guard !request.hasQuery else {
                return .failure(.status(404))
            }
            return .success(.listSessions)

        case ("GET", "/usage"):
            guard !request.hasQuery else {
                return .failure(.status(404))
            }
            return .success(.cliUsage)

        case ("GET", "/approvals"):
            guard !request.hasQuery else {
                return .failure(.status(404))
            }
            return .success(.listApprovals)

        case ("POST", "/send"):
            guard !request.hasQuery else {
                return .failure(.status(404))
            }
            return parseSend(body: request.body)

        case ("POST", "/sessions"):
            guard !request.hasQuery else {
                return .failure(.status(404))
            }
            return parseSpawn(body: request.body)

        case ("POST", "/device-tokens"):
            guard !request.hasQuery else {
                return .failure(.status(404))
            }
            return parseDeviceToken(body: request.body)

        default:
            if request.method == "GET" {
                if let agentModelsResult = parseAgentModels(path: request.path, hasQuery: request.hasQuery) {
                    return agentModelsResult
                }
                return routeSessionGET(path: request.path, query: request.query)
            }
            if request.method == "POST" {
                if let modelResult = parseModelChange(
                    path: request.path,
                    hasQuery: request.hasQuery,
                    body: request.body
                ) {
                    return modelResult
                }
                if let interruptResult = parseInterrupt(path: request.path, hasQuery: request.hasQuery) {
                    return interruptResult
                }
                return parseApprovalResponse(path: request.path, hasQuery: request.hasQuery, body: request.body)
            }
            if request.method == "PATCH" {
                return parseRename(path: request.path, hasQuery: request.hasQuery, body: request.body)
            }
            if request.method == "DELETE" {
                return parseRemove(path: request.path, hasQuery: request.hasQuery)
            }
            return .failure(.status(404))
        }
    }

    private static let maxSendImageCount = 4
    private static let maxSendBytesPerImage = 4 * 1024 * 1024
    private static let maxSendTotalImageBytes = 8 * 1024 * 1024

    private func parseSend(body: Data) -> RouteResult {
        struct ImageWire: Decodable {
            let mediaType: String
            let dataBase64: String
        }

        struct SendBody: Decodable {
            let to: String
            let text: String
            let submit: Bool?
            let inReplyTo: String?
            let images: [ImageWire]?
        }

        guard let payload = try? JSONDecoder().decode(SendBody.self, from: body) else {
            return .failure(.status(400))
        }

        let recipient: Recipient
        if let uuid = UUID(uuidString: payload.to) {
            recipient = .id(SessionID(rawValue: uuid))
        } else {
            recipient = .name(payload.to)
        }

        let inReplyTo: UUID?
        if let rawInReplyTo = payload.inReplyTo {
            guard let uuid = UUID(uuidString: rawInReplyTo) else {
                return .failure(.status(400))
            }
            inReplyTo = uuid
        } else {
            inReplyTo = nil
        }

        var images: [ControlImageAttachment] = []
        if let wireImages = payload.images, !wireImages.isEmpty {
            if wireImages.count > Self.maxSendImageCount {
                return .failure(.json(413, ErrorDTO(error: "attachment too large")))
            }

            var totalBytes = 0
            for wire in wireImages {
                guard let data = Data(base64Encoded: wire.dataBase64) else {
                    return .failure(.status(400))
                }
                if data.count > Self.maxSendBytesPerImage {
                    return .failure(.json(413, ErrorDTO(error: "attachment too large")))
                }
                totalBytes += data.count
                images.append(ControlImageAttachment(mediaType: wire.mediaType, data: data))
            }

            if totalBytes > Self.maxSendTotalImageBytes {
                return .failure(.json(413, ErrorDTO(error: "attachment too large")))
            }
        }

        return .success(.sendText(
            to: recipient,
            text: payload.text,
            submit: payload.submit ?? true,
            inReplyTo: inReplyTo,
            images: images
        ))
    }

    private func parseDeviceToken(body: Data) -> RouteResult {
        guard let registration = try? JSONDecoder().decode(DeviceTokenRegistration.self, from: body) else {
            return .failure(.status(400))
        }
        return .success(.registerDeviceToken(registration: registration))
    }

    private func parseSpawn(body: Data) -> RouteResult {
        struct SpawnBody: Decodable {
            let kind: String
            // 省略時は既定 .pty。モバイルは "appServer" を送る。
            let backend: String?
            let workingDirectory: String?
            let role: String?
            let model: String?
        }

        guard let payload = try? JSONDecoder().decode(SpawnBody.self, from: body),
              !payload.kind.isEmpty
        else {
            return .failure(.status(400))
        }

        let role: String?
        if let rawRole = payload.role {
            let trimmed = rawRole.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return .failure(.json(400, ErrorDTO(error: "invalid role")))
            }
            guard trimmed.count <= Self.maxSpawnRoleLength else {
                return .failure(.json(400, ErrorDTO(error: "invalid role")))
            }
            guard !Self.containsRejectedControlCharacters(trimmed) else {
                return .failure(.json(400, ErrorDTO(error: "invalid role")))
            }
            role = trimmed
        } else {
            role = nil
        }

        let backend: SessionBackend
        if let rawBackend = payload.backend {
            guard let parsed = SessionBackend(rawValue: rawBackend) else {
                return .failure(.json(400, ErrorDTO(error: "unknown backend: \(rawBackend)")))
            }
            backend = parsed
        } else if role != nil, AgentKind(rawValue: payload.kind) == .claudeCode {
            // role 付き claudeCode spawn ＝ アゴラ討論の招集。討論のリレーは appServer の
            // transcript 観測が前提のため、明示指定が無ければチャット（appServer）で起動する。
            backend = .appServer
        } else {
            backend = .pty
        }

        if let kind = AgentKind(rawValue: payload.kind) {
            pendingSpawnRole = role
            pendingSpawnModel = Self.normalizedSpawnModel(payload.model, for: kind)
            return .success(.spawn(ref: .builtin(kind), backend: backend, workingDirectory: payload.workingDirectory))
        }

        let ref = AgentRef.custom(payload.kind)
        if agentCatalog.descriptor(for: ref) != nil {
            pendingSpawnRole = role
            pendingSpawnModel = nil
            return .success(.spawn(ref: ref, backend: backend, workingDirectory: payload.workingDirectory))
        }

        return .failure(.json(400, ErrorDTO(error: "unknown agent kind: \(payload.kind)")))
    }

    private static let maxSpawnRoleLength = 64
    private static let maxSpawnModelLength = 128

    private static func normalizedSpawnModel(_ model: String?, for kind: AgentKind) -> String? {
        guard let model else { return nil }
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count <= maxSpawnModelLength,
              !containsRejectedControlCharacters(trimmed)
        else {
            return nil
        }
        return AgentModelCatalog.models(for: kind).contains(where: { $0.id == trimmed })
            ? trimmed
            : nil
    }

    private static func containsRejectedControlCharacters(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            let value = scalar.value
            if scalar == "\r" || scalar == "\n" || scalar == "\u{1B}" {
                return true
            }
            if value == 0x7F {
                return true
            }
            if value < 0x20, scalar != "\t" {
                return true
            }
        }
        return false
    }

    private func routeSessionGET(path: String, query: [String: String]) -> RouteResult {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)

        if components.count == 6,
           components[0] == "",
           components[1] == "sessions",
           components[3] == "subagents",
           components[5] == "messages" {
            guard let sessionID = parseSessionID(from: components[2]) else {
                return .failure(.status(400))
            }
            let rawSubAgentID = String(components[4])
            let decodedSubAgentID = rawSubAgentID.removingPercentEncoding ?? rawSubAgentID
            guard !decodedSubAgentID.isEmpty else {
                return .failure(.status(404))
            }
            return .success(.subAgentMessages(id: sessionID, subAgentID: decodedSubAgentID))
        }

        guard components.count == 4,
              components[0] == "",
              components[1] == "sessions"
        else {
            return .failure(.status(404))
        }

        guard let sessionID = parseSessionID(from: components[2]) else {
            return .failure(.status(400))
        }

        if "/\(components[3])" == ControlModelWireContract.settingsPathSuffix {
            guard query.isEmpty else {
                return .failure(.status(404))
            }
            return .success(.sessionSettings(id: sessionID))
        }

        switch components[3] {
        case "output":
            return parseOutput(sessionID: sessionID, query: query)
        case "messages":
            return parseMessages(sessionID: sessionID, query: query)
        case "ready":
            return parseReady(sessionID: sessionID, query: query)
        case "wait":
            return parseWait(sessionID: sessionID, query: query)
        case "subagents":
            return .success(.subAgents(id: sessionID))
        case "usage":
            return .success(.usage(id: sessionID))
        default:
            return .failure(.status(404))
        }
    }

    private func parseAgentModels(path: String, hasQuery: Bool) -> RouteResult? {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 4,
              components[0] == "",
              components[1] == "agents",
              components[3] == "models"
        else {
            return nil
        }
        guard !hasQuery else {
            return .failure(.status(404))
        }
        guard let kind = AgentKind(rawValue: String(components[2])) else {
            return .failure(.status(404))
        }
        return .success(.agentModels(kind: kind))
    }

    private func parseModelChange(path: String, hasQuery: Bool, body: Data) -> RouteResult? {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 4,
              components[0] == "",
              components[1] == "sessions",
              "/\(components[3])" == ControlModelWireContract.modelPathSuffix
        else {
            return nil
        }
        if hasQuery {
            return .failure(.status(404))
        }
        guard let sessionID = parseSessionID(from: components[2]) else {
            return .failure(.status(400))
        }

        struct ModelBody: Decodable {
            let model: String
        }
        guard let payload = try? JSONDecoder().decode(ModelBody.self, from: body) else {
            return .failure(.status(400))
        }
        let model = payload.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            return .failure(.status(400))
        }
        return .success(.setModel(id: sessionID, model: model))
    }

    private func parseInterrupt(path: String, hasQuery: Bool) -> RouteResult? {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 4,
              components[0] == "",
              components[1] == "sessions",
              components[3] == "interrupt"
        else {
            return nil
        }
        if hasQuery {
            return .failure(.status(404))
        }
        guard let sessionID = parseSessionID(from: components[2]) else {
            return .failure(.status(400))
        }
        return .success(.interrupt(id: sessionID))
    }

    /// パスセグメントから percent decode + UUID 変換を行い SessionID を返す。
    private func parseSessionID(from segment: some StringProtocol) -> SessionID? {
        let raw = String(segment)
        guard !raw.isEmpty else { return nil }
        let decoded = raw.removingPercentEncoding ?? raw
        guard let uuid = UUID(uuidString: decoded) else { return nil }
        return SessionID(rawValue: uuid)
    }

    /// 契約6: `?since=<cursor>`（空文字は 400）・`?wait=<seconds>`（非整数は 400、値はハンドラで
    /// 1〜25 秒に clamp）を解析する。両方省略なら従来と同一挙動（＋cursor 付与はハンドラ側）。
    private func parseMessages(sessionID: SessionID, query: [String: String]) -> RouteResult {
        let since: String?
        if let rawSince = query["since"] {
            guard !rawSince.isEmpty else {
                return .failure(.status(400))
            }
            since = rawSince
        } else {
            since = nil
        }

        let wait: Int?
        if let rawWait = query["wait"] {
            guard let parsed = Int(rawWait) else {
                return .failure(.status(400))
            }
            wait = parsed
        } else {
            wait = nil
        }

        return .success(.messages(id: sessionID, since: since, wait: wait))
    }

    private func parseOutput(sessionID: SessionID, query: [String: String]) -> RouteResult {
        let mode: OutputMode
        if let rawMode = query["mode"] {
            guard let parsedMode = OutputMode(rawValue: rawMode) else {
                return .failure(.status(400))
            }
            mode = parsedMode
        } else {
            mode = .screen
        }

        return .success(.output(id: sessionID, mode: mode))
    }

    private func parseReady(sessionID: SessionID, query: [String: String]) -> RouteResult {
        let timeoutSeconds: Int
        if let rawTimeout = query["timeout"] {
            guard let parsed = Int(rawTimeout), parsed > 0 else {
                return .failure(.status(400))
            }
            timeoutSeconds = parsed
        } else {
            timeoutSeconds = 10
        }

        return .success(.waitReady(id: sessionID, timeoutSeconds: timeoutSeconds))
    }

    private func parseWait(sessionID: SessionID, query: [String: String]) -> RouteResult {
        guard let rawTimeout = query["timeout"],
              let timeoutSeconds = Int(rawTimeout),
              timeoutSeconds > 0
        else {
            return .failure(.status(400))
        }

        let sentinel: String?
        if let rawSentinel = query["sentinel"] {
            guard !rawSentinel.isEmpty else {
                return .failure(.status(400))
            }
            sentinel = rawSentinel
        } else {
            sentinel = nil
        }

        return .success(.wait(
            id: sessionID,
            timeoutSeconds: timeoutSeconds,
            sentinel: sentinel
        ))
    }

    private func parseRemove(path: String, hasQuery: Bool) -> RouteResult {
        if hasQuery {
            return .failure(.status(400))
        }

        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 3,
              components[0] == "",
              components[1] == "sessions"
        else {
            return .failure(.status(400))
        }

        guard let sessionID = parseSessionID(from: components[2]) else {
            return .failure(.status(400))
        }

        return .success(.remove(id: sessionID))
    }

    private func parseApprovalResponse(path: String, hasQuery: Bool, body: Data) -> RouteResult {
        struct DecisionBody: Decodable {
            let decision: String
        }

        if hasQuery {
            return .failure(.status(400))
        }

        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        // path == "/approvals/{id}" → components: ["", "approvals", "{id}"]
        guard components.count == 3,
              components[0] == "",
              components[1] == "approvals"
        else {
            return .failure(.status(404))
        }

        let approvalID = String(components[2])
        guard !approvalID.isEmpty else {
            return .failure(.status(404))
        }

        guard let payload = try? JSONDecoder().decode(DecisionBody.self, from: body),
              let decision = ApprovalDecision(rawValue: payload.decision)
        else {
            return .failure(.status(400))
        }

        return .success(.respondApproval(id: approvalID, decision: decision))
    }

    private func parseRename(path: String, hasQuery: Bool, body: Data) -> RouteResult {
        struct RenameBody: Decodable {
            let name: String
        }

        if hasQuery {
            return .failure(.status(400))
        }

        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 3,
              components[0] == "",
              components[1] == "sessions"
        else {
            return .failure(.status(400))
        }

        guard let sessionID = parseSessionID(from: components[2]) else {
            return .failure(.status(400))
        }

        guard let payload = try? JSONDecoder().decode(RenameBody.self, from: body) else {
            return .failure(.status(400))
        }

        return .success(.rename(id: sessionID, name: payload.name))
    }

    private func send(connection: NWConnection, response: ControlResponse) async {
        let httpResponse = HTTPResponseBuilder.jsonResponse(
            statusCode: response.statusCode,
            body: response.body
        )
        await LocalHTTPConnection.sendAndClose(httpResponse, over: connection)
    }
}

/// spawn リクエストでパースした role をハンドラ層へ渡す TaskLocal（task-3）。
/// `ControlRequest.Action` の形を変えず凍結テストとの互換を保つ。
public enum ControlSpawnContext {
    @TaskLocal public static var role: String?
    @TaskLocal public static var model: String?
}

private struct ErrorDTO: Codable {
    let error: String
}
