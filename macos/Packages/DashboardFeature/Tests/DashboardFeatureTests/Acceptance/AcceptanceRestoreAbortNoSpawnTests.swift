import Foundation
import Testing
import AgentDomain
import HookServer
import MessageStore
import PTYKit
import SessionFeature
@testable import DashboardFeature

/// Acceptance: 隔離を中止した復元は、エージェントを 1 つも起動しない（task-2 契約）
///
/// **PM が凍結した受け入れテスト。実装役は編集してはならない。**
///
/// ## なぜこれが要るか
///
/// 独立レビューの切り分けで、「隔離できないので起動を中止する」と表示しておきながら
/// **150ms 後に同じセッションのエージェントを、隔離が拒否したまさにそのパスで起動する**経路が
/// 決定論的に再現した（静穏待ちを入れると 6/6 で発生）。連鎖は次のとおり:
///
/// 1. 復元が `prepareSessionLaunchAsync(..., isolationIntent: .restore)` で隔離に失敗して throw する（ここまでは契約どおり）。
/// 2. `catch` が `SessionSpawnService.makeRestoreErrorSession` を呼ぶ。この関数は **生きた `SpawnRequest`**
///    （`descriptor.workingDirectory` 入り）を持つ `SessionViewModel` を作る。
/// 3. 同関数の `terminalCoordinator.applyFontSize(...)` が SwiftTerm の `sizeChanged` → `onResize` を発火させる。
/// 4. `SessionViewModel.handleResize` は `!didSpawn` なので **150ms の debounce** を仕掛け、期限後に `spawnOnce` する。
/// 5. `markRestoreFailed` は `spawnRequest` も `initialSpawnTask` も武装解除しない。
///
/// チャット（appServer）側は `makeRestoreErrorChatSession` が意図的に起動しない設計になっており、
/// **PTY 側だけが非対称に生きた `SpawnRequest` を持つ**のがこの穴の正体である。
///
/// ## 実害
///
/// `worktreeCreationFailed` のケースは起動先が存在しないパスなのでプロセスは立たない見込みだが、
/// `.abort`（`branchAlreadyExists` / `worktreePathOccupied` / `notAGitRepository`）で中止した場合、
/// descriptor の `workingDirectory` は**実在する共有ディレクトリ**でありうる。そのとき
/// **隔離を拒否したままエージェントが共有ディレクトリで起動する**＝契約が名指しで禁じた
/// サイレントフォールバックが成立する。1 番目のテストがこれを凍結する。
///
/// ## 検証の作り
///
/// spawn は 150ms の debounce 越しに起きるため、`await dashboard.start()` の直後に
/// `spawnCalls.isEmpty` を見るだけでは**見逃す方向に**不安定になる（実測 5 回中 3 回すり抜けた）。
/// 「一定時間待っても起動が発生しないこと」を確かめる形にすること。
@Suite("Acceptance: 中止された復元は起動しない（task-2）", .serialized)
struct AcceptanceRestoreAbortNoSpawnTests {

    /// debounce（150ms）より十分長く待ち、「待っても起動しない」ことを確かめる。
    private static let quietPeriod = Duration.milliseconds(500)

    /// `.abort` で中止したのに、descriptor に記録された**実在する共有ディレクトリ**で
    /// エージェントが起動してしまわないこと。成立すると契約が禁じたサイレントフォールバックになる。
    @Test @MainActor
    func 隔離を中止した復元は共有ディレクトリでエージェントを起動しない() async throws {
        let ptyManager = MockPTYManager()
        let repository = try makeAcceptanceRestoreAbortRepository()
        let workspaceRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("phlox-abort-nospawn-shared-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
        let sessionID = SessionID()
        let worktreePath = workspaceRoot.appendingPathComponent(
            sessionID.rawValue.uuidString,
            isDirectory: true
        )
        // worktree として登録されていない実ディレクトリを置く → `.abort(.worktreePathOccupied)` を誘発する。
        try FileManager.default.createDirectory(at: worktreePath, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: workspaceRoot)
            try? FileManager.default.removeItem(at: repository)
        }

        let project = Project(
            name: "abort-shared",
            directoryPath: repository.path,
            createdAt: Date(timeIntervalSince1970: 0),
            isManagedDirectory: false,
            worktreeIsolationEnabled: true
        )
        let projectStore = AcceptanceRestoreAbortProjectStore()
        try await projectStore.save([project])
        let descriptor = PersistedSessionDescriptor(
            id: sessionID,
            kind: .codex,
            // 隔離が中止されたとき、ここへ落ちて起動してはならない（＝共有ディレクトリ）。
            workingDirectory: repository.path,
            name: "aborted",
            projectID: project.id,
            startedAt: Date(timeIntervalSince1970: 0),
            command: "/usr/local/bin/codex",
            args: [],
            env: [:]
        )
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let environment = makeTestEnvironment(
            pty: ptyManager,
            hookStream: hookStream,
            projects: projectStore,
            sessions: AcceptanceRestoreAbortSessionStore([descriptor]),
            workspaceDirectory: workspaceRoot,
            agentBinaryPaths: [.codex: "/usr/local/bin/codex"]
        )
        let dashboard = DashboardViewModel(
            environment: environment,
            codexUserHooksEnabledProvider: { true }
        )

        await dashboard.start()
        // debounce 越しの遅延起動を取りこぼさないための静穏待ち。短くしないこと。
        try await Task.sleep(for: Self.quietPeriod)

        #expect(
            ptyManager.spawnCalls.isEmpty,
            "隔離を中止したのにエージェントを起動している: \(ptyManager.spawnCalls.map(\.workingDirectory))"
        )
    }

    /// worktree の生成そのものに失敗したときも、エージェントを起動しないこと。
    @Test @MainActor
    func worktree生成に失敗した復元はエージェントを起動しない() async throws {
        let ptyManager = MockPTYManager()
        let repository = try makeAcceptanceRestoreAbortRepository()
        let workspaceRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("phlox-abort-nospawn-failed-\(UUID().uuidString)", isDirectory: true)
        // ワークスペース基点を**ファイル**にして、worktree の親ディレクトリ生成を必ず失敗させる。
        try Data("workspace root is intentionally a file\n".utf8).write(to: workspaceRoot)
        let sessionID = SessionID()
        let worktreePath = workspaceRoot.appendingPathComponent(
            sessionID.rawValue.uuidString,
            isDirectory: true
        )
        defer {
            try? FileManager.default.removeItem(at: workspaceRoot)
            try? FileManager.default.removeItem(at: repository)
        }

        let project = Project(
            name: "abort-failed-creation",
            directoryPath: repository.path,
            createdAt: Date(timeIntervalSince1970: 0),
            isManagedDirectory: false,
            worktreeIsolationEnabled: true
        )
        let projectStore = AcceptanceRestoreAbortProjectStore()
        try await projectStore.save([project])
        let descriptor = PersistedSessionDescriptor(
            id: sessionID,
            kind: .codex,
            workingDirectory: worktreePath.path,
            name: "failed-creation",
            projectID: project.id,
            startedAt: Date(timeIntervalSince1970: 0),
            command: "/usr/local/bin/codex",
            args: [],
            env: [:]
        )
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let environment = makeTestEnvironment(
            pty: ptyManager,
            hookStream: hookStream,
            projects: projectStore,
            sessions: AcceptanceRestoreAbortSessionStore([descriptor]),
            workspaceDirectory: workspaceRoot,
            agentBinaryPaths: [.codex: "/usr/local/bin/codex"]
        )
        let dashboard = DashboardViewModel(
            environment: environment,
            codexUserHooksEnabledProvider: { true }
        )

        await dashboard.start()
        try await Task.sleep(for: Self.quietPeriod)

        #expect(
            ptyManager.spawnCalls.isEmpty,
            "worktree を作れなかったのにエージェントを起動している: \(ptyManager.spawnCalls.map(\.workingDirectory))"
        )
    }
}

// MARK: - このスイート専用の最小フィクスチャ
//
// 実装役が所有するテストファイルのヘルパーに依存させない（凍結テストの独立性を保つため）。

private actor AcceptanceRestoreAbortProjectStore: ProjectStoreProtocol {
    private var stored: [Project] = []

    func load() async -> [Project] {
        stored
    }

    func save(_ projects: [Project]) async throws {
        stored = projects
    }
}

private actor AcceptanceRestoreAbortSessionStore: SessionStoreProtocol {
    private var stored: [PersistedSessionDescriptor]

    init(_ stored: [PersistedSessionDescriptor] = []) {
        self.stored = stored
    }

    func load() async -> [PersistedSessionDescriptor] {
        stored
    }

    func save(_ sessions: [PersistedSessionDescriptor]) async throws {
        stored = sessions
    }
}

private struct AcceptanceRestoreAbortGitError: Error {}

@discardableResult
private func runAcceptanceRestoreAbortGit(_ arguments: [String], in directory: URL) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = arguments
    process.currentDirectoryURL = directory

    var environment = ProcessInfo.processInfo.environment
    environment["GIT_CONFIG_NOSYSTEM"] = "1"
    process.environment = environment

    let output = Pipe()
    process.standardOutput = output
    process.standardError = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw AcceptanceRestoreAbortGitError()
    }
    return String(decoding: data, as: UTF8.self)
}

private func makeAcceptanceRestoreAbortRepository() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("phlox-abort-nospawn-repo-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try runAcceptanceRestoreAbortGit(["init", "-q", "-b", "main"], in: root)
    try runAcceptanceRestoreAbortGit(["config", "user.email", "acceptance@example.com"], in: root)
    try runAcceptanceRestoreAbortGit(["config", "user.name", "Acceptance"], in: root)
    try Data("seed\n".utf8).write(to: root.appendingPathComponent("README.md"))
    try runAcceptanceRestoreAbortGit(["add", "."], in: root)
    try runAcceptanceRestoreAbortGit(["commit", "-q", "-m", "seed"], in: root)
    return root
}
