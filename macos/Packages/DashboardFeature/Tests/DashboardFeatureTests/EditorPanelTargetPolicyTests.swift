import AgentDomain
import Testing
@testable import DashboardFeature

@Suite("EditorPanelTargetPolicy")
struct EditorPanelTargetPolicyTests {
    private func workspace(
        _ sessionID: SessionID,
        _ workingDirectory: String,
        isActive: Bool = true
    ) -> SessionWorkspace {
        SessionWorkspace(
            sessionID: sessionID,
            workingDirectory: workingDirectory,
            isActive: isActive
        )
    }

    @Test func 同一プロジェクトの別セッションへ切り替えるとtargetが変わる() {
        let first = SessionID()
        let second = SessionID()
        let workspaces = [
            workspace(first, "/tmp/editor-target/repository"),
            workspace(second, "/tmp/editor-target/repository"),
        ]

        let firstTarget = EditorPanelTargetPolicy.target(
            selectedSessionID: first,
            workspaces: workspaces
        )
        let secondTarget = EditorPanelTargetPolicy.target(
            selectedSessionID: second,
            workspaces: workspaces
        )

        #expect(firstTarget != secondTarget)
        #expect(firstTarget.selectedSessionID == first)
        #expect(secondTarget.selectedSessionID == second)
        #expect(firstTarget.workingDirectory == secondTarget.workingDirectory)
    }

    @Test func 無関係なセッションが増減終了してもtargetは変わらない() {
        let selected = SessionID()
        let unrelated = SessionID()
        let anotherUnrelated = SessionID()
        let selectedWorkspace = workspace(selected, "/tmp/editor-target/repository")

        let before = EditorPanelTargetPolicy.target(
            selectedSessionID: selected,
            workspaces: [
                selectedWorkspace,
                workspace(unrelated, "/tmp/editor-target/other"),
            ]
        )
        let afterSpawnAndExit = EditorPanelTargetPolicy.target(
            selectedSessionID: selected,
            workspaces: [
                selectedWorkspace,
                workspace(unrelated, "/tmp/editor-target/other", isActive: false),
                workspace(anotherUnrelated, "/tmp/editor-target/another"),
            ]
        )

        #expect(before == afterSpawnAndExit)
    }

}
