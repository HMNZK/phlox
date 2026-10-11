import Foundation
import AgentDomain
import PTYKit
import Testing
@testable import DashboardFeature

@Suite("アプリ終了時のユーザーターミナル停止")
@MainActor
struct UserTerminalShutdownTests {

    // 終了時にプロジェクトのターミナルを止め忘れると、アプリを閉じたあともシェルが孤児プロセスとして残る。
    @Test("プロジェクトのターミナルのシェルが kill される")
    func killsProjectTerminalShells() async throws {
        let pty = MockPTYManager()
        let sessions = ProjectTerminalStore { _ in TerminalPanelSession(controller: makeController(pty: pty)) }
        let tab = sessions.terminal(for: TerminalTabID(), projectID: ProjectID(), workingDirectory: "/tmp")
        try await tab.controller.ensureStarted()
        let tabID = try #require(tab.controller.sessionID)

        await shutdownUserTerminals(sessions: sessions)

        #expect(pty.killedIDs == [tabID])
        #expect(!tab.controller.isRunning)
    }

    @Test("まだ何も作っていなくても落ちない")
    func toleratesMissingTerminals() async {
        await shutdownUserTerminals(sessions: nil)
    }

    private func makeController(pty: any PTYManagerProtocol) -> UserTerminalController {
        UserTerminalController(
            pty: pty, shellPath: "/bin/sh", workingDirectory: "/tmp",
            environment: ["PATH": "/usr/bin:/bin"]
        )
    }
}
