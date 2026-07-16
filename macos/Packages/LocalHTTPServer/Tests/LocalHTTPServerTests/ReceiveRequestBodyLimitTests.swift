import Foundation
import Network
import Testing
@testable import LocalHTTPServer

private actor OutcomeBox {
    private(set) var value: String?
    func set(_ value: String) { if self.value == nil { self.value = value } }
}

private func waitUntil(_ deadline: Duration, _ condition: @Sendable () async -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let end = clock.now.advanced(by: deadline)
    while clock.now < end {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return await condition()
}

@Suite struct ReceiveRequestBodyLimitTests {
    @Test func receiveRequestUsesInjectedMaxBodyLength() async throws {
        let queue = DispatchQueue(label: "receive.body-limit")
        let listener = try LocalHTTPListener.makeListener(port: 0)
        let box = OutcomeBox()
        let injectedLimit = 16
        let port = try await LocalHTTPListener.startAndWaitUntilReady(listener, queue: queue) { connection in
            connection.start(queue: queue)
            Task {
                try? await LocalHTTPConnection.waitUntilReady(connection)
                do {
                    _ = try await LocalHTTPConnection.receiveRequest(
                        from: connection,
                        timeout: .seconds(5),
                        maxBodyLength: injectedLimit
                    )
                    await box.set("completed")
                } catch HTTPMessageParserError.payloadTooLarge {
                    await box.set("payloadTooLarge")
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

        let request = Data("POST /send HTTP/1.1\r\nContent-Length: 20\r\n\r\n01234567890123456789".utf8)
        client.send(content: request, completion: .contentProcessed { _ in })

        let ok = await waitUntil(.seconds(3)) { await box.value == "payloadTooLarge" }
        let observed = await box.value ?? "nil"
        #expect(ok, "注入上限 \(injectedLimit) 未満の宣言長でも受信ボディ超過で 413 相当の throw になるべき (observed: \(observed))")

        client.cancel()
        listener.cancel()
    }

    @Test func receiveRequestAcceptsBodyWithinInjectedLimit() async throws {
        let queue = DispatchQueue(label: "receive.body-limit.ok")
        let listener = try LocalHTTPListener.makeListener(port: 0)
        let box = OutcomeBox()
        let injectedLimit = 32
        let port = try await LocalHTTPListener.startAndWaitUntilReady(listener, queue: queue) { connection in
            connection.start(queue: queue)
            Task {
                try? await LocalHTTPConnection.waitUntilReady(connection)
                do {
                    let request = try await LocalHTTPConnection.receiveRequest(
                        from: connection,
                        timeout: .seconds(5),
                        maxBodyLength: injectedLimit
                    )
                    await box.set("completed:\(request.body.count)")
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

        let body = Data("hello".utf8)
        let request = Data("POST /send HTTP/1.1\r\nContent-Length: \(body.count)\r\n\r\n".utf8) + body
        client.send(content: request, completion: .contentProcessed { _ in })

        let ok = await waitUntil(.seconds(3)) { await box.value == "completed:5" }
        let observed = await box.value ?? "nil"
        #expect(ok, "注入上限内の body は受信完了するべき (observed: \(observed))")

        client.cancel()
        listener.cancel()
    }
}
