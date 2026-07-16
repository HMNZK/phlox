import Foundation
import Testing
import AgentDomain
import HookServer
import PTYKit
@testable import DashboardFeature

// MARK: - Helpers

private let orchestrationGuideEnvKey = "PHLOX_ORCHESTRATION_GUIDE"

private func makePlannerEnvironment(
    claudeBinaryPath: String = "/usr/local/bin/claude",
    agentBinaryPaths: [AgentKind: String] = [:],
    hookURL: URL = URL(string: "http://127.0.0.1:8080/hook")!,
    claudeSettingsURL: URL = URL(fileURLWithPath: "/tmp/agent-dashboard-test-hooks.json"),
    claudeSettingsRestrictedURL: URL? = nil,
    hookDispatcherPath: String = "/tmp/agent-dashboard-test-dispatcher.sh",
    pathEnvironment: String = "/usr/local/bin:/usr/bin:/bin",
    workspaceDirectory: URL = URL(fileURLWithPath: "/tmp/agent-dashboard-test-workspace"),
    controlURL: URL = URL(string: "http://127.0.0.1:9999")!,
    tokenStore: SessionTokenStore = SessionTokenStore(),
    messages: MockMessageStore = MockMessageStore(),
    cliPath: String = "/tmp/agent-dashboard-test-cli"
) -> AppEnvironment {
    AppEnvironment(
        pty: MockPTYManager(),
        hook: MockHookServer(events: AsyncStream { _ in }),
        hookURL: hookURL,
        claudeSettingsURL: claudeSettingsURL,
        claudeSettingsRestrictedURL: claudeSettingsRestrictedURL,
        hookDispatcherPath: hookDispatcherPath,
        claudeBinaryPath: claudeBinaryPath,
        pathEnvironment: pathEnvironment,
        workspaceDirectory: workspaceDirectory,
        agentBinaryPaths: agentBinaryPaths,
        controlURL: controlURL,
        tokenStore: tokenStore,
        messages: messages,
        cliPath: cliPath
    )
}

// MARK: - Tests

@Test func plan_claudeCode_includesSettingsAndHookURL() throws {
    let hookURL = URL(string: "http://127.0.0.1:54321/hook")!
    let settingsURL = URL(fileURLWithPath: "/tmp/test-hooks.json")
    let claudePath = "/usr/local/bin/claude"
    let sessionID = SessionID()
    let environment = makePlannerEnvironment(
        claudeBinaryPath: claudePath,
        hookURL: hookURL,
        claudeSettingsURL: settingsURL
    )

    let plan = try AgentLaunchPlanner().plan(
        kind: .claudeCode,
        environment: environment,
        sessionID: sessionID,
        sessionToken: "test-token"
    )

    #expect(plan.command == claudePath)
    #expect(plan.args == ["--settings", settingsURL.path])
    #expect(plan.env["CLAUDE_HOOKS_URL"] == hookURL.absoluteString)
    #expect(plan.env[orchestrationGuideEnvKey] == nil)
    #expect(plan.env["PHLOX_SESSION_ID"] == sessionID.rawValue.uuidString)
    #expect(plan.env["TERM"] == "xterm-256color")
    #expect(plan.env["COLORTERM"] == "truecolor")
    #expect(plan.scrollbackPolicy == .keep)
    #expect(plan.statusBootstrap == .viaHook)
    #expect(plan.kind == .claudeCode)
    #expect(plan.workingDirectory == environment.sessionWorkspaceDirectory(for: sessionID).path)
}

@Test func plan_allBuiltinKindsAndBackends_doNotInjectGuide() throws {
    let settingsURL = URL(fileURLWithPath: "/tmp/test-hooks.json")
    let hookURL = URL(string: "http://127.0.0.1:54321/hook")!
    let environment = makePlannerEnvironment(
        agentBinaryPaths: [
            .codex: "/usr/local/bin/codex",
            .cursor: "/usr/local/bin/cursor-agent",
        ],
        hookURL: hookURL,
        claudeSettingsURL: settingsURL
    )

    for kind in AgentKind.allCases {
        for backend in [SessionBackend.pty, .appServer] {
            let plan = try AgentLaunchPlanner().plan(
                kind: kind,
                environment: environment,
                sessionID: SessionID(),
                sessionToken: "test-token",
                backend: backend
            )

            #expect(!plan.args.contains("--append-system-prompt"))
            #expect(plan.env[orchestrationGuideEnvKey] == nil)

            if backend == .pty {
                switch kind {
                case .claudeCode:
                    #expect(plan.args == ["--settings", settingsURL.path])
                    #expect(plan.env["CLAUDE_HOOKS_URL"] == hookURL.absoluteString)
                case .codex, .cursor:
                    #expect(plan.env["CLAUDE_HOOKS_URL"] == hookURL.absoluteString)
                }
            } else {
                #expect(plan.env["CLAUDE_HOOKS_URL"] == nil)
                #expect(!plan.args.contains("--settings"))
            }
        }
    }
}

@Test func plan_claudeCode_bypassEnabledSelectsPrimarySettingsPath() throws {
    let settingsURL = URL(fileURLWithPath: "/tmp/test-hooks.json")
    let restrictedSettingsURL = URL(fileURLWithPath: "/tmp/test-hooks-restricted.json")
    #expect(settingsURL != restrictedSettingsURL)
    let environment = makePlannerEnvironment(
        claudeSettingsURL: settingsURL,
        claudeSettingsRestrictedURL: restrictedSettingsURL
    )

    let plan = try AgentLaunchPlanner().plan(
        kind: .claudeCode,
        environment: environment,
        sessionID: SessionID(),
        sessionToken: "test-token",
        bypassEnabled: true
    )

    #expect(plan.args == ["--settings", settingsURL.path])
}

@Test func plan_claudeCode_bypassDisabledSelectsRestrictedSettingsPath() throws {
    let settingsURL = URL(fileURLWithPath: "/tmp/test-hooks.json")
    let restrictedSettingsURL = URL(fileURLWithPath: "/tmp/test-hooks-restricted.json")
    #expect(settingsURL != restrictedSettingsURL)
    let environment = makePlannerEnvironment(
        claudeSettingsURL: settingsURL,
        claudeSettingsRestrictedURL: restrictedSettingsURL
    )

    let plan = try AgentLaunchPlanner().plan(
        kind: .claudeCode,
        environment: environment,
        sessionID: SessionID(),
        sessionToken: "test-token",
        bypassEnabled: false
    )

    #expect(plan.args == ["--settings", restrictedSettingsURL.path])
}

@Test func plan_codex_setsHookURLWithoutSettingsFlag() throws {
    let hookURL = URL(string: "http://127.0.0.1:54321/hook")!
    let codexPath = "/usr/local/bin/codex"
    let sessionID = SessionID()
    let environment = makePlannerEnvironment(
        agentBinaryPaths: [.codex: codexPath],
        hookURL: hookURL
    )

    let plan = try AgentLaunchPlanner().plan(
        kind: .codex,
        environment: environment,
        sessionID: sessionID,
        sessionToken: "test-token"
    )

    #expect(plan.command == codexPath)
    #expect(plan.args == ["--dangerously-bypass-approvals-and-sandbox", "--dangerously-bypass-hook-trust"])
    #expect(plan.env["CLAUDE_HOOKS_URL"] == hookURL.absoluteString)
    #expect(plan.env[orchestrationGuideEnvKey] == nil)
    #expect(!plan.args.contains("--settings"))
    #expect(plan.scrollbackPolicy == .keep)
    #expect(plan.statusBootstrap == .idleOnSpawnComplete)
    #expect(plan.kind == .codex)
    #expect(plan.workingDirectory == environment.sessionWorkspaceDirectory(for: sessionID).path)
}

@Test func plan_codex_userHooksEnabled_omitsOnlyHookTrustBypassArg() throws {
    let codexPath = "/usr/local/bin/codex"
    let environment = makePlannerEnvironment(agentBinaryPaths: [.codex: codexPath])

    let plan = try AgentLaunchPlanner().plan(
        kind: .codex,
        environment: environment,
        sessionID: SessionID(),
        sessionToken: "test-token",
        codexUserHooksEnabled: true
    )

    #expect(plan.command == codexPath)
    #expect(plan.args == ["--dangerously-bypass-approvals-and-sandbox"])
    #expect(plan.env["CLAUDE_HOOKS_URL"] == environment.hookURL.absoluteString)
}

@Test func plan_codex_bypassDisabled_omitsBypassArgs() throws {
    let codexPath = "/usr/local/bin/codex"
    let environment = makePlannerEnvironment(agentBinaryPaths: [.codex: codexPath])

    let plan = try AgentLaunchPlanner().plan(
        kind: .codex,
        environment: environment,
        sessionID: SessionID(),
        sessionToken: "test-token",
        bypassEnabled: false
    )

    #expect(plan.command == codexPath)
    #expect(plan.args == [])
    #expect(plan.env["CLAUDE_HOOKS_URL"] == environment.hookURL.absoluteString)
}

@Test func plan_cursor_setsHookURLWithoutSettingsOrBypassFlag() throws {
    let hookURL = URL(string: "http://127.0.0.1:54321/hook")!
    let cursorPath = "/usr/local/bin/cursor-agent"
    let sessionID = SessionID()
    let environment = makePlannerEnvironment(
        agentBinaryPaths: [.cursor: cursorPath],
        hookURL: hookURL
    )

    let plan = try AgentLaunchPlanner().plan(
        kind: .cursor,
        environment: environment,
        sessionID: sessionID,
        sessionToken: "test-token"
    )

    #expect(plan.command == cursorPath)
    #expect(plan.args == ["--force", "--sandbox", "disabled"])
    #expect(plan.env["CLAUDE_HOOKS_URL"] == hookURL.absoluteString)
    #expect(plan.env[orchestrationGuideEnvKey] == nil)
    #expect(!plan.args.contains("--settings"))
    #expect(!plan.args.contains("--dangerously-bypass-hook-trust"))
    #expect(plan.scrollbackPolicy == .keep)
    #expect(plan.statusBootstrap == .idleOnSpawnComplete)
    #expect(plan.kind == .cursor)
    #expect(plan.workingDirectory == environment.sessionWorkspaceDirectory(for: sessionID).path)
}

@Test func plan_cursor_bypassDisabled_omitsBypassArgs() throws {
    let cursorPath = "/usr/local/bin/cursor-agent"
    let environment = makePlannerEnvironment(agentBinaryPaths: [.cursor: cursorPath])

    let plan = try AgentLaunchPlanner().plan(
        kind: .cursor,
        environment: environment,
        sessionID: SessionID(),
        sessionToken: "test-token",
        bypassEnabled: false
    )

    #expect(plan.command == cursorPath)
    #expect(plan.args == [])
    #expect(plan.env["CLAUDE_HOOKS_URL"] == environment.hookURL.absoluteString)
}

@Test func plan_claudeCode_newSessionWithResumeID_addsSessionIDFlag() throws {
    let settingsURL = URL(fileURLWithPath: "/tmp/test-hooks.json")
    let sessionID = SessionID(rawValue: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!)
    let resumeID = sessionID.rawValue.uuidString.lowercased()
    let environment = makePlannerEnvironment(claudeSettingsURL: settingsURL)

    let plan = try AgentLaunchPlanner().plan(
        kind: .claudeCode,
        environment: environment,
        sessionID: sessionID,
        sessionToken: "test-token",
        launchMode: .newSession(resumeID: resumeID)
    )

    #expect(plan.args == [
        "--settings",
        settingsURL.path,
        "--session-id",
        resumeID,
    ])
    #expect(!plan.args.contains("--resume"))
}

@Test func plan_claudeCode_resume_addsResumeFlagWithoutSessionIDFlag() throws {
    let settingsURL = URL(fileURLWithPath: "/tmp/test-hooks.json")
    let resumeID = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    let environment = makePlannerEnvironment(claudeSettingsURL: settingsURL)

    let plan = try AgentLaunchPlanner().plan(
        kind: .claudeCode,
        environment: environment,
        sessionID: SessionID(),
        sessionToken: "test-token",
        launchMode: .resume(resumeID: resumeID)
    )

    #expect(plan.args == [
        "--settings",
        settingsURL.path,
        "--resume",
        resumeID,
    ])
    #expect(!plan.args.contains("--session-id"))
}

@Test func plan_cursor_newSessionWithResumeID_addsResumeFlag() throws {
    let cursorPath = "/usr/local/bin/cursor-agent"
    let resumeID = "cursor-chat-123"
    let environment = makePlannerEnvironment(agentBinaryPaths: [.cursor: cursorPath])

    let plan = try AgentLaunchPlanner().plan(
        kind: .cursor,
        environment: environment,
        sessionID: SessionID(),
        sessionToken: "test-token",
        launchMode: .newSession(resumeID: resumeID)
    )

    #expect(plan.command == cursorPath)
    #expect(plan.args == ["--force", "--sandbox", "disabled", "--resume", resumeID])
}

@Test func plan_cursor_resume_addsResumeFlag() throws {
    let resumeID = "cursor-chat-456"
    let environment = makePlannerEnvironment(agentBinaryPaths: [.cursor: "/usr/local/bin/cursor-agent"])

    let plan = try AgentLaunchPlanner().plan(
        kind: .cursor,
        environment: environment,
        sessionID: SessionID(),
        sessionToken: "test-token",
        launchMode: .resume(resumeID: resumeID)
    )

    #expect(plan.args == ["--force", "--sandbox", "disabled", "--resume", resumeID])
}

@Test func plan_codex_resume_usesResumeSubcommandBeforeBypassFlags() throws {
    let codexPath = "/usr/local/bin/codex"
    let resumeID = "codex-session-123"
    let environment = makePlannerEnvironment(agentBinaryPaths: [.codex: codexPath])

    let plan = try AgentLaunchPlanner().plan(
        kind: .codex,
        environment: environment,
        sessionID: SessionID(),
        sessionToken: "test-token",
        launchMode: .resume(resumeID: resumeID)
    )

    #expect(plan.command == codexPath)
    #expect(plan.args == [
        "resume",
        resumeID,
        "--dangerously-bypass-approvals-and-sandbox",
        "--dangerously-bypass-hook-trust",
    ])
}

@Test func plan_codex_resumeWithBypassDisabled_keepsResumeSubcommandOrder() throws {
    let codexPath = "/usr/local/bin/codex"
    let resumeID = "codex-session-123"
    let environment = makePlannerEnvironment(agentBinaryPaths: [.codex: codexPath])

    let plan = try AgentLaunchPlanner().plan(
        kind: .codex,
        environment: environment,
        sessionID: SessionID(),
        sessionToken: "test-token",
        launchMode: .resume(resumeID: resumeID),
        bypassEnabled: false
    )

    #expect(plan.command == codexPath)
    #expect(plan.args == ["resume", resumeID])
}

@Test(arguments: [AgentKind.claudeCode, AgentKind.cursor, AgentKind.codex])
func plan_newSessionWithoutResumeID_preservesFallbackArgs(kind: AgentKind) throws {
    let agentBinaryPaths: [AgentKind: String] = switch kind {
    case .claudeCode: [:]
    case .codex: [.codex: "/usr/local/bin/codex"]
    case .cursor: [.cursor: "/usr/local/bin/cursor-agent"]
    }
    let environment = makePlannerEnvironment(agentBinaryPaths: agentBinaryPaths)

    let plan = try AgentLaunchPlanner().plan(
        kind: kind,
        environment: environment,
        sessionID: SessionID(),
        sessionToken: "test-token",
        launchMode: .newSession()
    )

    switch kind {
    case .claudeCode:
        #expect(!plan.args.contains("--session-id"))
        #expect(!plan.args.contains("--resume"))
    case .cursor:
        #expect(plan.args == ["--force", "--sandbox", "disabled"])
    case .codex:
        #expect(plan.args == ["--dangerously-bypass-approvals-and-sandbox", "--dangerously-bypass-hook-trust"])
    }
}

@Test func plan_missingBinary_throwsBinaryNotFound() {
    let environment = makePlannerEnvironment()
    let sessionID = SessionID()

    #expect(throws: AgentLaunchPlannerError.self) {
        try AgentLaunchPlanner().plan(
            kind: .cursor,
            environment: environment,
            sessionID: sessionID,
            sessionToken: "test-token"
        )
    }
}

@Test(arguments: [AgentKind.claudeCode, AgentKind.codex, AgentKind.cursor])
func plan_allKinds_includesDashboardMessagingEnvKeys(kind: AgentKind) throws {
    let token = "my-session-token"
    let controlURL = URL(string: "http://127.0.0.1:9999")!
    let cliPath = "/tmp/agent-dashboard-test-cli"
    let agentBinaryPaths: [AgentKind: String] = switch kind {
    case .claudeCode: [:]
    case .codex: [.codex: "/usr/local/bin/codex"]
    case .cursor: [.cursor: "/usr/local/bin/cursor-agent"]
    }
    let environment = makePlannerEnvironment(
        agentBinaryPaths: agentBinaryPaths,
        controlURL: controlURL,
        cliPath: cliPath
    )

    let plan = try AgentLaunchPlanner().plan(
        kind: kind,
        environment: environment,
        sessionID: SessionID(),
        sessionToken: token
    )

    #expect(plan.env["PHLOX_API_URL"] == controlURL.absoluteString)
    #expect(plan.env["PHLOX_TOKEN"] == token)
    #expect(plan.env["PHLOX_CLI"] == cliPath)
}

@Test func plan_extraEnvInjectsOnlyMissingKeys() throws {
    let cliPath = "/tmp/agent-dashboard-test-cli"
    let environment = makePlannerEnvironment(cliPath: cliPath)

    let plan = try AgentLaunchPlanner().plan(
        kind: .claudeCode,
        environment: environment,
        sessionID: SessionID(),
        sessionToken: "test-token",
        extraEnv: [
            "PHLOX_CUSTOM_CONTEXT": "/tmp/phlox/context.json",
            "PHLOX_CLI": "/tmp/should-not-override",
        ]
    )

    #expect(plan.env["PHLOX_CUSTOM_CONTEXT"] == "/tmp/phlox/context.json")
    #expect(plan.env["PHLOX_CLI"] == cliPath)
}

@Test func test_cursor_profile_postSpawnReset_isNil() throws {
    let cursorPath = "/usr/local/bin/cursor-agent"
    let environment = makePlannerEnvironment(
        agentBinaryPaths: [.cursor: cursorPath]
    )

    let plan = try AgentLaunchPlanner().plan(
        kind: .cursor,
        environment: environment,
        sessionID: SessionID(),
        sessionToken: "test-token"
    )

    #expect(plan.postSpawnReset == nil)
}

@Test func test_codex_profile_does_not_set_postSpawnReset() throws {
    let environment = makePlannerEnvironment(
        agentBinaryPaths: [.codex: "/usr/local/bin/codex"]
    )

    let plan = try AgentLaunchPlanner().plan(
        kind: .codex,
        environment: environment,
        sessionID: SessionID(),
        sessionToken: "test-token"
    )

    #expect(plan.postSpawnReset == nil)
}

@Test func test_cursor_profile_setsDebugDumpFalse() throws {
    let environment = makePlannerEnvironment(
        agentBinaryPaths: [.cursor: "/usr/local/bin/cursor-agent"]
    )

    let plan = try AgentLaunchPlanner().plan(
        kind: .cursor,
        environment: environment,
        sessionID: SessionID(),
        sessionToken: "test-token"
    )

    #expect(plan.debugDump == false)
}

@Test func test_codex_profile_setsDebugDumpFalse() throws {
    let environment = makePlannerEnvironment(
        agentBinaryPaths: [.codex: "/usr/local/bin/codex"]
    )

    let plan = try AgentLaunchPlanner().plan(
        kind: .codex,
        environment: environment,
        sessionID: SessionID(),
        sessionToken: "test-token"
    )

    #expect(plan.debugDump == false)
}

@Test func test_claudeCode_profile_setsDebugDumpFalse() throws {
    let environment = makePlannerEnvironment()

    let plan = try AgentLaunchPlanner().plan(
        kind: .claudeCode,
        environment: environment,
        sessionID: SessionID(),
        sessionToken: "test-token"
    )

    #expect(plan.debugDump == false)
}

@Test func test_claudeCode_profile_does_not_set_postSpawnReset() throws {
    let environment = makePlannerEnvironment()

    let plan = try AgentLaunchPlanner().plan(
        kind: .claudeCode,
        environment: environment,
        sessionID: SessionID(),
        sessionToken: "test-token"
    )

    #expect(plan.postSpawnReset == nil)
}

// MARK: - チャットモード（appServer）

@Test func plan_claudeCode_appServerDoesNotCarryGuideEnv() throws {
    let environment = makePlannerEnvironment()

    let plan = try AgentLaunchPlanner().plan(
        kind: .claudeCode,
        environment: environment,
        sessionID: SessionID(),
        sessionToken: "test-token",
        backend: .appServer
    )

    #expect(plan.env[orchestrationGuideEnvKey] == nil)
    // planner はチャットモードでは settings・hook URL を載せない。
    #expect(!plan.args.contains("--append-system-prompt"))
    #expect(!plan.args.contains("--settings"))
    #expect(plan.env["CLAUDE_HOOKS_URL"] == nil)
}

@Test func plan_codex_appServerDoesNotCarryGuideEnv() throws {
    let environment = makePlannerEnvironment(agentBinaryPaths: [.codex: "/usr/local/bin/codex"])

    let plan = try AgentLaunchPlanner().plan(
        kind: .codex,
        environment: environment,
        sessionID: SessionID(),
        sessionToken: "test-token",
        backend: .appServer
    )

    #expect(plan.env[orchestrationGuideEnvKey] == nil)
    #expect(plan.env["CLAUDE_HOOKS_URL"] == nil)
}

@Test func plan_cursor_appServerDoesNotCarryGuideEnv() throws {
    let environment = makePlannerEnvironment(agentBinaryPaths: [.cursor: "/usr/local/bin/cursor-agent"])

    let plan = try AgentLaunchPlanner().plan(
        kind: .cursor,
        environment: environment,
        sessionID: SessionID(),
        sessionToken: "test-token",
        backend: .appServer
    )

    #expect(plan.env[orchestrationGuideEnvKey] == nil)
}

@Test func plan_missingBinary_throwsCorrectKind() {
    let environment = makePlannerEnvironment()
    let sessionID = SessionID()

    do {
        _ = try AgentLaunchPlanner().plan(
            kind: .codex,
            environment: environment,
            sessionID: sessionID,
            sessionToken: "test-token"
        )
        Issue.record("Expected binaryNotFound error")
    } catch AgentLaunchPlannerError.binaryNotFound(let kind) {
        #expect(kind == .codex)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}
