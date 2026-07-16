import AgentDomain
import Foundation
import Testing
@testable import PTYKit

private let testEnv: [String: String] = [
    "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
]

private func withTimeout<T: Sendable>(
    seconds: Double = 5,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw TimeoutError()
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

private struct TimeoutError: Error {}

@Test func resizeSucceedsForActiveSession() async throws {
    try await withTimeout {
        let manager = PTYManager()
        let id = try await manager.spawn(
            command: "/bin/sh",
            args: ["-c", "exec sleep 5"],
            env: testEnv
        )

        try await manager.resize(id, cols: 120, rows: 40)
        await manager.kill(id)
    }
}

@Test func resizeToUnknownSessionThrowsSessionNotFound() async throws {
    let manager = PTYManager()
    let bogusID = SessionID()
    await #expect(throws: PTYError.sessionNotFound) {
        try await manager.resize(bogusID, cols: 80, rows: 24)
    }
}
