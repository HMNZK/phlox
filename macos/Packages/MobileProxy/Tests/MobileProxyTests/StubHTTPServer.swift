import Foundation
import Network

/// 結合テスト用のスタブ HTTP サーバ。
/// 127.0.0.1 のランダムポートで待ち受け、受信したリクエスト(ヘッダ + Content-Length 分の
/// ボディ)を生バイトで記録し、テストが指定した生レスポンスをそのまま返す。
/// プロキシが「無改変で中継する」ことをループバック越しに検証するために使う。
final class StubHTTPServer: @unchecked Sendable {
    /// テストが返したい生レスポンス全体(ステータス行 + ヘッダ + body)。
    private let rawResponse: Data
    private let listener: NWListener
    private let queue = DispatchQueue(label: "StubHTTPServer")

    private let lock = NSLock()
    private var _capturedRequests: [Data] = []

    /// 受信し終えたリクエストの生バイト列(複数接続を順に記録)。
    var capturedRequests: [Data] {
        lock.withLock { _capturedRequests }
    }

    /// 最後に受信したリクエストの生バイト列。
    var lastRequest: Data? {
        lock.withLock { _capturedRequests.last }
    }

    init(rawResponse: Data) throws {
        self.rawResponse = rawResponse
        let parameters = NWParameters.tcp
        parameters.acceptLocalOnly = true
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host("127.0.0.1"),
            port: NWEndpoint.Port(rawValue: 0)!
        )
        self.listener = try NWListener(using: parameters)
    }

    /// サーバを起動し、束縛された 127.0.0.1 のポート番号を返す。
    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
            let once = OnceResume()

            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    guard let port = self?.listener.port?.rawValue else {
                        once.run { continuation.resume(throwing: StubError.noPort) }
                        return
                    }
                    once.run { continuation.resume(returning: port) }
                case .failed(let error):
                    once.run { continuation.resume(throwing: error) }
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { connection.cancel(); return }
                connection.start(queue: self.queue)
                self.handle(connection)
            }

            listener.start(queue: queue)
        }
    }

    func stop() {
        listener.cancel()
    }

    private func handle(_ connection: NWConnection) {
        receiveRequest(connection, accumulated: Data())
    }

    /// ヘッダ終端と Content-Length を見てリクエスト全体を受信し終えたら、
    /// 記録してから生レスポンスを返す。
    private func receiveRequest(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { connection.cancel(); return }
            if error != nil {
                connection.cancel()
                return
            }
            var buffer = accumulated
            if let data { buffer.append(data) }

            if Self.isComplete(buffer) || isComplete {
                self.lock.withLock { self._capturedRequests.append(buffer) }
                self.sendResponse(connection)
                return
            }
            self.receiveRequest(connection, accumulated: buffer)
        }
    }

    private func sendResponse(_ connection: NWConnection) {
        connection.send(content: rawResponse, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    /// ヘッダ + Content-Length 分の body を受信し終えたかを判定する。
    static func isComplete(_ data: Data) -> Bool {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else {
            return false
        }
        let headerData = data[..<headerEnd.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            return false
        }
        let contentLength = Self.contentLength(in: headerText) ?? 0
        let bodyStart = headerEnd.upperBound
        return data.count >= bodyStart + contentLength
    }

    static func contentLength(in headerText: String) -> Int? {
        for line in headerText.split(separator: "\r\n").dropFirst() {
            if line.lowercased().hasPrefix("content-length:") {
                let value = line.split(separator: ":", maxSplits: 1).last?
                    .trimmingCharacters(in: .whitespaces)
                return value.flatMap { Int($0) }
            }
        }
        return nil
    }

    enum StubError: Error { case noPort }
}

extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock(); defer { unlock() }
        return body()
    }
}
