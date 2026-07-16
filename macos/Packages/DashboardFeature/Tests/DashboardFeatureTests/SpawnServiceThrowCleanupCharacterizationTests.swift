import Foundation
import Testing
import AgentDomain
import CodexAppServerKit
import PTYKit
@testable import DashboardFeature
@testable import SessionFeature

private final class Task10FailingThreadStartTransport: AppServerTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<Data>.Continuation?
    private var closedFlag = false
    let receivedLines: AsyncStream<Data>

    init() {
        var captured: AsyncStream<Data>.Continuation?
        self.receivedLines = AsyncStream { captured = $0 }
        self.continuation = captured
    }

    func send(_ data: Data) async throws {
        let line: Data
        if let newline = data.firstIndex(of: 0x0A) {
            line = Data(data[..<newline])
        } else {
            line = data
        }
        guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any],
              let method = object["method"] as? String,
              let id = object["id"]
        else { return }

        let response: [String: Any]
        if method == "initialize" {
            response = ["jsonrpc": "2.0", "id": id, "result": [
                "codexHome": "/tmp/codex",
                "platformFamily": "mac",
                "platformOs": "macos",
                "userAgent": "codex-test/1",
            ]]
        } else {
            response = ["jsonrpc": "2.0", "id": id, "error": [
                "code": -32000,
                "message": "task-10 scripted thread/start failure",
            ]]
        }
        let payload = try JSONSerialization.data(withJSONObject: response)
        continuation?.yield(payload)
    }

    func close() async {
        lock.withLock { closedFlag = true }
        continuation?.finish()
    }

    func wasClosed() -> Bool {
        lock.withLock { closedFlag }
    }
}

private final class Task10TokenBox: @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?

    func set(_ token: String?) {
        lock.withLock { self.token = token }
    }

    func get() -> String? {
        lock.withLock { token }
    }
}

@Suite(.serialized)
struct SpawnServiceThrowCleanupCharacterizationTests {
    @Test @MainActor
    func appServerStartNewThrowTerminatesRemovesTokenCleansWorkspaceAndDoesNotAppendNode() async throws {
        let workspaceRoot = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(workspaceRoot) }
        let transport = Task10FailingThreadStartTransport()
        let tokenBox = Task10TokenBox()
        let sessionStore = InMemorySessionStore()
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let environment = makeTestEnvironment(
            pty: MockPTYManager(),
            hookStream: hookStream,
            sessions: sessionStore,
            workspaceDirectory: workspaceRoot,
            agentBinaryPaths: [.codex: "/bin/echo"],
            appServerClientFactory: { _, _, _, env, handler in
                tokenBox.set(env["PHLOX_TOKEN"])
                return CodexStructuredAgentClient(
                    client: CodexAppServerClient(transport: transport, serverRequestHandler: handler)
                )
            }
        )
        let dashboard = DashboardViewModel(environment: environment)
        await dashboard.start()
        let nodesBefore = dashboard.sessionNodes.count

        await #expect(throws: (any Error).self) {
            try await dashboard.spawnNewSession(kind: .codex, backend: .appServer)
        }

        #expect(dashboard.sessionNodes.count == nodesBefore)
        try await waitUntil { transport.wasClosed() }
        let capturedToken = try #require(tokenBox.get(), "factory did not receive PHLOX_TOKEN")
        let stillRegistered = await environment.tokenStore.session(forToken: capturedToken)
        #expect(stillRegistered == nil)
        let leftover = (try? FileManager.default.contentsOfDirectory(atPath: workspaceRoot.path)) ?? []
        #expect(leftover.isEmpty)
        #expect(await sessionStore.load().isEmpty)
    }
}
