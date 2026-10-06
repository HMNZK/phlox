import Foundation
import Network
import Testing
@testable import LocalHTTPServer

// 同時接続の上限（ConnectionLimiter とリスナーへの配線）と、受信タイムアウト。

// MARK: - 同時接続上限（セマフォ単体）: 上限で reject / release / 二重 release 保護

@Suite struct ConnectionLimiterTests {
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

// MARK: - 実ソケット: 受信タイムアウトと同時接続上限の配線

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

@Suite struct ReceiveTimeoutTests {
    /// idle 接続(何も送らない)は注入した短い timeout で timedOut になり閉じる。
    @Test func idleConnectionTimesOut() async throws {
        let queue = DispatchQueue(label: "limits.timeout")
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
        let queue = DispatchQueue(label: "limits.valid")
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

@Suite struct ConnectionLimitWiringTests {
    /// maxConnections=1 で、1 本目が保持中は 2 本目を reject し、1 本目が閉じると
    /// スロットが解放されて新規接続を再び accept する(release 漏れが無いことの配線検証)。
    @Test func rejectsWhileFullAndAcceptsAfterRelease() async throws {
        let queue = DispatchQueue(label: "limits.limit")
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
