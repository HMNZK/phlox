import Foundation
import AgentDomain
import Testing
@testable import DashboardFeature

@Suite("EditorPanelCoordinator")
struct EditorPanelCoordinatorTests {
    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("phlox-editor-coordinator-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func git(_ arguments: [String], in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = [
            "-c", "user.name=phlox-test",
            "-c", "user.email=test@phlox.local",
            "-c", "commit.gpgsign=false",
            "-c", "core.hooksPath=/dev/null",
        ] + arguments
        process.currentDirectoryURL = directory
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_CONFIG_NOSYSTEM"] = "1"
        process.environment = environment

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        try #require(process.terminationStatus == 0, "git \(arguments.joined(separator: " ")) failed: \(text)")
        return text
    }

    private func makeGitRepository() throws -> URL {
        let root = try makeTempDir()
        try git(["init", "-q"], in: root)
        try "before\n".write(
            to: root.appendingPathComponent("a.txt"),
            atomically: true,
            encoding: .utf8
        )
        try git(["add", "a.txt"], in: root)
        try git(["commit", "-q", "-m", "base"], in: root)
        try "after\n".write(
            to: root.appendingPathComponent("a.txt"),
            atomically: true,
            encoding: .utf8
        )
        return root
    }

    private func workspace(_ sessionID: SessionID, _ repository: URL) -> SessionWorkspace {
        SessionWorkspace(
            sessionID: sessionID,
            workingDirectory: repository.path,
            isActive: true
        )
    }

    private func repositoryRoot(_ repository: URL) throws -> String {
        try git(["rev-parse", "--show-toplevel"], in: repository)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @Test("共有相手が増えてもVMは作り直されずドラフトが残り注記だけ更新される")
    @MainActor
    func sharedPeerChangePreservesViewModelState() async throws {
        let coordinator = EditorPanelCoordinator()
        let repository = try makeGitRepository()
        let expectedRoot = try repositoryRoot(repository)
        let selected = SessionID()
        let peer = SessionID()
        let alone = [workspace(selected, repository)]

        coordinator.update(selectedSessionID: selected, workspaces: alone)
        await coordinator.resolve(workspaces: alone)
        let viewModel = coordinator.viewModel
        await viewModel.select("a.txt")
        viewModel.draft = "編集中"

        let shared = alone + [workspace(peer, repository)]
        coordinator.update(selectedSessionID: selected, workspaces: shared)
        #expect(coordinator.target.peerCount == 1)
        await coordinator.resolve(workspaces: shared)

        #expect(coordinator.viewModel === viewModel)
        #expect(coordinator.viewModel.selectedPath == "a.txt")
        #expect(coordinator.viewModel.draft == "編集中")
        #expect(
            coordinator.viewModel.changeScope
                == .shared(repositoryRoot: expectedRoot, peerCount: 1)
        )
    }

    @Test("ドロワーを閉じて開き直すと変更一覧が再取得される")
    @MainActor
    func reopeningDrawerRefreshesChanges() async throws {
        let repository = try makeGitRepository()
        let selected = SessionID()
        let workspaces = [workspace(selected, repository)]

        let coordinator = EditorPanelCoordinator()
        coordinator.update(selectedSessionID: selected, workspaces: workspaces)
        await coordinator.resolve(workspaces: workspaces)
        #expect(coordinator.viewModel.changes.map(\.path) == ["a.txt"])

        try "new\n".write(
            to: repository.appendingPathComponent("b.txt"),
            atomically: true,
            encoding: .utf8
        )

        await coordinator.resolve(workspaces: workspaces)
        #expect(coordinator.viewModel.changes.map(\.path).sorted() == ["a.txt", "b.txt"])
    }

    @Test("git リポジトリでない作業ディレクトリなら notARepository を出す")
    @MainActor
    func nonRepositoryWorkspaceShowsNotARepository() async throws {
        let plain = try makeTempDir()
        let selected = SessionID()
        let workspaces = [workspace(selected, plain)]

        let coordinator = EditorPanelCoordinator()
        coordinator.update(selectedSessionID: selected, workspaces: workspaces)
        await coordinator.resolve(workspaces: workspaces)

        #expect(coordinator.viewModel.changeScope == .unavailable)
        #expect(coordinator.viewModel.listState == .notARepository)
    }

    @Test("選択セッションが変わると変更一覧の対象が切り替わる")
    @MainActor
    func switchingSelectedSessionChangesRepositoryScope() async throws {
        let coordinator = EditorPanelCoordinator()
        let repositoryA = try makeGitRepository()
        let repositoryB = try makeGitRepository()
        let expectedRootB = try repositoryRoot(repositoryB)
        let sessionA = SessionID()
        let sessionB = SessionID()
        let workspaces = [
            workspace(sessionA, repositoryA),
            workspace(sessionB, repositoryB),
        ]

        coordinator.update(selectedSessionID: sessionA, workspaces: workspaces)
        await coordinator.resolve(workspaces: workspaces)
        coordinator.update(selectedSessionID: sessionB, workspaces: workspaces)
        await coordinator.resolve(workspaces: workspaces)

        #expect(coordinator.viewModel.listState == .ready)
        #expect(coordinator.viewModel.changeScope.repositoryRoot == expectedRootB)
        #expect(coordinator.viewModel.changes.map(\.path) == ["a.txt"])
    }

    @Test("非gitで初回解決した後に git init されても共有相手がいれば注記が出る")
    @MainActor
    func lateGitInitStillReportsSharedScope() async throws {
        let dir = try makeTempDir()
        let selected = SessionID()
        let peer = SessionID()
        let alone = [workspace(selected, dir)]

        let coordinator = EditorPanelCoordinator()
        coordinator.update(selectedSessionID: selected, workspaces: alone)
        await coordinator.resolve(workspaces: alone)
        #expect(coordinator.viewModel.changeScope == .unavailable)

        try git(["init", "-q"], in: dir)
        try "x\n".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

        let shared = alone + [workspace(peer, dir)]
        coordinator.update(selectedSessionID: selected, workspaces: shared)
        await coordinator.resolve(workspaces: shared)

        #expect(coordinator.viewModel.listState == .ready)
        if case .shared(_, let peerCount) = coordinator.viewModel.changeScope {
            #expect(peerCount == 1)
        } else {
            Issue.record("共有相手がいるのに \(coordinator.viewModel.changeScope) になった")
        }
    }

    @Test("閉じたまま別セッションを経由して戻ってきても変更一覧が復元される")
    @MainActor
    func switchingAwayAndBackBeforeResolvingRestoresChanges() async throws {
        let coordinator = EditorPanelCoordinator()
        let repositoryA = try makeGitRepository()
        let repositoryB = try makeGitRepository()
        let expectedRootA = try repositoryRoot(repositoryA)
        let sessionA = SessionID()
        let sessionB = SessionID()
        let workspaces = [
            workspace(sessionA, repositoryA),
            workspace(sessionB, repositoryB),
        ]

        coordinator.update(selectedSessionID: sessionA, workspaces: workspaces)
        await coordinator.resolve(workspaces: workspaces)
        #expect(coordinator.viewModel.listState == .ready)

        // エディタドロワーを閉じている間は B の解決を行わず、A へ戻る。
        coordinator.update(selectedSessionID: sessionB, workspaces: workspaces)
        coordinator.update(selectedSessionID: sessionA, workspaces: workspaces)
        await coordinator.resolve(workspaces: workspaces)

        #expect(coordinator.viewModel.listState == .ready)
        #expect(coordinator.viewModel.changes.count == 1)
        #expect(coordinator.viewModel.changeScope.repositoryRoot == expectedRootA)
    }
}
