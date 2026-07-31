import Foundation
import Testing
@testable import DashboardFeature

@Suite("Terminal panel view white-box tests")
@MainActor
struct TerminalPanelViewWhiteboxTests {

    @Test("パネル用シェルの cwd はホーム固定（ゲート①決定）")
    func terminalPanelSpawnsInHomeDirectory() throws {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { url.deleteLastPathComponent() }
        let app = try String(
            contentsOf: url.appendingPathComponent("macos/App/PhloxApp.swift"),
            encoding: .utf8
        )

        #expect(app.contains("workingDirectory: home"))
        #expect(!app.contains("workingDirectory: environment.workspaceDirectory.path"))
    }

    @Test("パネルの表示器は同じコントローラを保持し、入出力を TerminalCoordinator へ接続する")
    func panelSessionBindsTheSharedController() async throws {
        let pty = MockPTYManager()
        let controller = UserTerminalController(
            pty: pty,
            shellPath: "/bin/sh",
            workingDirectory: "/tmp",
            environment: ["PATH": "/usr/bin:/bin", "TERM": "xterm-256color"]
        )
        let panel = TerminalPanelSession(controller: controller)

        #expect(panel.controller === controller)
        await panel.ensureStarted()
        try await waitUntil { controller.isRunning }
        let sessionID = try #require(controller.sessionID)

        panel.terminalCoordinator.onInput(Data("echo panel\\n".utf8))
        try await waitUntil { pty.writtenCalls.count == 1 }
        #expect(pty.writtenCalls.first?.0 == Data("echo panel\\n".utf8))

        panel.terminalCoordinator.onResize(58, 40)
        try await waitUntil {
            pty.resizeCalls.last == ResizeCall(id: sessionID, cols: 58, rows: 40)
        }

        pty.emitOutput(for: sessionID, data: Data("panel output\\n".utf8))
        try await waitUntil { panel.terminalCoordinator.visibleText().contains("panel output") }

        await controller.shutdown()
    }

    // ゲート②で独立 Window 方式のプロトタイプを撤去したため、この失効テストも撤去する。
    private func waitUntil(
        timeout: Duration = .seconds(1),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !condition() {
            guard clock.now < deadline else {
                throw TimeoutError()
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private struct TimeoutError: Error {}
}
