import Foundation
import PhloxCore

/// Mac（Phlox プロキシ）への HTTP クライアント（E3-1）。`actor` でデータ競合を型保証する。
///
/// - `URLSession` を注入可能（テスト時に `URLProtocol` スタブを差し込める）。
/// - Bearer トークンは `TokenStore` から**都度**読み出す（メモリに永続キャッシュしない）。
/// - GET 系は指数バックオフで最大 `maxRetries` 回再試行。破壊的操作（spawn/send/remove/respond）は再試行しない。
/// - HTTP ステータス/トランスポート失敗を `PhloxError`（E3-2）へ正規化する。
public actor PhloxAPIClient: PhloxAPI {
    /// 接続先を**都度**解決する。固定 config 生成時は定数を返す。動的生成時は保存済み設定を
    /// 都度読むため、設定変更がアプリ再起動なしで反映される。
    private let configProvider: @Sendable () -> ConnectionConfig
    private let tokenStore: TokenStore
    private let session: URLSession
    private let maxRetries: Int
    private let retryBaseDelayNanos: UInt64

    /// 固定 config で生成（テスト・固定接続先用）。
    public init(
        config: ConnectionConfig,
        tokenStore: TokenStore,
        session: URLSession = .shared,
        maxRetries: Int = 3,
        retryBaseDelayNanos: UInt64 = 200_000_000
    ) {
        self.configProvider = { config }
        self.tokenStore = tokenStore
        self.session = session
        self.maxRetries = max(1, maxRetries)
        self.retryBaseDelayNanos = retryBaseDelayNanos
    }

    /// 接続先を都度解決する provider で生成（保存後に再起動なしで新 host/port を反映する）。
    public init(
        configProvider: @escaping @Sendable () -> ConnectionConfig,
        tokenStore: TokenStore,
        session: URLSession = .shared,
        maxRetries: Int = 3,
        retryBaseDelayNanos: UInt64 = 200_000_000
    ) {
        self.configProvider = configProvider
        self.tokenStore = tokenStore
        self.session = session
        self.maxRetries = max(1, maxRetries)
        self.retryBaseDelayNanos = retryBaseDelayNanos
    }

    // MARK: - PhloxAPI

    public func listSessions() async throws -> [Session] {
        let dto = try await getDecoded(SessionListDTO.self, path: "sessions")
        return dto.sessions.compactMap { $0.toDomain() }
    }

    public func spawn(_ request: SpawnRequest) async throws -> Session {
        let body = try encode(
            SpawnRequestDTO(kind: request.agent.rawValue, backend: "appServer", model: request.model)
        )
        // Mac は新規セッション id のみ返す（{id}）。name はサーバー採番で、一覧ポーリングが反映する。
        // spawn は二重作成を避けるため自動再試行しない（retry: false）。
        let dto = try await decoded(IDDTO.self, method: "POST", path: "sessions", bodyData: body, retry: false)
        return Session(
            id: dto.id,
            name: "",
            agent: request.agent,
            status: .starting,
            subtitle: request.workspace,
            updatedAt: Date()
        )
    }

    public func agentModels(kind: AgentKind) async throws -> AgentModels {
        try await getDecoded(AgentModels.self, path: "agents/\(kind.rawValue)/models")
    }

    public func cliUsage() async throws -> [CLIUsage] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let response = try await getDecoded(CLIUsageResponse.self, path: "usage", decoder: decoder)
        return response.agents
    }

    public func send(_ request: SendRequest) async throws -> SendResult {
        let body = try encode(SendRequestDTO(to: request.sessionID, text: request.text, images: request.images))
        _ = try await data(method: "POST", path: "send", bodyData: body, retry: false)
        return SendResult(accepted: true, message: nil)
    }

    public func interrupt(sessionID: String) async throws {
        _ = try await data(
            method: "POST",
            path: Self.sessionsPath(sessionID: sessionID, suffix: "interrupt"),
            bodyData: nil,
            retry: false
        )
    }

    public func subAgents(sessionID: String) async throws -> [SubAgentSummary] {
        let dto = try await getDecoded(
            SubAgentsListDTO.self,
            path: Self.sessionsPath(sessionID: sessionID, suffix: "subagents")
        )
        return dto.subAgents.map { $0.toDomain() }
    }

    public func subAgentMessages(sessionID: String, subAgentID: String) async throws -> [ChatMessage] {
        let encodedSubAgentID = Self.percentEncodedPathSegment(subAgentID)
        let dto = try await getDecoded(
            ChatMessagesDTO.self,
            path: Self.sessionsPath(
                sessionID: sessionID,
                suffix: "subagents/\(encodedSubAgentID)/messages"
            )
        )
        return dto.messages.compactMap { $0.toDomain() }
    }

    public func usage(sessionID: String) async throws -> TurnUsage? {
        let dto = try await getDecoded(
            UsageDTO.self,
            path: Self.sessionsPath(sessionID: sessionID, suffix: "usage")
        )
        return dto.turn?.toDomain()
    }

    public func messagesDelta(sessionID: String, since: String?, wait: Int?) async throws -> MessagesDelta {
        var queryItems: [URLQueryItem] = []
        if let since {
            queryItems.append(URLQueryItem(name: "since", value: since))
        }
        if let wait {
            queryItems.append(URLQueryItem(name: "wait", value: String(wait)))
        }
        let dto = try await getDecoded(
            MessagesDeltaDTO.self,
            path: Self.sessionsPath(sessionID: sessionID, suffix: "messages"),
            queryItems: queryItems.isEmpty ? nil : queryItems
        )
        return dto.toDomain(since: since)
    }

    public func output(sessionID: String) async throws -> String {
        let dto = try await getDecoded(
            OutputDTO.self,
            path: Self.sessionsPath(sessionID: sessionID, suffix: "output")
        )
        return dto.output
    }

    public func waitUntilReady(sessionID: String) async throws -> Bool {
        // Mac は ?timeout 既定10秒でロングポーリングし {ready} を返す。再試行はしない（待機の二重化を避ける）。
        let dto = try await decoded(
            ReadyDTO.self,
            method: "GET",
            path: Self.sessionsPath(sessionID: sessionID, suffix: "ready"),
            bodyData: nil,
            retry: false
        )
        return dto.ready
    }

    public func messages(sessionID: String) async throws -> [ChatMessage] {
        let dto = try await getDecoded(
            ChatMessagesDTO.self,
            path: Self.sessionsPath(sessionID: sessionID, suffix: "messages")
        )
        // 未知 type は toDomain が nil を返すため compactMap で除外（前方互換）。
        return dto.messages.compactMap { $0.toDomain() }
    }

    public func remove(sessionID: String) async throws {
        _ = try await data(
            method: "DELETE",
            path: Self.sessionsPath(sessionID: sessionID),
            bodyData: nil,
            retry: false
        )
    }

    public func rename(sessionID: String, name: String) async throws {
        let body = try encode(RenameSessionRequestDTO(name: name))
        _ = try await data(
            method: "PATCH",
            path: Self.sessionsPath(sessionID: sessionID),
            bodyData: body,
            retry: false
        )
    }

    public func approvals() async throws -> [Approval] {
        let dto = try await getDecoded(ApprovalListDTO.self, path: "approvals")
        return dto.approvals.compactMap { $0.toDomain() }
    }

    public func respond(approvalID: String, decision: ApprovalDecision) async throws {
        let body = try encode(RespondRequestDTO(decision: decision.rawValue))
        _ = try await data(
            method: "POST",
            path: "approvals/\(Self.percentEncodedPathSegment(approvalID))",
            bodyData: body,
            retry: false
        )
    }

    public func respondToQuestion(sessionID: String, requestId: String, answers: [String: [String]]) async throws {
        let body = try encode(RespondToQuestionRequestDTO(requestId: requestId, answers: answers))
        _ = try await data(
            method: "POST",
            path: Self.sessionsPath(
                sessionID: sessionID,
                suffix: PhloxQuestionWireContract.questionPathSuffix
            ),
            bodyData: body,
            retry: false
        )
    }

    public func sessionSettings(sessionID: String) async throws -> SessionModelSettings {
        let dto = try await getDecoded(
            SessionModelSettingsDTO.self,
            path: Self.sessionsPath(
                sessionID: sessionID,
                suffix: PhloxModelWireContract.settingsPathSuffix
            )
        )
        return dto.toDomain()
    }

    public func setModel(sessionID: String, model: String) async throws {
        let body = try encode(SetModelRequestDTO(model: model))
        _ = try await data(
            method: "POST",
            path: Self.sessionsPath(
                sessionID: sessionID,
                suffix: PhloxModelWireContract.modelPathSuffix
            ),
            bodyData: body,
            retry: false
        )
    }

    // MARK: - リクエスト共通

    private func getDecoded<T: Decodable>(
        _ type: T.Type,
        path: String,
        queryItems: [URLQueryItem]? = nil,
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> T {
        try await decoded(
            type,
            method: "GET",
            path: path,
            bodyData: nil,
            queryItems: queryItems,
            retry: true,
            decoder: decoder
        )
    }

    private func decoded<T: Decodable>(
        _ type: T.Type,
        method: String,
        path: String,
        bodyData: Data?,
        queryItems: [URLQueryItem]? = nil,
        retry: Bool,
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> T {
        let responseData = try await data(
            method: method,
            path: path,
            bodyData: bodyData,
            queryItems: queryItems,
            retry: retry
        )
        do {
            return try decoder.decode(T.self, from: responseData)
        } catch {
            throw PhloxError.decoding(WrappedError(error))
        }
    }

    private func data(
        method: String,
        path: String,
        bodyData: Data?,
        queryItems: [URLQueryItem]? = nil,
        retry: Bool
    ) async throws -> Data {
        var attempt = 0
        while true {
            do {
                return try await single(method: method, path: path, bodyData: bodyData, queryItems: queryItems)
            } catch let error as PhloxError {
                guard retry, Self.isRetryable(error), attempt < maxRetries - 1 else {
                    throw error
                }
                attempt += 1
                try? await Task.sleep(nanoseconds: Self.backoffNanos(base: retryBaseDelayNanos, attempt: attempt))
            }
        }
    }

    private func single(
        method: String,
        path: String,
        bodyData: Data?,
        queryItems: [URLQueryItem]? = nil
    ) async throws -> Data {
        let config = configProvider()
        var components = URLComponents()
        components.scheme = "http"
        components.host = config.host
        components.port = config.port
        components.percentEncodedPath = "/" + path
        if let queryItems, !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw PhloxError.transport(WrappedError(description: "invalid URL for path: \(path)"))
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        let token = (try? await tokenStore.load()) ?? nil
        if let token, HostTrustPolicy.allowsAuthorization(host: config.host) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let bodyData {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = bodyData
        }

        let responseData: Data
        let response: URLResponse
        do {
            (responseData, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw Self.mapTransport(urlError)
        } catch {
            throw PhloxError.transport(WrappedError(error))
        }

        guard let http = response as? HTTPURLResponse else {
            throw PhloxError.transport(WrappedError(description: "non-HTTP response"))
        }
        try Self.mapStatus(http, data: responseData)
        return responseData
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        do {
            return try JSONEncoder().encode(value)
        } catch {
            throw PhloxError.decoding(WrappedError(error))
        }
    }

    // MARK: - エラー正規化（テスト可能な純粋関数）

    static func mapTransport(_ error: URLError) -> PhloxError {
        switch error.code {
        case .timedOut, .cannotConnectToHost, .cannotFindHost, .notConnectedToInternet, .networkConnectionLost:
            return .unreachable
        default:
            return .transport(WrappedError(error))
        }
    }

    static func mapStatus(_ http: HTTPURLResponse, data: Data) throws {
        switch http.statusCode {
        case 200...299:
            return
        case 401:
            throw PhloxError.unauthorized
        case 404:
            throw PhloxError.notFound
        case 429:
            let retryAfter = Int(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 0
            throw PhloxError.rateLimited(retryAfter: retryAfter)
        case 422:
            let reason = (try? JSONDecoder().decode(ServerErrorDTO.self, from: data))?.reason
            throw PhloxError.spawnRejected(reason: reason ?? "リクエストが拒否されました")
        default:
            let message = (try? JSONDecoder().decode(ServerErrorDTO.self, from: data))?.message
            throw PhloxError.server(status: http.statusCode, message: message)
        }
    }

    static func isRetryable(_ error: PhloxError) -> Bool {
        switch error {
        case .unreachable, .transport:
            return true
        case .server(let status, _):
            return status >= 500
        default:
            return false
        }
    }

    static func backoffNanos(base: UInt64, attempt: Int) -> UInt64 {
        base << UInt64(max(0, attempt - 1))
    }

    /// パスセグメント用 percent-encoding（`/` 等をエスケープしサブエージェント id を安全に載せる）。
    static func percentEncodedPathSegment(_ segment: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        return segment.addingPercentEncoding(withAllowedCharacters: allowed) ?? segment
    }

    /// `sessions/{sessionID}` 以降のパスを組み立てる。sessionID は percent-encode 済みで載せる。
    private static func sessionsPath(sessionID: String, suffix: String? = nil) -> String {
        let encodedSessionID = percentEncodedPathSegment(sessionID)
        if let suffix {
            return "sessions/\(encodedSessionID)/\(suffix)"
        }
        return "sessions/\(encodedSessionID)"
    }
}

extension PhloxAPIClient: DeviceTokenRegistering {
    /// POST /device-tokens（契約 v1）。成否は HTTP ステータスのみで判定し（2xx=成功・body 非依存）、
    /// 破壊的操作と同じく自動再試行しない（リトライ戦略は PushRegistrationService の責務）。
    public func registerDeviceToken(_ registration: DeviceTokenRegistration) async throws {
        let body = try encode(registration)
        _ = try await data(method: "POST", path: "device-tokens", bodyData: body, retry: false)
    }
}

/// task-6 契約（凍結・PM 著）: モデル選択 API のワイヤ契約（macOS 側 `ControlModelWireContract` と
/// 一字一句一致させる単一の正）。`implemented` はクライアントメソッド
/// （sessionSettings / setModel）の実装完了と同時に true へ反転する（flag だけの反転は虚偽報告）。
public enum PhloxModelWireContract {
    /// GET sessions/{id}/settings → 200 {"selectedModel": String?, "availableModels": [{"id","displayName"}]}
    public static let settingsPathSuffix = "settings"
    /// POST sessions/{id}/model  body {"model": String} → 200 / 404 / 400
    public static let modelPathSuffix = "model"
    public static let selectedModelKey = "selectedModel"
    public static let availableModelsKey = "availableModels"
    public static let modelIDKey = "id"
    public static let modelDisplayNameKey = "displayName"
    public static let modelKey = "model"
    public static let implemented = true
}

/// task-0 契約（凍結・PM 著）: AskUserQuestion のワイヤ契約。
/// 定数は macOS 側 `ControlQuestionWireContract` と一字一句一致させる（パスの前置 `/` を除く）。
/// `implemented` は task-4（iOS 側配線）の実装完了と同時に true へ反転する
/// （flag だけの反転は虚偽報告として扱う）。
///
/// メッセージ側（GET sessions/{id}/messages の ChatMessageDTO）:
///   type == "userQuestion" のとき追加フィールド
///   {"requestId": String, "state": "pending"|"answered"|"expired",
///    "questions": [{"question","header","multiSelect","options":[{"label","description"?}]}],
///    "answers": {"<question文>": [String]}? }
/// 回答側:
///   POST sessions/{id}/question  body {"requestId": String, "answers": {"<question文>": [String]}}
///   → 200（受理）/ 404（セッション or pending 質問なし）/ 400（body 不正）
public enum PhloxQuestionWireContract {
    public static let messageType = "userQuestion"
    public static let questionPathSuffix = "question"
    public static let requestIdKey = "requestId"
    public static let stateKey = "state"
    public static let questionsKey = "questions"
    public static let answersKey = "answers"
    public static let questionKey = "question"
    public static let headerKey = "header"
    public static let multiSelectKey = "multiSelect"
    public static let optionsKey = "options"
    public static let optionLabelKey = "label"
    public static let optionDescriptionKey = "description"
    public static let statePending = "pending"
    public static let stateAnswered = "answered"
    public static let stateExpired = "expired"
    public static let implemented = true
}

/// セッション詳細のモデル選択 UI が依存する API 面（`PhloxAPI` プロトコル拡張は task-6 スコープ外のため別シーム）。
public protocol SessionModelSelecting: Sendable {
    func sessionSettings(sessionID: String) async throws -> SessionModelSettings
    func setModel(sessionID: String, model: String) async throws
}

extension PhloxAPIClient: SessionModelSelecting {}

private struct RenameSessionRequestDTO: Encodable {
    let name: String
}
