import Foundation
import Testing
@testable import CodexAppServerKit

private func codexE2EEnabled() -> Bool {
    ProcessInfo.processInfo.environment["PHLOX_CODEX_E2E"] == "1"
}

@Suite("Codex app-server E2E")
struct CodexAppServerE2ETests {
    @Test(.enabled(if: codexE2EEnabled()), .timeLimit(.minutes(2)))
    func initializeThreadTurnReadAndResume() async throws {
        let workdir = FileManager.default.temporaryDirectory
            .appending(path: "phlox-codex-appserver-e2e-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: workdir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workdir) }

        let transport = try ProcessTransport.codexAppServer(workingDirectory: workdir)
        let client = CodexAppServerClient(transport: transport)
        await client.start()
        defer { Task { await client.close() } }

        let initialize = try await client.initialize(
            InitializeParams(clientInfo: ClientInfo(name: "PhloxTests", version: "1"))
        )
        #expect(!initialize.userAgent.isEmpty)

        let started = try await client.threadStart(
            ThreadStartParams(cwd: workdir.path, approvalPolicy: .named("never"))
        )
        let threadId = started.thread.id
        #expect(!threadId.isEmpty)

        var iterator = client.events.makeAsyncIterator()
        _ = try await client.turnStart(
            TurnStartParams(
                threadId: threadId,
                input: [.text("Reply with exactly: PHLOX_E2E_OK")]
            )
        )

        let completed = await waitUntil(timeoutNanoseconds: 90_000_000_000) {
            while let event = await iterator.next() {
                if case .turnCompleted(let completedThreadId, _) = event {
                    return completedThreadId == threadId
                }
            }
            return false
        }
        #expect(completed)

        let read = try await client.threadRead(ThreadReadParams(threadId: threadId, includeTurns: true))
        #expect(read.thread.id == threadId)

        let resumed = try await client.threadResume(ThreadResumeParams(threadId: threadId, cwd: workdir.path))
        #expect(resumed.thread.id == threadId)
    }

    @Test(.enabled(if: codexE2EEnabled()), .timeLimit(.minutes(2)))
    func threadStartWithExplicitSources() async throws {
        let workdir = FileManager.default.temporaryDirectory
            .appending(path: "phlox-codex-appserver-e2e-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: workdir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workdir) }

        let transport = try ProcessTransport.codexAppServer(workingDirectory: workdir)
        let client = CodexAppServerClient(transport: transport)
        await client.start()
        defer { Task { await client.close() } }

        _ = try await client.initialize(
            InitializeParams(clientInfo: ClientInfo(name: "PhloxTests", version: "1"))
        )

        let started = try await client.threadStart(
            ThreadStartParams(
                cwd: workdir.path,
                approvalPolicy: .named("never"),
                threadSource: ThreadSource.user.rawValue,
                sessionStartSource: SessionStartSource.startup.rawValue
            )
        )
        #expect(!started.thread.id.isEmpty)
    }

    @Test(.enabled(if: codexE2EEnabled()), .timeLimit(.minutes(2)))
    func updateThreadSettingsEmitsNotification() async throws {
        let workdir = FileManager.default.temporaryDirectory
            .appending(path: "phlox-codex-appserver-e2e-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: workdir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workdir) }

        let transport = try ProcessTransport.codexAppServer(workingDirectory: workdir)
        let client = CodexAppServerClient(transport: transport)
        await client.start()
        defer { Task { await client.close() } }

        _ = try await client.initialize(
            InitializeParams(
                clientInfo: ClientInfo(name: "PhloxTests", version: "1"),
                capabilities: InitializeCapabilities(experimentalApi: true)
            )
        )

        let models = try await client.listModels(ModelListParams(limit: 50))
        let selectedModel = try #require(models.data.first(where: \.isDefault) ?? models.data.first)
        let profiles = try await client.listPermissionProfiles(PermissionProfileListParams(cwd: workdir.path))
        let selectedProfile = profiles.data.first { $0.id == ":workspace" } ?? profiles.data.first
        let modes = try await client.listCollaborationModes()
        let supportsPlanMode = modes.data.contains { $0.mode == .plan }

        let started = try await client.threadStart(
            ThreadStartParams(cwd: workdir.path, approvalPolicy: .named("never"))
        )
        let threadId = started.thread.id
        #expect(!threadId.isEmpty)

        var iterator = client.events.makeAsyncIterator()
        let collaborationMode = supportsPlanMode
            ? CollaborationMode(
                mode: .plan,
                settings: CollaborationModeSettings(
                    model: selectedModel.id,
                    reasoningEffort: selectedModel.defaultReasoningEffort,
                    developerInstructions: nil
                )
            )
            : nil

        _ = try await client.updateThreadSettings(
            ThreadSettingsUpdateParams(
                threadId: threadId,
                model: selectedModel.id,
                effort: selectedModel.defaultReasoningEffort,
                permissions: selectedProfile?.id,
                collaborationMode: collaborationMode
            )
        )

        let received = await waitUntil(timeoutNanoseconds: 30_000_000_000) {
            while let event = await iterator.next() {
                if case .threadSettingsUpdated(let updatedThreadId, let settings) = event {
                    return updatedThreadId == threadId
                        && settings.model == selectedModel.id
                        && settings.effort == selectedModel.defaultReasoningEffort
                }
            }
            return false
        }
        #expect(received)
    }
}
