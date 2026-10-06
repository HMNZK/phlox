import Foundation
import AgentDomain
import PTYKit
import Testing
@testable import DashboardFeature

@Suite("アプリ終了時のユーザーターミナル停止")
@MainActor
struct UserTerminalShutdownTests {

    // 終了時に共通ターミナルかタブのシェルを止め忘れると、アプリを閉じたあともシェルが孤児プロセスとして残る。
    @Test("共通ターミナルとセッションのターミナルの両方のシェルが kill される")
    func killsCommonAndSessionShells() async throws {
        let pty = MockPTYManager()
        let common = makeController(pty: pty)
        let sessions = SessionTerminalStore { _ in TerminalPanelSession(controller: makeController(pty: pty)) }
        let tab = sessions.terminal(for: SessionID(), workingDirectory: "/tmp")
        try await common.ensureStarted()
        try await tab.controller.ensureStarted()
        let commonID = try #require(common.sessionID)
        let tabID = try #require(tab.controller.sessionID)

        await shutdownUserTerminals(common: common, sessions: sessions)

        #expect(Set(pty.killedIDs) == Set([commonID, tabID]))
        #expect(!common.isRunning)
        #expect(!tab.controller.isRunning)
    }

    @Test("まだ何も作っていなくても落ちない")
    func toleratesMissingTerminals() async {
        await shutdownUserTerminals(common: nil, sessions: nil)
    }

    private func makeController(pty: any PTYManagerProtocol) -> UserTerminalController {
        UserTerminalController(
            pty: pty, shellPath: "/bin/sh", workingDirectory: "/tmp",
            environment: ["PATH": "/usr/bin:/bin"]
        )
    }
}
