import Foundation
import Testing
import AgentDomain
import ControlServer
import DashboardFeature
import StructuredChatKit
import AppBootstrap
import SessionFeature

@MainActor @Suite struct ComposerSettingsHandlerTests {
    @MainActor
    private final class SettingsDashboardStub: ControlActionDashboard {
        let spawnedID = SessionID()
        private(set) var spawnCallCount = 0
        private(set) var appliedModel: (id: SessionID, model: String)?

        var receivedSettings: CodexAppServerSessionSettings?
        var spawnError: (any Error)?
        var settingsOutcome: ControlSettingsApplyOutcome = .applied
        var receivedUpdate: ControlSettingsUpdate?
        var controlProjects: [ControlProject] = []
        var sessionSettings: ControlSessionModelSettings?
        func sessionModelSettings(for id: SessionID) -> ControlSessionModelSettings? { sessionSettings }
        func setSessionSettings(_ settings: ControlSettingsUpdate, for id: SessionID) async -> ControlSettingsApplyOutcome {
            receivedUpdate = settings
            return settingsOutcome
        }
        var controlSessionSummaries: [ControlSessionSummary] = []

        func spawnSession(
            ref: AgentRef,
            from: SessionID?,
            backend: SessionBackend,
            workingDirectory: String?,
            projectID: ProjectID?, initialSettings: CodexAppServerSessionSettings?
        ) async throws -> SessionID {
            spawnCallCount += 1
            receivedSettings = initialSettings
            if let spawnError { throw spawnError }
            return spawnedID
        }

        func setSessionModel(_ model: String, for id: SessionID) async -> ControlSetModelOutcome {
            appliedModel = (id, model)
            return .applied
        }

        func sendMessage(
            to recipient: Recipient,
            text: String,
            submit: Bool,
            from: SessionID?,
            inReplyTo: UUID?,
            images: [ControlImageAttachment]
        ) async -> DashboardViewModel.SendOutcome { .sent }
        func isAuthorizedToRemove(_ id: SessionID, requester: SessionID?) -> Bool { true }
        func removeSession(_ id: SessionID) async -> Bool { true }
        func renameSession(_ id: SessionID, to name: String) {}
        func sessionOutput(for id: SessionID) -> String? { nil }
        func sessionChatMessagesDelta(for id: SessionID, since: String?) -> TranscriptDelta? { nil }
        func waitUntilReady(for id: SessionID, timeout: Duration) async -> DashboardViewModel.ReadinessResult { .ready }
        func waitUntilDone(
            for id: SessionID,
            timeout: Duration,
            sentinel: String?
        ) async -> DashboardViewModel.DoneResult { .done(output: "") }
        func listApprovals() async -> [ApprovalDTO] { [] }
        func respondToApproval(id: String, decision: ApprovalDecision) async -> Bool { true }
        func interruptSession(_ id: SessionID) async -> ControlInterruptOutcome { .accepted }
        func sessionSubAgents(for id: SessionID) -> [SubAgentControlSummary]? { nil }
        func sessionSubAgentMessages(for id: SessionID, subAgentID: String) -> [ChatItem]? { nil }
        func sessionUsage(for id: SessionID) -> ControlSessionUsage? { nil }
    }


    private func handler(_ dashboard: SettingsDashboardStub) -> ControlActionHandler {
        let handler = ControlActionHandler()
        handler.dashboard = dashboard
        return handler
    }

    private func json(_ response: ControlResponse) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: response.body) as? [String: Any])
    }

    private func spawn(_ settings: CodexAppServerSessionSettings?) -> ControlRequest {
        ControlRequest(requester: nil, action: .spawn(ref: .builtin(.claudeCode), backend: .appServer, workingDirectory: nil, projectID: nil, initialSettings: settings))
    }

    @Test func initialSettingsReachSpawnAndSkipLegacyApplier() async {
        let dashboard = SettingsDashboardStub()
        let settings = CodexAppServerSessionSettings(selectedModel: "opus[1m]", selectedEffort: "high", selectedPermissionProfile: "manual", isPlanMode: true)
        let response = await ControlSpawnContext.$model.withValue("sonnet") {
            await handler(dashboard).handle(spawn(settings))
        }
        #expect(response.statusCode == 201)
        #expect(dashboard.receivedSettings == settings)
        #expect(dashboard.appliedModel == nil)
    }

    @Test(arguments: ["effort", "permission"])
    func unknownSpawnValueDoesNotSpawn(field: String) async throws {
        let dashboard = SettingsDashboardStub()
        let settings = CodexAppServerSessionSettings(selectedModel: "opus[1m]", selectedEffort: field == "effort" ? "unknown" : nil, selectedPermissionProfile: field == "permission" ? "plan" : nil)
        let response = await handler(dashboard).handle(spawn(settings))
        #expect(response.statusCode == 400)
        #expect(try json(response)["error"] as? String == "unknown \(field): \(field == "effort" ? "unknown" : "plan")")
        #expect(dashboard.spawnCallCount == 0)
    }

    @Test func initialSettingsFailureMapsTo422() async throws {
        let dashboard = SettingsDashboardStub()
        dashboard.spawnError = ChatLaunchError.settingsNotApplied("rejected")
        let response = await handler(dashboard).handle(spawn(.init(isPlanMode: false)))
        #expect(response.statusCode == 422)
        #expect(try json(response)["error"] as? String == "settings not applied")
    }

    @Test func agentSettingsWireShape() async throws {
        let dashboard = SettingsDashboardStub()
        for kind in AgentKind.allCases {
            let response = await handler(dashboard).handle(ControlRequest(requester: nil, action: .agentSettings(kind: kind)))
            #expect(response.statusCode == 200)
            let body = try json(response)
            let efforts = try #require(body["availableEfforts"] as? [String: [[String: Any]]])
            #expect(Set(efforts.keys) == Set(AgentModelCatalog.models(for: kind).map(\.id)))
            #expect(body["planModeAvailable"] as? Bool == true)
            let permissions = try #require(body["availablePermissions"] as? [[String: Any]])
            if kind == .cursor {
                #expect(permissions.first?["value"] is NSNull)
                #expect(permissions.last?["value"] as? String == "ask")
            }
            if kind == .claudeCode {
                for (model, values) in efforts {
                    #expect(values.count == (model.split(separator: "[").first == "haiku" ? 0 : 5))
                }
                #expect(permissions.compactMap { $0["value"] as? String } == ["acceptEdits", "auto", "bypassPermissions", "manual", "dontAsk"])
            }
        }
    }

    @Test func unsupportedSessionIncludesExplicitNullsAndOldKeys() async throws {
        let dashboard = SettingsDashboardStub()
        let id = SessionID()
        dashboard.controlSessionSummaries = [.init(id: id, name: "test", agentID: "codex", status: .idle, workspaceName: "test")]
        let response = await handler(dashboard).handle(ControlRequest(requester: nil, action: .sessionSettings(id: id)))
        #expect(response.statusCode == 200)
        let body = try json(response)
        for key in ["selectedModel", "selectedEffort", "selectedPermission"] { #expect(body[key] is NSNull) }
        for key in ["availableModels", "availableEfforts", "availablePermissions"] { #expect((body[key] as? [Any])?.isEmpty == true) }
        for key in ["planMode", "planModeAvailable"] { #expect(body[key] as? Bool == false) }
    }

    @Test func supportedSessionEncodesComposerValuesAlongsideModels() async throws {
        let dashboard = SettingsDashboardStub()
        dashboard.sessionSettings = .init(selectedModel: "sonnet", availableModels: [.init(id: "sonnet", displayName: "Sonnet")],
            selectedEffort: "high", availableEfforts: [.init(value: "high", displayName: "高")],
            selectedPermission: "manual", availablePermissions: [.init(value: "manual", displayName: "Manual")],
            planMode: true, planModeAvailable: true)
        let response = await handler(dashboard).handle(ControlRequest(requester: nil, action: .sessionSettings(id: SessionID())))
        #expect(response.statusCode == 200)
        let body = try json(response)
        #expect(body["selectedModel"] as? String == "sonnet")
        #expect((body["availableModels"] as? [[String: String]]) == [["id": "sonnet", "displayName": "Sonnet"]])
        #expect(body["selectedEffort"] as? String == "high")
        #expect((body["availableEfforts"] as? [[String: String]]) == [["value": "high", "displayName": "高"]])
        #expect(body["selectedPermission"] as? String == "manual")
        #expect((body["availablePermissions"] as? [[String: String]]) == [["value": "manual", "displayName": "Manual"]])
        #expect(body["planMode"] as? Bool == true)
        #expect(body["planModeAvailable"] as? Bool == true)
    }

    @Test func patchMapsEveryOutcome() async throws {
        let dashboard = SettingsDashboardStub()
        let cases: [(ControlSettingsApplyOutcome, Int, String?)] = [
            (.applied, 200, nil), (.notFound, 404, nil), (.notReady, 425, "session not ready"),
            (.busy, 409, "settings update in progress"), (.failed, 500, nil),
            (.invalidValue("effort"), 400, "unknown effort: high"),
            (.invalidValue("permission"), 400, "unknown permission: null"),
            (.unsupported("effort"), 409, "effort unsupported"),
            (.unsupported("permission"), 409, "permission unsupported"),
            (.unsupported("planMode"), 409, "plan mode unavailable"),
        ]
        let update = ControlSettingsUpdate(effort: "high", permission: .some(nil), planMode: true)
        for (outcome, status, error) in cases {
            dashboard.settingsOutcome = outcome
            let response = await handler(dashboard).handle(ControlRequest(requester: nil, action: .setSettings(id: SessionID(), settings: update)))
            #expect(response.statusCode == status)
            #expect(dashboard.receivedUpdate == update)
            if let error { #expect(try json(response)["error"] as? String == error) }
            else { #expect(response.body.isEmpty) }
        }
    }

    @Test func projectsPreserveOrderAndEmptyList() async throws {
        let dashboard = SettingsDashboardStub()
        for projects in [[], [ControlProject(id: "B", name: "Second"), ControlProject(id: "A", name: "First")]] {
            dashboard.controlProjects = projects
            let response = await handler(dashboard).handle(ControlRequest(requester: nil, action: .listProjects))
            #expect(response.statusCode == 200)
            let values = try #require(try json(response)["projects"] as? [[String: String]])
            #expect(values == projects.map { ["id": $0.id, "name": $0.name] })
        }
    }
}
