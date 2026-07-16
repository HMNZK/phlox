import Foundation
import Network
import Testing
@testable import LocalHTTPServer

// MARK: - I1: 非UTF-8ヘッダで maxBodyLength チェック前に .needsMore を返しバッファ無制限成長

@Suite struct AuditI1Tests {
    /// 復号不能ヘッダ(headerDecodable==false)でヘッダ終端は届くが body が上限超過。
    /// 修正前: 全長超過チェックが decode guard の後ろにあり .needsMore を返す(無制限成長)。
    /// 修正後: decode guard の前に超過判定し payloadTooLarge を throw。
    @Test func nonUTF8HeaderWithOversizedBodyThrowsPayloadTooLarge() {
        var accumulator = HTTPRequestAccumulator(maxBodyLength: 8)
        var data = Data([0xFF, 0xFE]) // 不正な UTF-8 先頭バイト
        data.append(Data("\r\n\r\n".utf8)) // ヘッダ終端
        data.append(Data("0123456789".utf8)) // 10 バイト body > 上限 8

        #expect(throws: HTTPMessageParserError.payloadTooLarge) {
            _ = try accumulator.append(data)
        }
    }

    /// body が複数チャンクで届いて上限を超えた時点で throw する(非UTF-8ヘッダでも)。
    /// 修正前: 3 回とも .needsMore を返し throw しない。
    @Test func nonUTF8HeaderBodyGrowingAcrossChunksEventuallyThrows() throws {
        var accumulator = HTTPRequestAccumulator(maxBodyLength: 8)
        var header = Data([0xFF])
        header.append(Data("\r\n\r\n".utf8))

        #expect(try accumulator.append(header) == .needsMore) // body 0
        #expect(try accumulator.append(Data("1234".utf8)) == .needsMore) // body 4 <= 8
        #expect(throws: HTTPMessageParserError.payloadTooLarge) {
            _ = try accumulator.append(Data("56789".utf8)) // body 9 > 8
        }
    }

    /// 誤爆防止(不変): 非UTF-8ヘッダでも body が上限内なら 413 にせず .needsMore を返す。
    @Test func nonUTF8HeaderWithinLimitDoesNotFalselyThrow() throws {
        var accumulator = HTTPRequestAccumulator(maxBodyLength: 256)
        var data = Data([0xFF])
        data.append(Data("\r\n\r\n".utf8))
        data.append(Data("ab".utf8))

        #expect(try accumulator.append(data) == .needsMore)
    }
}

// MARK: - nit: Content-Length 負値許容

@Suite struct AuditNegativeContentLengthTests {
    /// 修正前: Int("-5") == -5 を返し負値を許容。修正後: guard n >= 0 で nil。
    @Test func negativeContentLengthIsInvalid() {
        let header = "POST /x HTTP/1.1\r\nContent-Length: -5"
        #expect(HTTPMessageParser.contentLength(in: header) == nil)
    }

    /// 正値は従来どおり抽出できる(回帰なし)。
    @Test func nonNegativeContentLengthStillParsed() {
        #expect(HTTPMessageParser.contentLength(in: "POST /x HTTP/1.1\r\nContent-Length: 0") == 0)
        #expect(HTTPMessageParser.contentLength(in: "POST /x HTTP/1.1\r\nContent-Length: 42") == 42)
    }
}

// MARK: - I2(セマフォ単体): 上限で reject / release / 二重 release 保護

@Suite struct AuditConnectionLimiterTests {
    @Test func rejectsWhenFullAndReleasesToAcceptAgain() {
        let limiter = ConnectionLimiter(maxConnections: 2)

        #expect(limiter.tryAcquire() == true) // 1
        #expect(limiter.tryAcquire() == true) // 2
        #expect(limiter.tryAcquire() == false) // 上限到達 → reject
        #expect(limiter.activeCount == 2)

        limiter.release()
        #expect(limiter.activeCount == 1)
        #expect(limiter.tryAcquire() == true) // 空きができたので acquire 可
        #expect(limiter.tryAcquire() == false)

        limiter.release()
        limiter.release()
        #expect(limiter.activeCount == 0)

        // 二重 release でも 0 を下回らない(会計破綻でスロットが増殖しない)
        limiter.release()
        #expect(limiter.activeCount == 0)
        #expect(limiter.tryAcquire() == true)
    }
}

// MARK: - I2(実ソケット): 受信タイムアウトと同時接続上限の配線

/// サーバ側で観測した結果を 1 度だけ記録する箱。
private actor OutcomeBox {
    private(set) var value: String?
    func set(_ v: String) { if value == nil { value = v } }
}

/// accept された回数(onConnection に渡った回数)を数える。
private actor AcceptLog {
    private(set) var count = 0
    func increment() { count += 1 }
}

/// deadline 内に cond が true になるのを待つ(小刻みポーリング)。
private func waitUntil(_ deadline: Duration, _ cond: @Sendable () async -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let end = clock.now.advanced(by: deadline)
    while clock.now < end {
        if await cond() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return await cond()
}

@Suite struct AuditReceiveTimeoutTests {
    /// idle 接続(何も送らない)は注入した短い timeout で timedOut になり閉じる。
    @Test func idleConnectionTimesOut() async throws {
        let queue = DispatchQueue(label: "audit.timeout")
        let listener = try LocalHTTPListener.makeListener(port: 0)
        let box = OutcomeBox()
        let port = try await LocalHTTPListener.startAndWaitUntilReady(listener, queue: queue) { connection in
            connection.start(queue: queue)
            Task {
                try? await LocalHTTPConnection.waitUntilReady(connection)
                do {
                    _ = try await LocalHTTPConnection.receiveRequest(from: connection, timeout: .milliseconds(300))
                    await box.set("completed")
                } catch LocalHTTPConnectionError.timedOut {
                    await box.set("timedOut")
                } catch {
                    await box.set("error")
                }
                connection.cancel()
            }
        }

        let client = NWConnection(
            host: "127.0.0.1",
            port: NWEndpoint.Port(rawValue: UInt16(port))!,
            using: .tcp
        )
        client.start(queue: queue)

        // idle: 何も送らない。
        let ok = await waitUntil(.seconds(3)) { await box.value == "timedOut" }
        let observed = await box.value ?? "nil"
        #expect(ok, "idle 接続は timedOut で閉じるべき (observed: \(observed))")

        client.cancel()
        listener.cancel()
    }

    /// 正常なリクエストは timeout に達する前に完成する(誤って timeout で切らない)。
    @Test func validRequestCompletesWellWithinTimeout() async throws {
        let queue = DispatchQueue(label: "audit.valid")
        let listener = try LocalHTTPListener.makeListener(port: 0)
        let box = OutcomeBox()
        let port = try await LocalHTTPListener.startAndWaitUntilReady(listener, queue: queue) { connection in
            connection.start(queue: queue)
            Task {
                try? await LocalHTTPConnection.waitUntilReady(connection)
                do {
                    let request = try await LocalHTTPConnection.receiveRequest(from: connection, timeout: .seconds(5))
                    await box.set("completed:\(request.method):\(String(data: request.body, encoding: .utf8) ?? "")")
                } catch {
                    await box.set("error")
                }
                connection.cancel()
            }
        }

        let client = NWConnection(
            host: "127.0.0.1",
            port: NWEndpoint.Port(rawValue: UInt16(port))!,
            using: .tcp
        )
        client.start(queue: queue)
        let request = Data("POST /hook HTTP/1.1\r\nContent-Length: 5\r\n\r\nhello".utf8)
        client.send(content: request, completion: .contentProcessed { _ in })

        // timeout(5s)より十分早く完成する。3s 以内に completed になれば false-timeout でない。
        let ok = await waitUntil(.seconds(3)) { await box.value == "completed:POST:hello" }
        let observed = await box.value ?? "nil"
        #expect(ok, "正常リクエストは timeout 前に完成すべき (observed: \(observed))")

        client.cancel()
        listener.cancel()
    }
}

@Suite struct AuditConnectionLimitWiringTests {
    /// maxConnections=1 で、1 本目が保持中は 2 本目を reject し、1 本目が閉じると
    /// スロットが解放されて新規接続を再び accept する(release 漏れが無いことの配線検証)。
    @Test func rejectsWhileFullAndAcceptsAfterRelease() async throws {
        let queue = DispatchQueue(label: "audit.limit")
        let listener = try LocalHTTPListener.makeListener(port: 0)
        let log = AcceptLog()
        let port = try await LocalHTTPListener.startAndWaitUntilReady(
            listener,
            queue: queue,
            maxConnections: 1
        ) { connection in
            connection.start(queue: queue)
            Task {
                await log.increment() // accept された回数
                try? await LocalHTTPConnection.waitUntilReady(connection)
                // idle クライアントを長めに保持(テストが明示的に client を閉じるまでスロットを握る)
                _ = try? await LocalHTTPConnection.receiveRequest(from: connection, timeout: .seconds(5))
                connection.cancel()
            }
        }

        func makeClient() -> NWConnection {
            let c = NWConnection(
                host: "127.0.0.1",
                port: NWEndpoint.Port(rawValue: UInt16(port))!,
                using: .tcp
            )
            c.start(queue: queue)
            return c
        }

        // A: 1 本目。accept される(count==1)。idle なのでスロットを握り続ける。
        let clientA = makeClient()
        #expect(await waitUntil(.seconds(3)) { await log.count >= 1 }, "1 本目は accept されるべき")

        // B: 2 本目。A がスロットを握っている間は reject される(count は 1 のまま)。
        let clientB = makeClient()
        try? await Task.sleep(for: .milliseconds(300))
        let countWhileFull = await log.count
        #expect(countWhileFull == 1, "上限到達中の 2 本目は reject されるべき (count=\(countWhileFull))")

        // A を閉じる → サーバ側 receiveRequest が EOF で戻り connection.cancel() → スロット解放。
        clientA.cancel()

        // C: 解放後の新規接続は accept されるべき(count==2)。単発接続だと拒否された瞬間に
        // NWConnection は再試行しないため、並列実行の CPU 競合で解放伝播が遅れると取りこぼす。
        // そこで「新規接続を張り直しつつ count>=2 になるまで待つ」ことで、release 漏れが
        // 無いこと(=いずれ必ず accept される)を頑健に検証する。release 漏れならここで stuck。
        var retryClients: [NWConnection] = []
        var acceptedAfterRelease = false
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while clock.now < deadline {
            if await log.count >= 2 {
                acceptedAfterRelease = true
                break
            }
            retryClients.append(makeClient())
            try? await Task.sleep(for: .milliseconds(150))
        }
        if await log.count >= 2 { acceptedAfterRelease = true }
        let finalCount = await log.count
        #expect(acceptedAfterRelease, "解放後の接続は accept されるべき (count=\(finalCount))")

        clientB.cancel()
        for c in retryClients { c.cancel() }
        listener.cancel()
    }
}
