import Foundation
import Testing
import AgentDomain
@testable import DashboardFeature

@Suite("隠れたタブの対応待ち（C7）")
struct HiddenAttentionSummaryTests {

    @Test("種類がひとつならその状態、件数つき")
    func singleKind() {
        let summary = HiddenAttentionSummary.make(hiddenStates: [.question, .running, .question])

        #expect(summary == HiddenAttentionSummary(kind: .question, count: 2))
    }

    @Test("種類が混ざれば種類なし（「対応待ち」と出す）")
    func mixedKinds() {
        let summary = HiddenAttentionSummary.make(hiddenStates: [.approval, .error])

        #expect(summary == HiddenAttentionSummary(kind: nil, count: 2))
    }

    @Test("対応待ちが隠れていなければ出さない")
    func noneHidden() {
        #expect(HiddenAttentionSummary.make(hiddenStates: [.running, .done]) == nil)
    }
}

@Suite("プロジェクトのターミナルタブ")
@MainActor
struct ProjectTerminalStoreTests {

    @Test("ターミナルタブのシェルはそのプロジェクトのフォルダ で起動し、同じタブでは使い回す")
    func terminalStartsInProjectFolder() async throws {
        let pty = MockPTYManager()
        let store = ProjectTerminalStore { workingDirectory in
            TerminalPanelSession(controller: UserTerminalController(
                pty: pty,
                shellPath: "/bin/sh",
                workingDirectory: workingDirectory,
                environment: ["PATH": "/usr/bin:/bin"]
            ))
        }
        let session = TerminalTabID()
        let project = ProjectID()

        let terminal = store.terminal(for: session, projectID: project, workingDirectory: "/tmp/phlox-project")
        let again = store.terminal(for: session, projectID: project, workingDirectory: "/tmp/phlox-project")
        await terminal.ensureStarted()

        #expect(terminal === again)
        #expect(pty.spawnCalls.map(\.workingDirectory) == ["/tmp/phlox-project"])
        #expect(store.isRunning(session))
        await store.close(session)?.value
    }

    @Test("プロジェクトのフォルダが変わったら、旧い場所のシェルを止めて新しい場所で作り直す")
    func workspaceChangeRecreatesShell() async throws {
        let pty = MockPTYManager()
        let store = ProjectTerminalStore { workingDirectory in
            TerminalPanelSession(controller: UserTerminalController(
                pty: pty,
                shellPath: "/bin/sh",
                workingDirectory: workingDirectory,
                environment: ["PATH": "/usr/bin:/bin"]
            ))
        }
        let session = TerminalTabID()
        let project = ProjectID()
        let old = store.terminal(for: session, projectID: project, workingDirectory: "/tmp/old-worktree")
        await old.ensureStarted()

        let moved = store.terminal(for: session, projectID: project, workingDirectory: "/tmp/new-worktree")
        await moved.ensureStarted()
        try await waitUntil { old.controller.isRunning == false }

        #expect(moved !== old)
        #expect(old.controller.isRunning == false)
        #expect(pty.spawnCalls.map(\.workingDirectory) == ["/tmp/old-worktree", "/tmp/new-worktree"])
        await store.close(session)?.value
    }

    @Test("タブを閉じるとシェルを止め、次に開くと新しいシェルになる")
    func closingStopsShell() async throws {
        let pty = MockPTYManager()
        let store = ProjectTerminalStore { workingDirectory in
            TerminalPanelSession(controller: UserTerminalController(
                pty: pty,
                shellPath: "/bin/sh",
                workingDirectory: workingDirectory,
                environment: ["PATH": "/usr/bin:/bin"]
            ))
        }
        let session = TerminalTabID()
        let project = ProjectID()
        let first = store.terminal(for: session, projectID: project, workingDirectory: "/tmp/wt")
        await first.ensureStarted()

        await store.close(session)?.value
        let reopened = store.terminal(for: session, projectID: project, workingDirectory: "/tmp/wt")

        #expect(first.controller.isRunning == false)
        #expect(store.isRunning(session) == false)
        #expect(reopened !== first)
    }
}

/// 旧いシェルの停止は置き場の外で非同期に進むため、観測できるまで待つ。
@MainActor
private func waitUntil(timeout: Duration = .seconds(1), _ condition: @MainActor () -> Bool) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else { throw WaitTimeout() }
        await Task.yield()
    }
}

private struct WaitTimeout: Error {}

@Suite("⌘P で選んだファイルの相対パス")
struct FileOpenRelativePathTests {

    @Test("worktree の中なら直下からの相対パス、外なら開かない")
    func relativePathInsideRootOnly() {
        let root = "/tmp/phlox-root"

        let inside = DashboardView.relativePath(of: URL(fileURLWithPath: "/tmp/phlox-root/Sources/App.swift"), under: root)
        let outside = DashboardView.relativePath(of: URL(fileURLWithPath: "/tmp/phlox-rootless/App.swift"), under: root)

        #expect(inside == "Sources/App.swift")
        #expect(outside == nil)
    }
}

