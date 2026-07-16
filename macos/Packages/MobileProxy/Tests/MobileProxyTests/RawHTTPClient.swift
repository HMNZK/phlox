import Foundation
import Network

/// 結合テスト用の生 HTTP クライアント。
/// 127.0.0.1:<port>(=プロキシ)へ生バイトのリクエストを送り、
/// 接続クローズ(EOF)までの生レスポンス全体を返す。
enum RawHTTPClient {
    /// 生リクエストを送って生レスポンス全体を受け取る。
    static func send(_ request: Data, toPort port: UInt16, host: String = "127.0.0.1") async throws -> Data {
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )
        let queue = DispatchQueue(label: "RawHTTPClient")

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let once = OnceResume()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    once.run { continuation.resume() }
                case .failed(let error):
                    once.run { continuation.resume(throwing: error) }
                case .cancelled:
                    once.run { continuation.resume(throwing: ClientError.cancelled) }
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: request, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }

        var response = Data()
        while true {
            let (chunk, isComplete) = try await receive(connection)
            if let chunk { response.append(chunk) }
            if isComplete { break }
        }
        connection.cancel()
        return response
    }

    /// リクエストを送った直後に送信方向を half-close(FIN)してから応答を待つ。
    /// クライアントがリクエスト送信後に write 側を閉じても応答が欠落しないことを確認するため。
    static func sendHalfClosing(_ request: Data, toPort port: UInt16, host: String = "127.0.0.1") async throws -> Data {
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )
        let queue = DispatchQueue(label: "RawHTTPClient.halfClose")

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let once = OnceResume()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    once.run { continuation.resume() }
                case .failed(let error):
                    once.run { continuation.resume(throwing: error) }
                case .cancelled:
                    once.run { continuation.resume(throwing: ClientError.cancelled) }
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }

        // isComplete: true でリクエスト送信と同時に送信方向の FIN を送る(half-close)。
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: request, isComplete: true, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }

        var response = Data()
        while true {
            let (chunk, isComplete) = try await receive(connection)
            if let chunk { response.append(chunk) }
            if isComplete { break }
        }
        connection.cancel()
        return response
    }

    /// curl/URLSession 相当の keep-alive クライアント(素の POSIX ソケット)。
    /// リクエストを書き込んだ後**送信方向を閉じず**(half-close しない)、そのまま応答を
    /// EOF まで読む。これが実機の keep-alive 経路(送信後も接続を開いたまま応答待ち)の回帰ガード。
    static func sendKeepAlivePOSIX(_ request: Data, toPort port: UInt16, host: String = "127.0.0.1") throws -> Data {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ClientError.socketFailed }
        defer { close(fd) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        guard host.withCString({ inet_pton(AF_INET, $0, &addr.sin_addr) }) == 1 else {
            throw ClientError.badAddress
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                connect(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connectResult == 0 else { throw ClientError.connectFailed }

        // リクエストを全量書き込む(送信方向は閉じない=keep-alive)。
        try request.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            var offset = 0
            let base = raw.bindMemory(to: UInt8.self).baseAddress!
            while offset < raw.count {
                let n = write(fd, base + offset, raw.count - offset)
                if n <= 0 { throw ClientError.writeFailed }
                offset += n
            }
        }

        // 応答を EOF(read==0)まで読む。
        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let n = read(fd, &buffer, buffer.count)
            if n < 0 { throw ClientError.readFailed }
            if n == 0 { break }
            response.append(contentsOf: buffer[0..<n])
        }
        return response
    }

    private static func receive(_ connection: NWConnection) async throws -> (Data?, Bool) {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (data, isComplete))
            }
        }
    }

    enum ClientError: Error {
        case cancelled
        case socketFailed
        case badAddress
        case connectFailed
        case writeFailed
        case readFailed
    }
}
