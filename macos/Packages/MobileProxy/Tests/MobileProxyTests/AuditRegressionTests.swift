import Foundation
import Testing
@testable import MobileProxy
#if canImport(Darwin)
import Darwin
#endif

/// task-2 監査回帰: SocketRelay の SIGPIPE 対策(C1 critical)・accept 同時数上限(I3)・
/// スロット解放(デッドロック防止)を符号化する。
///
/// 重要(ハザード①): SIGPIPE の既定 disposition はプロセス終了。相手 close 後の生 write を
/// 素で行うテストはテストランナー自身を殺す。また Swift on Darwin では `fork()` が
/// unavailable(`'fork()' is unavailable: Please use threads or posix_spawn*()`)なので、
/// 「既定 disposition で実際に死ぬ」を子プロセスへ隔離する検証も書けない。
/// よって task 記載の指針どおり **「SO_NOSIGPIPE 設定後の fd への write が EPIPE を返し
/// プロセスが生存する」** 形の in-process 検証にする(テストランナーは死なない)。
@Suite struct AuditRegressionTests {

    // MARK: - ハザード① SIGPIPE → EPIPE 化(SO_NOSIGPIPE)

    /// 本番ヘルパ `setNoSIGPIPE`(SocketRelay の connectLoopback / POSIXSocketListener の accept が
    /// fd 生成直後に呼ぶのと同一)を適用した fd は、相手 close 後の write が SIGPIPE でプロセスを
    /// 落とさず errno==EPIPE を返す(プロセス生存=テスト完走)。
    /// これが SocketRelay の生 write 中継に必要な事後条件。未修正コードでは `setNoSIGPIPE` が
    /// 存在せずコンパイル不能(=red)。
    @Test func setNoSIGPIPEMakesWriteAfterPeerCloseReturnEPIPE() {
        var fds: [Int32] = [0, 0]
        #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0)
        let writeFD = fds[1]
        let peerFD = fds[0]

        // 本番コードが fd 生成直後に呼ぶのと同じ設定を適用する。
        setNoSIGPIPE(writeFD)
        // 相手(read 側)を閉じる → 以降の write は EPIPE を起こす。
        close(peerFD)

        var byte: UInt8 = 0
        var failedN = 0
        for _ in 0..<10_000 {
            let n = write(writeFD, &byte, 1)
            if n < 0 {
                failedN = n
                break
            }
        }
        let capturedErrno = errno
        close(writeFD)

        #expect(failedN < 0, "相手 close 後の write は失敗(-1)を返すはず(プロセスは生存している)")
        #expect(capturedErrno == EPIPE, "SO_NOSIGPIPE 設定時の errno は EPIPE のはず: got \(capturedErrno)")
    }

    /// [C1 critical wiring] **実 SocketRelay 経路**で accept 済み client fd の SO_NOSIGPIPE 配線
    /// (POSIXSocketListener.acceptLoop の setsockopt)を突く。巨大応答の途中でクライアントが切断すると、
    /// relay の 上流→クライアント write が消えた相手に当たる。client fd に SO_NOSIGPIPE が無ければ
    /// **ここでテストランナーが SIGPIPE で死ぬ**。テストが完走する = プロセス生存 = wiring が効いている。
    /// (上の単体テストと違い、この経路を通さないと :acceptLoop の setsockopt 削除を見逃す。)
    @Test func largeResponseWriteAfterClientAbortDoesNotKillProcess() async throws {
        // relay の送信バッファ最大(kern.ipc.maxsockbuf=8MB)を超える応答。クライアント側の受信
        // バッファを小さく固定して読まないため、relay は client への write でブロックしたまま残る。
        let body = String(repeating: "x", count: 16 << 20)
        var text = "HTTP/1.1 200 OK\r\nContent-Length: \(body.utf8.count)\r\n\r\n"
        text += body
        let stub = try StubHTTPServer(rawResponse: Data(text.utf8))
        let stubPort = try await stub.start()
        defer { stub.stop() }

        let proxy = MobileProxy(
            listenHost: "127.0.0.1", listenPort: 0, targetPort: stubPort, maxConcurrentRelays: 1
        )
        let port = try await proxy.start()
        defer { Task { await proxy.stop() } }

        // 受信バッファを小さく固定 → relay は client write で早期ブロックする。以後 read しない。
        let c = try PersistentRawClient(port: port, recvBufferBytes: 2048)
        c.sendAllIgnoringError(Data("GET / HTTP/1.1\r\nHost: x\r\n\r\n".utf8))
        try await Task.sleep(nanoseconds: 300_000_000)  // relay が client write でブロックするのを待つ
        c.closeWithReset()                              // RST で相手消失 → blocked write が失敗
        // relay の 上流→クライアント write がここで消えた client に当たる。accept 済み client fd に
        // SO_NOSIGPIPE 未配線なら、ここで relay スレッドが SIGPIPE を上げてランナーが死ぬ(=red)。
        try await Task.sleep(nanoseconds: 400_000_000)
        #expect(Bool(true), "relay は SIGPIPE で死なず生存(=accept 済み client fd の SO_NOSIGPIPE 配線が効いている)")
    }

    /// [C1 critical wiring] **実 SocketRelay 経路**で upstream fd の SO_NOSIGPIPE 配線
    /// (SocketRelay.connectLoopback の setsockopt)を突く。巨大 request body を送り、上流が読まずに RST で
    /// 切断すると relay の クライアント→上流 write が消えた相手に当たる。upstream fd に SO_NOSIGPIPE が
    /// 無ければ **テストランナーが SIGPIPE で死ぬ**。完走 = 生存 = wiring が効いている。
    @Test func largeRequestWriteAfterUpstreamAbortDoesNotKillProcess() async throws {
        // 上流の受信バッファを小さく固定 + 読まずに 300ms 後 RST。relay の送信バッファ最大(8MB)を
        // 超える 16MB body を送ると、relay は upstream write でブロックしたまま残り、RST で失敗する。
        let upstream = try AbortingUpstreamServer(closeAfterMs: 300, recvBufferBytes: 2048)
        defer { upstream.stop() }

        let proxy = MobileProxy(
            listenHost: "127.0.0.1", listenPort: 0, targetPort: upstream.port, maxConcurrentRelays: 1
        )
        let port = try await proxy.start()
        defer { Task { await proxy.stop() } }

        let c = try PersistentRawClient(port: port)
        defer { c.close() }

        var req = Data("POST / HTTP/1.1\r\nHost: x\r\nContent-Length: \(16 << 20)\r\n\r\n".utf8)
        req.append(Data(repeating: 0x78, count: 16 << 20))
        // 巨大 body 送信で relay の upstream write をブロックさせ、上流 RST 時に write-after-close を
        // 踏ませる。別スレッドで送って async ランタイムを塞がない。失敗は無視(ランナーは SO_NOSIGPIPE で生存)。
        let sender = Thread { c.sendAllIgnoringError(req) }
        sender.start()

        // upstream fd に SO_NOSIGPIPE 未配線なら、上流 RST 到達時に relay スレッドが SIGPIPE を上げて
        // ランナーが死ぬ(=red)。closeAfterMs(300) + teardown 分を待って生存を確認する。
        try await Task.sleep(nanoseconds: 700_000_000)
        #expect(Bool(true), "relay は SIGPIPE で死なず生存(=upstream fd の SO_NOSIGPIPE 配線が効いている)")
    }

    // MARK: - ハザード② accept 同時数上限(CWE-400)

    /// 同時リレー数の上限を超えた接続は accept 直後に close される(既存接続は継続)。
    /// 上限=2 のプロキシへ、応答しない保持サーバ向けに 2 接続を張ってスロットを占有し、
    /// 3 本目が即 close(EOF)されること、上流へ中継されないことを実ソケットで確認する。
    @Test func acceptBeyondConcurrencyLimitClosesExcessConnection() async throws {
        let holding = try HoldingUpstreamServer()
        defer { holding.stop() }

        let proxy = MobileProxy(
            listenHost: "127.0.0.1",
            listenPort: 0,
            targetPort: holding.port,
            maxConcurrentRelays: 2
        )
        let listenPort = try await proxy.start()
        defer { Task { await proxy.stop() } }

        // 上限=2 のスロットを占有する 2 接続。保持サーバは応答しないのでスロットは解放されない。
        let c1 = try PersistentRawClient(port: listenPort)
        let c2 = try PersistentRawClient(port: listenPort)
        defer { c1.close(); c2.close() }

        // 2 接続が上流まで到達(=スロット取得)したことを確認する。
        var waited = 0
        while holding.acceptedCount < 2 && waited < 400 {
            try await Task.sleep(nanoseconds: 5_000_000)
            waited += 1
        }
        #expect(holding.acceptedCount == 2, "上限内の 2 接続は上流へ到達するはず: got \(holding.acceptedCount)")

        // 3 本目: 上限超過 → プロキシは accept 直後に close する(即 EOF)。
        let c3 = try PersistentRawClient(port: listenPort)
        defer { c3.close() }
        let n = c3.readOneWithTimeout(ms: 1500)
        #expect(n == 0, "上限超過接続はプロキシに close される(read==0=EOF)。got n=\(n)")

        // 上流は 3 本目を受けていない(既存 2 本のみ)。
        try await Task.sleep(nanoseconds: 80_000_000)
        #expect(holding.acceptedCount == 2, "超過接続は上流へ中継されないはず: got \(holding.acceptedCount)")
    }

    // MARK: - ハザード③ スロット解放漏れ(デッドロック防止)

    /// リレー完了時にスロットが必ず解放されること。上限=2 のプロキシへ逐次に 5 リクエストを
    /// 通す。解放が漏れると 3 本目以降でスロットが枯渇し、以後の接続が即 close されて応答が
    /// 空になる。全リクエストが正しい応答を得られれば、全経路で解放されている。
    @Test func slotsAreReleasedSoSequentialRequestsSucceed() async throws {
        let body = "ok"
        var responseText = "HTTP/1.1 200 OK\r\nContent-Length: \(body.utf8.count)\r\n\r\n"
        responseText += body
        let response = Data(responseText.utf8)

        let stub = try StubHTTPServer(rawResponse: response)
        let stubPort = try await stub.start()
        defer { stub.stop() }

        let proxy = MobileProxy(
            listenHost: "127.0.0.1",
            listenPort: 0,
            targetPort: stubPort,
            maxConcurrentRelays: 2
        )
        let listenPort = try await proxy.start()
        defer { Task { await proxy.stop() } }

        let request = Data("GET /sessions HTTP/1.1\r\nHost: example\r\n\r\n".utf8)
        for i in 0..<5 {
            let received = try await RawHTTPClient.send(request, toPort: listenPort)
            #expect(received == response, "逐次 \(i) 本目でスロットが枯渇(解放漏れ)。got \(received.count) bytes")
            // 解放は両リレースレッド終了時に起きる。次接続前に短く settle させる。
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    /// [release: connect 失敗経路] connectLoopback 失敗の早期リターン
    /// (SocketRelay.start: `close(clientFD); onFinished?(); return`)で slot が返ること。
    /// 未 listen ポートへ向けた上限=1 のプロキシへ連続接続し、毎回 EOF で即 close されること、かつ
    /// slot 解放漏れでセマフォが枯渇(→proxy 破棄時に libdispatch が初期値未満 deinit を検出して trap)
    /// しないことを突く。`onFinished?()` を外すと slot が返らず、proxy stop 時に異常終了する。
    @Test func slotReleasedWhenUpstreamConnectFails() async throws {
        // 「closed-listener」ポートを使う: listen 済みポートを close すると connect は即 ECONNREFUSED に
        // なる(bind のみだと SYN が捨てられ ~7.8s ブロックするため不可)。プロキシの listen が同番号を
        // 再取得して自己接続する誤検出を避けるため、**プロキシ start までポートを保持**(listener 稼働)し、
        // proxy が別ポートを確保した後に close して解放する。
        let deadListener = try HoldingUpstreamServer()
        let deadPort = deadListener.port

        let proxy = MobileProxy(
            listenHost: "127.0.0.1", listenPort: 0, targetPort: deadPort, maxConcurrentRelays: 1
        )
        let port = try await proxy.start()   // deadPort は deadListener が保持中 → proxy は別ポートに bind
        #expect(port != deadPort)
        deadListener.stop()                  // ここで解放 → 以後 connectLoopback(deadPort) は即 ECONNREFUSED

        for _ in 0..<3 {
            let c = try PersistentRawClient(port: port)
            let n = c.readOneWithTimeout(ms: 500)
            #expect(n == 0, "connect 失敗でも slot が返り接続は即 close される(EOF)。got n=\(n)")
            c.close()
        }

        // slot が全接続で返っていればセマフォは初期値へ戻り deinit は安全。onFinished を外すと
        // ここ(stop → listener/セマフォ破棄)で初期値未満 deinit の trap が出て異常終了する。
        await proxy.stop()
    }
}
