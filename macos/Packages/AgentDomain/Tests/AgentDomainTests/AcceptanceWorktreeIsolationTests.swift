// 契約の正本: tasks/task-2.md — セッションごとの git worktree 隔離（オプトイン）。
// このファイルは PM が凍結する受け入れテスト。実装役はアサーションを変更禁止
// （テストハーネスの欠陥を発見した場合は、PM に報告し承認を得たうえでハーネス部分に限り修理してよい）。
//
// 契約の核心は 2 つ:
//  (1) 既定（フラグ未設定＝旧 projects.json）は従来どおり。挙動を 1 行も変えない。
//  (2) 隔離できないときは **起動を中止する**。共有ディレクトリへ黙って落とさない
//      （ゲート①でユーザーが「起動を中止する」を選択。decision-log.md 参照）。

import Foundation
import Testing
@testable import AgentDomain

@Suite("Acceptance: worktree 隔離（task-2）")
struct AcceptanceWorktreeIsolationTests {
    private func makeProject(worktreeIsolationEnabled: Bool?) -> Project {
        Project(
            name: "sample",
            directoryPath: "/tmp/phlox-wt/repo",
            createdAt: Date(timeIntervalSince1970: 0),
            isManagedDirectory: false,
            worktreeIsolationEnabled: worktreeIsolationEnabled
        )
    }

    private let workspaceDir = "/tmp/phlox-wt/workspace/session"

    // MARK: - 旧スキーマ互換（R1: これを壊すとユーザーのプロジェクト一覧が消える）

    @Test func 旧スキーマのJSONがデコードでき隔離は無効になる() throws {
        // worktreeIsolationEnabled キーを持たない、実際に保存されている形の JSON。
        let json = """
        {
          "id": { "rawValue": "3F2504E0-4F89-11D3-9A0C-0305E82C3301" },
          "name": "legacy",
          "directoryPath": "/tmp/phlox-wt/legacy",
          "createdAt": 0,
          "isManagedDirectory": false
        }
        """
        let project = try JSONDecoder().decode(Project.self, from: Data(json.utf8))
        #expect(project.worktreeIsolationEnabled == nil)
        #expect(project.usesWorktreeIsolation == false)
        #expect(project.name == "legacy")
    }

    @Test func 隔離フラグをつけた場合もエンコードとデコードで往復する() throws {
        let original = makeProject(worktreeIsolationEnabled: true)
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(Project.self, from: data)
        #expect(restored.usesWorktreeIsolation)
        #expect(restored == original)
    }

    // MARK: - 既定（off）は従来どおり

    @Test func フラグ未設定なら隔離しない() {
        let outcome = WorktreeIsolationPlanner.plan(
            project: makeProject(worktreeIsolationEnabled: nil),
            sessionID: SessionID(),
            sessionWorkspaceDirectory: workspaceDir,
            isGitRepository: true,
            existingBranchNames: [],
            worktreePathExists: false
        )
        #expect(outcome == .disabled)
    }

    @Test func フラグがfalseなら隔離しない() {
        let outcome = WorktreeIsolationPlanner.plan(
            project: makeProject(worktreeIsolationEnabled: false),
            sessionID: SessionID(),
            sessionWorkspaceDirectory: workspaceDir,
            isGitRepository: true,
            existingBranchNames: [],
            worktreePathExists: false
        )
        #expect(outcome == .disabled)
    }

    @Test func プロジェクト未所属のセッションは隔離しない() {
        let outcome = WorktreeIsolationPlanner.plan(
            project: nil,
            sessionID: SessionID(),
            sessionWorkspaceDirectory: workspaceDir,
            isGitRepository: true,
            existingBranchNames: [],
            worktreePathExists: false
        )
        #expect(outcome == .disabled)
    }

    // MARK: - on の正常系

    @Test func フラグがtrueでgitリポジトリなら専用worktreeを作る() {
        let sessionID = SessionID()
        let outcome = WorktreeIsolationPlanner.plan(
            project: makeProject(worktreeIsolationEnabled: true),
            sessionID: sessionID,
            sessionWorkspaceDirectory: workspaceDir,
            isGitRepository: true,
            existingBranchNames: [],
            worktreePathExists: false
        )
        guard case let .create(worktreePath, branchName) = outcome else {
            Issue.record("期待は .create だが \(outcome) だった")
            return
        }
        #expect(worktreePath == workspaceDir)
        #expect(branchName == WorktreeIsolationPlanner.branchName(for: sessionID))
        #expect(!branchName.isEmpty)
    }

    @Test func ブランチ名はセッションごとに異なる() {
        let a = WorktreeIsolationPlanner.branchName(for: SessionID())
        let b = WorktreeIsolationPlanner.branchName(for: SessionID())
        #expect(a != b)
    }

    @Test func ブランチ名はgitのrefnameとして使える文字だけを含む() {
        let name = WorktreeIsolationPlanner.branchName(for: SessionID())
        #expect(!name.isEmpty)
        // git check-ref-format が拒否する代表的な文字・並びを含まないこと。
        for forbidden in [" ", "~", "^", ":", "?", "*", "[", "\\", "..", "@{", "//"] {
            #expect(!name.contains(forbidden), "ブランチ名に \(forbidden) が含まれている: \(name)")
        }
        #expect(!name.hasPrefix("/"))
        #expect(!name.hasSuffix("/"))
        #expect(!name.hasSuffix(".lock"))
    }

    // MARK: - on の失敗系（すべて中止。フォールバックしない）

    @Test func gitリポジトリでなければ起動を中止する() {
        let outcome = WorktreeIsolationPlanner.plan(
            project: makeProject(worktreeIsolationEnabled: true),
            sessionID: SessionID(),
            sessionWorkspaceDirectory: workspaceDir,
            isGitRepository: false,
            existingBranchNames: [],
            worktreePathExists: false
        )
        #expect(outcome == .abort(.notAGitRepository(path: "/tmp/phlox-wt/repo")))
    }

    @Test func 同名ブランチが既にあれば起動を中止する() {
        let sessionID = SessionID()
        let branch = WorktreeIsolationPlanner.branchName(for: sessionID)
        let outcome = WorktreeIsolationPlanner.plan(
            project: makeProject(worktreeIsolationEnabled: true),
            sessionID: sessionID,
            sessionWorkspaceDirectory: workspaceDir,
            isGitRepository: true,
            existingBranchNames: [branch],
            worktreePathExists: false
        )
        #expect(outcome == .abort(.branchAlreadyExists(branch)))
    }

    @Test func worktreeパスが既に使われていれば起動を中止する() {
        let outcome = WorktreeIsolationPlanner.plan(
            project: makeProject(worktreeIsolationEnabled: true),
            sessionID: SessionID(),
            sessionWorkspaceDirectory: workspaceDir,
            isGitRepository: true,
            existingBranchNames: [],
            worktreePathExists: true
        )
        #expect(outcome == .abort(.worktreePathOccupied(workspaceDir)))
    }

    // MARK: - 復元（同じ SessionID で再度呼ばれる経路）
    //
    // `SessionRestoreCoordinator` は `spawnNewSessionImpl` を経由せず `prepareSessionLaunch` を
    // 直接呼び、`sessionID` は初回と同じ。`branchName(for:)` は SessionID の純関数なので、
    // 新規と同じ規則で判定すると必ず `.abort(.branchAlreadyExists)` になり、隔離セッションは
    // **アプリ再起動後に二度と復元できず worktree とブランチが恒久的に残る**。
    // 独立レビューが実 git で再現した MUST 指摘への対処として、復元は再利用を正とする。

    @Test func 復元時に登録済みworktreeがあればそれを再利用する() {
        let sessionID = SessionID()
        let branch = WorktreeIsolationPlanner.branchName(for: sessionID)
        let outcome = WorktreeIsolationPlanner.plan(
            project: makeProject(worktreeIsolationEnabled: true),
            sessionID: sessionID,
            sessionWorkspaceDirectory: workspaceDir,
            isGitRepository: true,
            existingBranchNames: [branch],
            worktreePathExists: true,
            isRegisteredWorktree: true,
            intent: .restore
        )
        #expect(outcome == .reuse(worktreePath: workspaceDir, branchName: branch))
    }

    @Test func 復元時にブランチだけ残りworktreeが失われていれば作り直す() {
        let sessionID = SessionID()
        let branch = WorktreeIsolationPlanner.branchName(for: sessionID)
        let outcome = WorktreeIsolationPlanner.plan(
            project: makeProject(worktreeIsolationEnabled: true),
            sessionID: sessionID,
            sessionWorkspaceDirectory: workspaceDir,
            isGitRepository: true,
            existingBranchNames: [branch],
            worktreePathExists: false,
            isRegisteredWorktree: false,
            intent: .restore
        )
        #expect(outcome == .recreate(worktreePath: workspaceDir, branchName: branch))
    }

    /// git には worktree の登録が残っているのに、実ディレクトリが消えている状態（`git worktree list --porcelain`
    /// が `prunable` を付けて報告する）。`isRegisteredWorktree` だけを見て `.reuse` にすると、
    /// 存在しない作業ディレクトリで PTY を起動しようとして毎回失敗し、`git worktree prune` を
    /// 人が手で叩くまで復元できなくなる。**登録の有無ではなく、実体があるかで判定すること。**
    @Test func 復元時に登録だけ残りディレクトリが失われていれば作り直す() {
        let sessionID = SessionID()
        let branch = WorktreeIsolationPlanner.branchName(for: sessionID)
        let outcome = WorktreeIsolationPlanner.plan(
            project: makeProject(worktreeIsolationEnabled: true),
            sessionID: sessionID,
            sessionWorkspaceDirectory: workspaceDir,
            isGitRepository: true,
            existingBranchNames: [branch],
            worktreePathExists: false,
            isRegisteredWorktree: true,
            intent: .restore
        )
        #expect(outcome == .recreate(worktreePath: workspaceDir, branchName: branch))
    }

    @Test func 復元時にパスはあるがworktreeとして未登録なら中止する() {
        let sessionID = SessionID()
        let outcome = WorktreeIsolationPlanner.plan(
            project: makeProject(worktreeIsolationEnabled: true),
            sessionID: sessionID,
            sessionWorkspaceDirectory: workspaceDir,
            isGitRepository: true,
            existingBranchNames: [],
            worktreePathExists: true,
            isRegisteredWorktree: false,
            intent: .restore
        )
        #expect(outcome == .abort(.worktreePathOccupied(workspaceDir)))
    }

    @Test func 復元でも隔離フラグがoffなら従来どおり() {
        let outcome = WorktreeIsolationPlanner.plan(
            project: makeProject(worktreeIsolationEnabled: false),
            sessionID: SessionID(),
            sessionWorkspaceDirectory: workspaceDir,
            isGitRepository: true,
            existingBranchNames: [],
            worktreePathExists: false,
            isRegisteredWorktree: false,
            intent: .restore
        )
        #expect(outcome == .disabled)
    }

    @Test func 復元でブランチもworktreeも無ければ新規に作る() {
        let sessionID = SessionID()
        let branch = WorktreeIsolationPlanner.branchName(for: sessionID)
        let outcome = WorktreeIsolationPlanner.plan(
            project: makeProject(worktreeIsolationEnabled: true),
            sessionID: sessionID,
            sessionWorkspaceDirectory: workspaceDir,
            isGitRepository: true,
            existingBranchNames: [],
            worktreePathExists: false,
            isRegisteredWorktree: false,
            intent: .restore
        )
        #expect(outcome == .create(worktreePath: workspaceDir, branchName: branch))
    }

    @Test func 復元でも非gitリポジトリなら中止する() {
        let outcome = WorktreeIsolationPlanner.plan(
            project: makeProject(worktreeIsolationEnabled: true),
            sessionID: SessionID(),
            sessionWorkspaceDirectory: workspaceDir,
            isGitRepository: false,
            existingBranchNames: [],
            worktreePathExists: true,
            isRegisteredWorktree: true,
            intent: .restore
        )
        #expect(outcome == .abort(.notAGitRepository(path: "/tmp/phlox-wt/repo")))
    }

    /// 新規 spawn 側の規則が復元の追加で緩んでいないこと。登録済み worktree があっても
    /// 新規セッションでは再利用せず中止する（別セッションの作業ツリーを奪わない）。
    @Test func 新規セッションは登録済みworktreeがあっても再利用しない() {
        let sessionID = SessionID()
        let outcome = WorktreeIsolationPlanner.plan(
            project: makeProject(worktreeIsolationEnabled: true),
            sessionID: sessionID,
            sessionWorkspaceDirectory: workspaceDir,
            isGitRepository: true,
            existingBranchNames: [WorktreeIsolationPlanner.branchName(for: sessionID)],
            worktreePathExists: true,
            isRegisteredWorktree: true,
            intent: .newSession
        )
        if case .reuse = outcome {
            Issue.record("新規セッションで既存 worktree を再利用している: \(outcome)")
        }
        if case .recreate = outcome {
            Issue.record("新規セッションで既存ブランチから作り直している: \(outcome)")
        }
        #expect(outcome == .abort(.branchAlreadyExists(WorktreeIsolationPlanner.branchName(for: sessionID))))
    }

    @Test func 失敗時に従来の共有ディレクトリへフォールバックしない() {
        // 隔離できない条件をすべて同時に与えても、.disabled（＝従来挙動で起動）にはならない。
        for (isRepo, branches, pathExists) in [
            (false, Set<String>(), false),
            (true, Set(["dummy"]), true),
            (false, Set<String>(), true),
        ] {
            let sessionID = SessionID()
            var branchSet = branches
            if branchSet.contains("dummy") {
                branchSet = [WorktreeIsolationPlanner.branchName(for: sessionID)]
            }
            let outcome = WorktreeIsolationPlanner.plan(
                project: makeProject(worktreeIsolationEnabled: true),
                sessionID: sessionID,
                sessionWorkspaceDirectory: workspaceDir,
                isGitRepository: isRepo,
                existingBranchNames: branchSet,
                worktreePathExists: pathExists
            )
            #expect(outcome != .disabled, "隔離失敗時に従来挙動へフォールバックしている: \(outcome)")
            if case .create = outcome {
                Issue.record("隔離できない条件なのに .create を返した: \(outcome)")
            }
        }
    }
}
