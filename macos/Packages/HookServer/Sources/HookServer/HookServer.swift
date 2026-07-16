import AgentDomain
import Foundation
import LocalHTTPServer
import Network

public enum HookServerError: Error, Sendable {
    case listenerFailed(Error)
    case portUnavailable
    case alreadyStarted
}

public actor HookServer: HookServerProtocol {
    private let eventContinuation: AsyncStream<(SessionID, HookEvent)>.Continuation
    public nonisolated let events: AsyncStream<(SessionID, HookEvent)>
    private let deliveryContinuation: AsyncStream<HookDelivery>.Continuation
    public nonisolated let deliveries: AsyncStream<HookDelivery>

    private var listener: NWListener?
    private let connectionQueue = DispatchQueue(label: "HookServer.connections")

    /// hook POST の認証に使う token↔session ストア。
    /// nil のときは認証を行わない（ライブラリ単体利用・既存テスト用）。本番は
    /// CompositionRoot が必ず注入し、`Authorization: Bearer <token>` を要求する。
    private let tokenStore: SessionTokenStore?

    public init(tokenStore: SessionTokenStore? = nil) {
        self.tokenStore = tokenStore
        let (stream, continuation) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        self.events = stream
        self.eventContinuation = continuation
        let (deliveryStream, deliveryContinuation) = AsyncStream<HookDelivery>.makeStream()
        self.deliveries = deliveryStream
        self.deliveryContinuation = deliveryContinuation
    }

    public func start() async throws -> Int {
        try await start(preferredPort: 0)
    }

    /// 指定ポートでの起動を試みる。0 のときはランダムポートを使う（既存の start() と同等）。
    /// 指定ポートが使用中の場合はランダムポートにフォールバックする。
    public func start(preferredPort: UInt16) async throws -> Int {
        if listener != nil {
            throw HookServerError.alreadyStarted
        }

        guard preferredPort != 0 else {
            return try await startListener(port: 0)
        }

        do {
            return try await startListener(port: preferredPort)
        } catch {
            // startListener が失敗時に listener を後始末済みなので、ここでは再試行のみ
            return try await startListener(port: 0)
        }
    }

    private func startListener(port: UInt16) async throws -> Int {
        let listener: NWListener
        do {
            listener = try LocalHTTPListener.makeListener(port: port)
        } catch {
            throw HookServerError.listenerFailed(error)
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
            // 失敗した listener を残すと以後の start() が恒久的に alreadyStarted になるため、
            // ここで必ず後始末して再 start 可能にする
            listener.cancel()
            if self.listener === listener {
                self.listener = nil
            }
            throw Self.startupError(from: error)
        }
    }

    /// 共通基盤のエラーを公開エラー型 HookServerError へ写像する。
    private static func startupError(from error: Error) -> HookServerError {
        switch error {
        case LocalHTTPListenerError.portUnavailable:
            return .portUnavailable
        case LocalHTTPListenerError.listenerFailed(let underlying):
            return .listenerFailed(underlying)
        default:
            return .listenerFailed(error)
        }
    }

    private func handle(connection: NWConnection) async {
        do {
            try await LocalHTTPConnection.waitUntilReady(connection)
        } catch {
            connection.cancel()
            return
        }

        let request: HTTPRequest
        do {
            request = try await LocalHTTPConnection.receiveRequest(from: connection)
        } catch HTTPMessageParserError.payloadTooLarge {
            await send(connection: connection, statusCode: 413, body: "payload too large")
            return
        } catch {
            await send(connection: connection, statusCode: 400, body: "invalid request")
            return
        }

        // 旧実装は query を含む raw target を path として照合していたため、
        // 同じ挙動になるよう target(生の request-target)で照合する
        guard request.method == "POST", request.target == "/hook" else {
            await send(connection: connection, statusCode: 404, body: "not found")
            return
        }

        // 認証: tokenStore が注入されている場合、Authorization: Bearer <token> を要求する。
        // token が無ければ 401（未認証で本文処理に入らない）。CWE-306 対策。
        let bearer: String?
        if tokenStore != nil {
            guard let token = Self.bearerToken(headers: request.headers) else {
                await send(connection: connection, statusCode: 401, body: "unauthorized")
                return
            }
            bearer = token
        } else {
            bearer = nil
        }

        do {
            let payload = try JSONDecoder().decode(HookPayload.self, from: request.body)
            let delivery = try payload.makeDelivery()

            // token が解決する session と payload の sessionID が一致しなければ拒否する。
            // 有効 token でも別セッションの hook を注入できない（CWE-639/偽 stop 注入対策）。
            if let tokenStore, let bearer {
                let tokenSession = await tokenStore.session(forToken: bearer)
                guard let tokenSession else {
                    await send(connection: connection, statusCode: 401, body: "unauthorized")
                    return
                }
                guard tokenSession == delivery.sessionID else {
                    await send(connection: connection, statusCode: 403, body: "forbidden")
                    return
                }
            }

            eventContinuation.yield((delivery.sessionID, delivery.event))
            deliveryContinuation.yield(delivery)
            await send(connection: connection, statusCode: 200, body: "")
        } catch let error as HookPayloadError {
            await send(connection: connection, statusCode: 400, body: error.localizedDescription)
        } catch {
            await send(connection: connection, statusCode: 400, body: "invalid json")
        }
    }

    /// `Authorization: Bearer <token>` ヘッダからトークンを取り出す。
    /// ヘッダキーは LocalHTTPServer が小文字化するため "authorization" を見る。
    private static func bearerToken(headers: [String: String]) -> String? {
        guard let authorization = headers["authorization"] else { return nil }
        let prefix = "Bearer "
        guard authorization.hasPrefix(prefix) else { return nil }
        let token = String(authorization.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespaces)
        return token.isEmpty ? nil : token
    }

    private func send(connection: NWConnection, statusCode: Int, body: String) async {
        let response = HTTPResponseBuilder.response(statusCode: statusCode, body: body)
        await LocalHTTPConnection.sendAndClose(response, over: connection)
    }
}
