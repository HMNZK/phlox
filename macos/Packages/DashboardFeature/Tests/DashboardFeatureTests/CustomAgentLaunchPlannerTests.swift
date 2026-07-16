import AgentDomain
import Foundation
import HookServer
import PTYKit
import Testing
@testable import DashboardFeature

private func temporaryCustomAgentsURL() -> URL {
    FileManager.default.temporaryDirectory
        .appending(path: "DashboardFeatureTests-agents-\(UUID().uuidString).json")
}

private func removeCustomAgentsFile(at url: URL) {
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    do {
        try FileManager.default.removeItem(at: url)
    } catch {
        Issue.record("Failed to remove test file \(url.path): \(error)")
    }
}

private func makeCustomPlannerEnvironment(
    descriptor: AgentDescriptor,
    binaryPath: String
) -> AppEnvironment {
    AppEnvironment(
        pty: MockPTYManager(),
        hook: MockHookServer(events: AsyncStream { _ in }),
        hookURL: URL(string: "http://127.0.0.1:8080/hook")!,
        claudeSettingsURL: URL(fileURLWithPath: "/tmp/custom-agent-test-hooks.json"),
        hookDispatcherPath: "/tmp/custom-agent-test-dispatcher.sh",
        claudeBinaryPath: "/usr/local/bin/claude",
        pathEnvironment: "/usr/local/bin:/usr/bin:/bin",
        workspaceDirectory: URL(fileURLWithPath: "/tmp/custom-agent-test-workspace"),
        customAgentBinaryPaths: [descriptor.ref.id: binaryPath],
        agentCatalog: AgentCatalog(customDescriptors: [descriptor]),
        controlURL: URL(string: "http://127.0.0.1:9999")!,
        tokenStore: SessionTokenStore(),
        messages: MockMessageStore(),
        cliPath: "/tmp/custom-agent-test-cli"
    )
}

@Test func plan_customAgentLoadedFromJSON_usesDescriptorLaunchSpecAndIdleBootstrap() throws {
    let url = temporaryCustomAgentsURL()
    defer { removeCustomAgentsFile(at: url) }
    let json = """
    {
      "agents": [
        {
          "id": "aider",
          "displayName": "Aider",
          "binaryName": "aider",
          "symbolName": "wrench.and.screwdriver",
          "colorHex": "#E5A53F",
          "baseArgs": ["--model", "sonnet"],
          "bypassArgs": ["--yes-always"],
          "bypassEnv": {"AIDER_AUTO_COMMITS": "0"},
          "statusBootstrap": "idleOnSpawnComplete",
          "resume": {"mode": "flag", "args": ["--restore"]}
        }
      ]
    }
    """
    try Data(json.utf8).write(to: url, options: .atomic)
    let descriptor = try #require(CustomAgentRegistryLoader.loadDescriptors(from: url, log: { _ in }).first)
    let binaryPath = "/opt/homebrew/bin/aider"
    let environment = makeCustomPlannerEnvironment(descriptor: descriptor, binaryPath: binaryPath)
    let sessionID = SessionID()

    let plan = try AgentLaunchPlanner().plan(
        ref: .custom("aider"),
        environment: environment,
        sessionID: sessionID,
        sessionToken: "custom-token"
    )

    #expect(plan.command == binaryPath)
    #expect(plan.args == ["--model", "sonnet", "--yes-always"])
    #expect(plan.env["AIDER_AUTO_COMMITS"] == "0")
    #expect(plan.env["PHLOX_SESSION_ID"] == sessionID.rawValue.uuidString)
    #expect(plan.env["PHLOX_TOKEN"] == "custom-token")
    #expect(plan.ref == .custom("aider"))
    #expect(plan.descriptor == descriptor)
    #expect(plan.statusBootstrap == .idleOnSpawnComplete)
    #expect(plan.scrollbackPolicy == .keep)
    #expect(plan.postSpawnReset == nil)
    #expect(plan.debugDump == false)
}
