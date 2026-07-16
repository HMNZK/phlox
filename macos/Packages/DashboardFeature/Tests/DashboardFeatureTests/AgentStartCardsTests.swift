import Foundation
import AgentDomain
import Testing
@testable import DashboardFeature
@testable import SessionFeature

@Test func agentStartCardsModel_preservesAvailableOrder() {
    let cards = AgentStartCardsModel.cards(available: [.claudeCode, .codex, .cursor])
    #expect(cards.map(\.kind) == [.claudeCode, .codex, .cursor])
}

@Test func agentStartCardsModel_emptyAvailable_returnsEmpty() {
    #expect(AgentStartCardsModel.cards(available: []).isEmpty)
}

@Test @MainActor
func agentStartCardSelection_spawnUsesRequestedKind() async throws {
    let suite = "agent-start-cards-terminal-pref-\(UUID().uuidString)"
    setenv("PHLOX_DEFAULTS_SUITE", suite, 1)
    defer {
        unsetenv("PHLOX_DEFAULTS_SUITE")
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }

    let defaults = UserDefaults(suiteName: suite)!
    defaults.set(
        DefaultSessionBackendPreference.terminal.rawValue,
        forKey: DefaultSessionBackendPreference.storageKey
    )

    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

    let projectURL = workspaceURL.appendingPathComponent("project", isDirectory: true)
    try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let dashboard = DashboardViewModel(
        environment: makeTestEnvironment(
            pty: MockPTYManager(),
            hookStream: hookStream,
            workspaceDirectory: workspaceURL,
            agentBinaryPaths: [.codex: "/bin/echo"]
        )
    )
    await dashboard.start()

    let projectID = try #require(dashboard.addProject(name: "Project", directoryPath: projectURL.path))

    let newID = try await AgentStartCardSelection.spawnNewSession(
        kind: .codex,
        viewModel: dashboard,
        selectedSessionID: nil
    )

    let session = try #require(dashboard.sessionNode(id: newID))
    #expect(session.agentRef.builtinKind == .codex)
    #expect(session.projectID == projectID)
}
