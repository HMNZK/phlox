import Foundation
@testable import CodexAppServerKit

actor SentMessages {
    private var messages: [JSONValue] = []

    func append(_ data: Data) throws {
        let trimmed: Data
        if let newline = data.firstIndex(of: 0x0A) {
            trimmed = Data(data[..<newline])
        } else {
            trimmed = data
        }
        let value = try JSONDecoder.appServer.decode(JSONValue.self, from: trimmed)
        messages.append(value)
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
    pollIntervalNanoseconds: UInt64 = 10_000_000,
    _ condition: @escaping () async -> Bool
) async -> Bool {
    var elapsed: UInt64 = 0
    while await !condition() {
        guard elapsed < timeoutNanoseconds else { return false }
        try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        elapsed += pollIntervalNanoseconds
    }
    return true
}
