import Foundation
@testable import CodexAppServerKit

actor SentMessages {
    private var messages: [JSONValue] = []
    let changes: AsyncStream<Void>
    private let changeContinuation: AsyncStream<Void>.Continuation

    init() {
        var captured: AsyncStream<Void>.Continuation?
        changes = AsyncStream(bufferingPolicy: .unbounded) { captured = $0 }
        changeContinuation = captured!
    }

    func append(_ data: Data) throws {
        let trimmed: Data
        if let newline = data.firstIndex(of: 0x0A) {
            trimmed = Data(data[..<newline])
        } else {
            trimmed = data
        }
        let value = try JSONDecoder.appServer.decode(JSONValue.self, from: trimmed)
        messages.append(value)
        changeContinuation.yield()
    }

    func all() -> [JSONValue] {
        messages
    }

    func first(where predicate: (JSONValue) -> Bool) -> JSONValue? {
        messages.first(where: predicate)
    }
}

final class MockTransport: AppServerTransport, @unchecked Sendable {
    let sent = SentMessages()
    let receivedLines: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation

    init() {
        var continuation: AsyncStream<Data>.Continuation?
        self.receivedLines = AsyncStream { continuation = $0 }
        self.continuation = continuation!
    }

    func send(_ data: Data) async throws {
        try await sent.append(data)
    }

    func close() async {
        continuation.finish()
    }

    func receive(_ json: String) {
        continuation.yield(Data(json.utf8))
    }
}

func jsonLine(_ value: JSONValue) throws -> String {
    let data = try JSONEncoder.appServer.encode(value)
    return String(data: data, encoding: .utf8)!
}

func waitUntil(
    timeoutNanoseconds: UInt64 = 2_000_000_000,
    _ condition: @escaping @Sendable () async -> Bool
) async -> Bool {
    await withTaskGroup(of: Bool.self) { group in
        group.addTask {
            await condition()
        }
        group.addTask {
            do {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                return false
            } catch {
                return false
            }
        }
        let result = await group.next() ?? false
        group.cancelAll()
        await group.waitForAll()
        return result
    }
}

func waitUntil(
    timeoutNanoseconds: UInt64 = 2_000_000_000,
    events: AsyncStream<Void>,
    _ condition: @escaping @Sendable () async -> Bool
) async -> Bool {
    guard await condition() == false else { return true }

    return await withTaskGroup(of: Bool.self) { group in
        group.addTask {
            for await _ in events {
                if await condition() { return true }
            }
            return false
        }
        group.addTask {
            do {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                return false
            } catch {
                return false
            }
        }
        let result = await group.next() ?? false
        group.cancelAll()
        await group.waitForAll()
        return result
    }
}
