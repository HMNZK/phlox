import Foundation
import Network
import os

/// listener 起動時の失敗。各サーバーは自分の公開エラー型へ写像して投げ直す。
public enum LocalHTTPListenerError: Error, Sendable {
    case listenerFailed(Error)
    case portUnavailable
}

/// 一度だけ通すゲート。NWListener/NWConnection の stateUpdateHandler が
/// 複数回発火しても continuation を一度しか resume しないようにする。
struct OnceGate: Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: false)

    func tryEnter() -> Bool {
        lock.withLock { entered in
            if entered {
                return false
            }
            entered = true
            return true
        }
    }
}

/// 同時接続数を上限で制限する非ブロッキングなカウンタ(セマフォ相当)。
/// `tryAcquire` は上限到達時に false を返す(待たない)。`release` は 1 減らす。
/// OSAllocatedUnfairLock は値をコピーしても同一の確保を共有するため、struct で
/// 複数クロージャに捕捉しても状態は共有される(OnceGate と同じ流儀)。
struct ConnectionLimiter: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: 0)
    let maxConnections: Int

    init(maxConnections: Int) {
        self.maxConnections = maxConnections
    }

    /// スロットを取得できたら true。上限に達していれば取得せず false。
    func tryAcquire() -> Bool {
        state.withLock { count in
            guard count < maxConnections else {
                return false
            }
            count += 1
            return true
        }
    }

    /// スロットを解放する。0 を下回らないようにする(二重 release の保険)。
    func release() {
        state.withLock { count in
            if count > 0 {
                count -= 1
            }
        }
    }

    var activeCount: Int {
        state.withLock { $0 }
    }
}

/// 127.0.0.1 専用 NWListener の生成と ready 待ちを担う共通基盤。
public enum LocalHTTPListener: Sendable {
    /// テスト用シーム: NWListener の生成を差し替えられるようにする(既定は実生成)。
    public typealias MakeListener = @Sendable (NWParameters) throws -> NWListener

    /// 127.0.0.1 の指定ポートへ束縛する listener を生成する(port 0 はランダムポート)。
    /// 生成失敗のエラーはそのまま伝播する(呼び出し側が自分のエラー型へ包む)。
    public static func makeListener(
        port: UInt16,
        make: MakeListener = { try NWListener(using: $0) }
    ) throws -> NWListener {
        let parameters = NWParameters.tcp
        parameters.acceptLocalOnly = true
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host("127.0.0.1"),
            port: NWEndpoint.Port(rawValue: port)!
        )
        return try make(parameters)
    }

    /// 同時接続数の既定上限(localhost の Hook/Control 用途に十分な安全弁)。
    public static let defaultMaxConnections = 64

    /// listener を起動し ready になるまで待って束縛ポートを返す。
    /// 失敗時の listener の後始末(cancel と保持解除)は呼び出し側の責務。
    /// `maxConnections` を超える新規接続は onConnection へ渡さず即 cancel する
    /// (Slowloris / 接続枯渇対策, CWE-400)。スロットは接続が終端(.cancelled/.failed)
    /// した時に一度だけ解放されるため、全ての handle 経路(完了/timeout/エラー)で
    /// 最終的に connection.cancel() される前提と噛み合う。
    public static func startAndWaitUntilReady(
        _ listener: NWListener,
        queue: DispatchQueue,
        maxConnections: Int = defaultMaxConnections,
        onConnection: @escaping @Sendable (NWConnection) -> Void
    ) async throws -> Int {
        let limiter = ConnectionLimiter(maxConnections: maxConnections)

        return try await withCheckedThrowingContinuation { continuation in
            let readyGate = OnceGate()

            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard readyGate.tryEnter() else { return }
                    // NWListener はハンドラを強保持するため、ローカル listener の
                    // キャプチャによる循環参照をここで切る(waitUntilReady と同じパターン)
                    listener.stateUpdateHandler = nil
                    guard let port = listener.port?.rawValue else {
                        continuation.resume(throwing: LocalHTTPListenerError.portUnavailable)
                        return
                    }
                    continuation.resume(returning: Int(port))
                case .failed(let error):
                    guard readyGate.tryEnter() else { return }
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: LocalHTTPListenerError.listenerFailed(error))
                default:
                    break
                }
            }

            listener.newConnectionHandler = { connection in
                // 上限に達していれば handle させず即 reject。
                guard limiter.tryAcquire() else {
                    connection.cancel()
                    return
                }

                // 接続が終端(.cancelled/.failed)した時に一度だけスロットを解放する。
                // 会計ハンドラは waitUntilReady が保存/復元/転送するため、handle 中に
                // 上書きされても終端で確実に発火する(release 漏れによるデッドロック防止)。
                let releaseGate = OnceGate()
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .cancelled, .failed:
                        if releaseGate.tryEnter() {
                            limiter.release()
                        }
                    default:
                        break
                    }
                }

                onConnection(connection)
            }

            listener.start(queue: queue)
        }
    }
}
