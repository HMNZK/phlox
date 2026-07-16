import Foundation
import Testing
import AgentDomain
import StructuredChatKit
@testable import DashboardFeature
@testable import SessionFeature

private struct CapturedStructuredLaunch: Sendable {
    let ref: AgentRef
    let env: [String: String]
}

private final class StructuredLaunchRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var launches: [CapturedStructuredLaunch] = []

    func record(ref: AgentRef, env: [String: String]) {
        lock.lock()
        launches.append(CapturedStructuredLaunch(ref: ref, env: env))
        lock.unlock()
    }

    func env(for ref: AgentRef) -> [String: String]? {
        lock.lock()
        defer { lock.unlock() }
        return launches.first { $0.ref == ref }?.env
    }
}

@Test @MainActor
func prepareSessionLaunch_sanitizesOnlyCursorPTYEnvironment() async throws {
    let workspaceRoot = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceRoot) }
    let ptyManager = MockPTYManager()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(
        pty: ptyManager,
        hookStream: hookStream,
        workspaceDirectory: workspaceRoot,
        agentBinaryPaths: [
            .codex: "/usr/local/bin/codex",
            .cursor: "/usr/local/bin/cursor-agent",
        ]
    )
    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    try await dashboard.spawnNewSession(kind: .cursor, backend: .pty)
    try await dashboard.spawnNewSession(kind: .claudeCode, backend: .pty)
    try await dashboard.spawnNewSession(kind: .codex, backend: .pty)
    try await waitUntil { ptyManager.spawnCalls.count == 3 }

    let cursorEnv = try #require(ptyManager.spawnCalls.first { $0.command == "/usr/local/bin/cursor-agent" }?.env)
    let claudeEnv = try #require(ptyManager.spawnCalls.first { $0.command == "/usr/local/bin/claude" }?.env)
    let codexEnv = try #require(ptyManager.spawnCalls.first { $0.command == "/usr/local/bin/codex" }?.env)

    let zdotDir = try #require(cursorEnv["ZDOTDIR"])
    #expect(cursorEnv["PATH"] == environment.pathEnvironment)
    #expect(FileManager.default.fileExists(atPath: zdotDir))
    #expect(!FileManager.default.fileExists(atPath: URL(fileURLWithPath: zdotDir).appendingPathComponent(".zshrc").path))
    #expect(claudeEnv["ZDOTDIR"] == nil)
    #expect(codexEnv["ZDOTDIR"] == nil)
}

@Test @MainActor
func prepareSessionLaunch_sanitizesOnlyCursorAppServerEnvironment() async throws {
    let workspaceRoot = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceRoot) }
    let ptyManager = MockPTYManager()
    let recorder = StructuredLaunchRecorder()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(
        pty: ptyManager,
        hookStream: hookStream,
        workspaceDirectory: workspaceRoot,
        agentBinaryPaths: [
            .codex: "/usr/local/bin/codex",
            .cursor: "/usr/local/bin/cursor-agent",
        ],
        appServerClientFactory: { ref, _, _, env, _ in
            recorder.record(ref: ref, env: env)
            return EventYieldingStructuredClient()
        }
    )
    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    try await dashboard.spawnNewSession(kind: .cursor, backend: .appServer)
    try await dashboard.spawnNewSession(kind: .claudeCode, backend: .appServer)
    try await dashboard.spawnNewSession(kind: .codex, backend: .appServer)

    let cursorEnv = try #require(recorder.env(for: .builtin(.cursor)))
    let claudeEnv = try #require(recorder.env(for: .builtin(.claudeCode)))
    let codexEnv = try #require(recorder.env(for: .builtin(.codex)))

    let zdotDir = try #require(cursorEnv["ZDOTDIR"])
    #expect(cursorEnv["PATH"] == environment.pathEnvironment)
    #expect(FileManager.default.fileExists(atPath: zdotDir))
    #expect(!FileManager.default.fileExists(atPath: URL(fileURLWithPath: zdotDir).appendingPathComponent(".zshrc").path))
    #expect(claudeEnv["ZDOTDIR"] == nil)
    #expect(codexEnv["ZDOTDIR"] == nil)
}
