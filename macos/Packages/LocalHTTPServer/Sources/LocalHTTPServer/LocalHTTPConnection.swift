import Foundation
import Network

/// 接続待機時の失敗。handle 側では種類を問わず接続破棄に倒すため、型は観測されない。
public enum LocalHTTPConnectionError: Error, Sendable {
    case cancelled
    /// 受信が制限時間内に完了しなかった(Slowloris 対策の全体上限)。
    case timedOut
}

/// NWConnection 上の 1 リクエスト / 1 レスポンス交換を担う共通基盤。
public enum LocalHTTPConnection: Sendable {
    /// 接続が ready になるまで待つ。
    public static func waitUntilReady(_ connection: NWConnection) async throws {
        if connection.state == .ready {
            return
        }

        // 既存の stateUpdateHandler(listener が仕込む接続数の会計ハンドラ等)を保存し、
        // ready 待ち後に nil でなく元へ復元する。これにより、後段で connection が
        // .cancelled/.failed になった際も会計ハンドラが発火してスロットを解放できる。
        let previous = connection.stateUpdateHandler
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = OnceGate()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard gate.tryEnter() else { return }
                    connection.stateUpdateHandler = previous
                    continuation.resume()
                case .failed(let error):
                    guard gate.tryEnter() else { return }
                    connection.stateUpdateHandler = previous
                    // ready 待ち中に終端した場合、以後の遷移は無いので終端を会計へ転送する
                    previous?(state)
                    continuation.resume(throwing: error)
                case .cancelled:
                    guard gate.tryEnter() else { return }
                    connection.stateUpdateHandler = previous
                    previous?(state)
                    continuation.resume(throwing: LocalHTTPConnectionError.cancelled)
                default:
                    break
                }
            }
        }
    }

    /// 受信〜リクエスト完成までの全体上限(既定 10 秒。テストで短縮するため注入可能)。
    public static let defaultReceiveTimeout: Duration = .seconds(10)

    /// リクエスト全体(ヘッダ + Content-Length 分のボディ)を受信し終え、
    /// 構築済みの HTTPRequest を返す。走査はチャンク増分のみ行う。
    /// `timeout` 内に完成しなければ接続を破棄して `LocalHTTPConnectionError.timedOut` を投げる
    /// (Slowloris / idle 接続対策の全体上限。CWE-400)。
    public static func receiveRequest(
        from connection: NWConnection,
        timeout: Duration = defaultReceiveTimeout,
        maxBodyLength: Int = HTTPMessageParser.maxBodyLength
    ) async throws -> HTTPRequest {
        // 受信ループとタイムアウトを競わせ、先に終わった方を採用する。
        // 勝った側の結果を取ったら defer で残りをキャンセルする(取りこぼしのリークを防ぐ)。
        try await withThrowingTaskGroup(of: HTTPRequest.self) { group in
            group.addTask {
                try await receiveLoop(from: connection, maxBodyLength: maxBodyLength)
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw LocalHTTPConnectionError.timedOut
            }
            defer { group.cancelAll() }
            // 最初に完了した子タスクの結果(または throw)を採用する。
            // タイムアウトが勝つと timedOut を rethrow し、cancelAll → receive の
            // onCancel → connection.cancel() で保留中の受信を確実に解く。
            guard let request = try await group.next() else {
                throw LocalHTTPConnectionError.cancelled
            }
            return request
        }
    }

    private static func receiveLoop(
        from connection: NWConnection,
        maxBodyLength: Int
    ) async throws -> HTTPRequest {
        var accumulator = HTTPRequestAccumulator(maxBodyLength: maxBodyLength)

        while true {
            let chunk = try await receive(on: connection)
            if chunk.isEmpty {
                if accumulator.isEmpty {
                    throw HTTPMessageParserError.invalidRequest
                }
                break
            }
            if try accumulator.append(chunk) == .complete {
                break
            }
        }

        return try accumulator.makeRequest()
    }

    private static func receive(on connection: NWConnection) async throws -> Data {
        // タスクがキャンセルされたら connection を cancel し、保留中の receive を
        // 解いて continuation を確実に resume させる(タイムアウト時のリーク防止)。
        let gate = OnceGate()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
                    // NWConnection の完了ハンドラは 1 回のみだが、二重 resume を防ぐ保険
                    guard gate.tryEnter() else { return }
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    if let data {
                        continuation.resume(returning: data)
                        return
                    }
                    if isComplete {
                        continuation.resume(returning: Data())
                        return
                    }
                    continuation.resume(throwing: HTTPMessageParserError.incomplete)
                }
            }
        } onCancel: {
            connection.cancel()
        }
    }

    /// レスポンスを送信して接続を閉じる。
    public static func sendAndClose(_ response: Data, over connection: NWConnection) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            connection.send(content: response, completion: .contentProcessed { _ in
                continuation.resume()
            })
        }
        connection.cancel()
    }
}
