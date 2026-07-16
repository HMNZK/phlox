import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// SIGPIPE を抑止する。**fd 生成直後に呼ぶこと**。相手が接続を閉じた後の write が
/// SIGPIPE(既定 disposition = プロセス終了)ではなく errno==EPIPE を返すようにする。
///
/// 生 TCP リレーは相手(iPhone / ControlServer)が切断している最中にも write しうるため、
/// **両 fd**(accept 済み client fd・connectLoopback の upstream fd)へ必須。片方でも漏れると
/// その方向の write で SIGPIPE が飛び、Phlox プロセス全体が落ちる(全セッション喪失)。
/// 設定失敗は無視する(致命ではない。EPIPE 化できないだけで機能はする)。
func setNoSIGPIPE(_ fd: Int32) {
    var on: Int32 = 1
    _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
}

/// 1 つのクライアント接続(POSIX fd)を `127.0.0.1:<targetPort>`(ControlServer)へ接続した
/// 上流 fd と結び、双方向に生バイトを中継する。NWConnection は utun で accept できないため
/// listener も relay も素の BSD ソケットで実装する。
///
/// half-close の扱い(重要):
/// - クライアント → 上流 方向が EOF(read==0)になっても応答(上流 → クライアント)はまだ
///   流れる可能性があるため**全閉じしない**。上流の write 側だけ `shutdown(SHUT_WR)` で FIN を
///   伝え、応答パスは生かす。これが keep-alive(送信後も接続を開いたまま応答待ち)を壊さない鍵。
/// - 上流 → クライアント 方向が EOF(ControlServer が応答後にクローズ)になったら、残バイトを
///   送り切ってから両 fd を閉じる。これで 1 リクエスト = 1 接続が完結する。
///
/// teardown の順序(close-while-in-use の回避):
/// - 停止要求は `requestTeardown()` でまず両 fd を `shutdown(SHUT_RDWR)` し、相手スレッドの
///   read/write を解除する(EOF/エラーで戻る)。実 `close()` は**両ポンプスレッド終了後**に
///   一度だけ行う。片方のスレッドが使用中の fd を別スレッドが close する競合を避ける。
///
/// HTTP を一切解釈しないため method / path / query / ヘッダ / body / status は無改変で通る。
final class SocketRelay: @unchecked Sendable {
    private let clientFD: Int32
    private let upstreamFD: Int32
    /// リレー完全終了(両ポンプスレッド終了・両 fd close 済み)時に**一度だけ**呼ぶ。
    /// POSIXSocketListener の同時リレー数セマフォ解放(スロット返却)に使う。全終了経路で必ず発火する。
    private let onFinished: (@Sendable () -> Void)?

    private let lock = NSLock()
    /// 稼働中のポンプスレッド数。0 になった時点で fd を close し onFinished を呼ぶ。
    private var remainingThreads = 2
    /// requestTeardown の多重 shutdown を避けるフラグ。
    private var tearingDown = false

    private init(clientFD: Int32, upstreamFD: Int32, onFinished: (@Sendable () -> Void)?) {
        self.clientFD = clientFD
        self.upstreamFD = upstreamFD
        self.onFinished = onFinished
    }

    /// 受理済みクライアント fd を受け取り、上流へ接続して中継を開始する。
    /// 失敗時は client fd を閉じ、`onFinished`(スロット返却)を**必ず**呼ぶ(解放漏れ防止)。
    static func start(clientFD: Int32, targetPort: UInt16, onFinished: (@Sendable () -> Void)? = nil) {
        guard let upstreamFD = connectLoopback(port: targetPort) else {
            close(clientFD)
            onFinished?()
            return
        }
        let relay = SocketRelay(clientFD: clientFD, upstreamFD: upstreamFD, onFinished: onFinished)
        relay.begin()
    }

    /// 127.0.0.1:port へ接続した fd を返す(失敗時 nil)。
    private static func connectLoopback(port: UInt16) -> Int32? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        // fd 生成直後に SIGPIPE を抑止する(相手 close 後の write を EPIPE 化しプロセス終了を防ぐ)。
        setNoSIGPIPE(fd)

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        guard "127.0.0.1".withCString({ inet_pton(AF_INET, $0, &addr.sin_addr) }) == 1 else {
            close(fd)
            return nil
        }

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                connect(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0 else {
            close(fd)
            return nil
        }
        return fd
    }

    private func begin() {
        // クライアント → 上流: EOF では上流 write 側を half-close するのみ(応答パスは生かす)。
        Thread.detachNewThread { [self] in
            self.pumpClientToUpstream()
        }
        // 上流 → クライアント: EOF(応答完了)で teardown を要求する。
        Thread.detachNewThread { [self] in
            self.pumpUpstreamToClient()
        }
    }

    private func pumpClientToUpstream() {
        defer { threadDidExit() }
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let n = read(clientFD, &buffer, buffer.count)
            if n < 0 {
                if errno == EINTR { continue }
                requestTeardown()
                return
            }
            if n == 0 {
                // クライアントが送信方向を閉じた(half-close)。上流の write 側へ FIN を伝えるのみ。
                // 応答(上流 → クライアント)は閉じない。teardown はしない(keep-alive を壊さない)。
                shutdown(upstreamFD, Int32(SHUT_WR))
                return
            }
            if !writeAll(upstreamFD, buffer, n) {
                requestTeardown()
                return
            }
        }
    }

    private func pumpUpstreamToClient() {
        defer { threadDidExit() }
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let n = read(upstreamFD, &buffer, buffer.count)
            if n < 0 {
                if errno == EINTR { continue }
                requestTeardown()
                return
            }
            if n == 0 {
                // 上流が応答後にクローズ(EOF)= 交換完了。teardown を要求する。
                requestTeardown()
                return
            }
            if !writeAll(clientFD, buffer, n) {
                requestTeardown()
                return
            }
        }
    }

    /// buffer の先頭 count バイトを fd へ全量書き込む。失敗で false。
    /// SO_NOSIGPIPE 設定済みのため、相手 close 後は SIGPIPE ではなく errno==EPIPE(n<0)で false を返す。
    private func writeAll(_ fd: Int32, _ buffer: [UInt8], _ count: Int) -> Bool {
        var offset = 0
        return buffer.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Bool in
            let base = raw.bindMemory(to: UInt8.self).baseAddress!
            while offset < count {
                let n = write(fd, base + offset, count - offset)
                if n <= 0 {
                    if n < 0 && errno == EINTR { continue }
                    return false
                }
                offset += n
            }
            return true
        }
    }

    /// リレー全体の停止を要求する。close-while-in-use を避けるため、まず両 fd を
    /// `shutdown(SHUT_RDWR)` して相手スレッドの read/write を解除し(EOF/エラーで戻す)、
    /// 実 `close()` は両スレッド終了後(`threadDidExit`)に一度だけ行う。多重呼び出しは無害。
    private func requestTeardown() {
        lock.lock()
        if tearingDown {
            lock.unlock()
            return
        }
        tearingDown = true
        lock.unlock()
        shutdown(clientFD, Int32(SHUT_RDWR))
        shutdown(upstreamFD, Int32(SHUT_RDWR))
    }

    /// ポンプスレッド 1 本の終了を記録する。両方終わったら両 fd を close し、onFinished(スロット
    /// 返却)を一度だけ呼ぶ。close はここでのみ行うため、使用中 fd への他スレッド close は起きない。
    private func threadDidExit() {
        lock.lock()
        remainingThreads -= 1
        let done = remainingThreads == 0
        lock.unlock()
        guard done else { return }
        close(clientFD)
        close(upstreamFD)
        onFinished?()
    }
}
